import Foundation
import AVFoundation
import AppKit
import ScreenCaptureKit

/// Headless render check: `Framecast --selftest <video> <outDir>`
/// Builds a project from a video with simulated cursor movement and clicks, then exports MP4 + GIF.
enum SelfTest {
    static func runIfRequested() {
        let args = CommandLine.arguments
        if args.contains("--checks") {
            Task { @MainActor in
                let failures = await runChecks(video: args.last.map { URL(fileURLWithPath: $0) })
                print(failures == 0 ? "CHECKS OK" : "CHECKS FAILED: \(failures)")
                exit(failures == 0 ? 0 : 1)
            }
            return
        }
        if let i = args.firstIndex(of: "--recordtest"), args.count > i + 2 {
            let seconds = Double(args[i + 1]) ?? 4
            let outDir = URL(fileURLWithPath: args[i + 2])
            Task { @MainActor in
                do {
                    try await recordTest(seconds: seconds, outDir: outDir)
                    print("RECORDTEST OK")
                    exit(0)
                } catch {
                    print("RECORDTEST FAILED: \(error)")
                    exit(1)
                }
            }
            return
        }
        guard let i = args.firstIndex(of: "--selftest"), args.count > i + 2 else { return }
        let video = URL(fileURLWithPath: args[i + 1])
        let outDir = URL(fileURLWithPath: args[i + 2])
        Task { @MainActor in
            do {
                try await run(video: video, outDir: outDir)
                print("SELFTEST OK")
                exit(0)
            } catch {
                print("SELFTEST FAILED: \(error)")
                exit(1)
            }
        }
    }

    /// Logic checks for the trickiest pieces: `Framecast --checks [video]`.
    @MainActor
    private static func runChecks(video: URL?) async -> Int {
        var failures = 0
        func check(_ ok: Bool, _ name: String) {
            print((ok ? "  ok   " : "  FAIL ") + name)
            if !ok { failures += 1 }
        }

        // Clock: samples are placed by their own timestamp around pauses.
        let clock = RecordingClock()
        clock.begin()
        let t0 = RecordingClock.hostNow
        try? await Task.sleep(nanoseconds: 200_000_000)
        let beforePause = RecordingClock.hostNow
        clock.pause()
        try? await Task.sleep(nanoseconds: 300_000_000)
        let duringPause = RecordingClock.hostNow
        clock.resume()
        try? await Task.sleep(nanoseconds: 100_000_000)
        let afterResume = RecordingClock.hostNow
        let late = clock.recordingTime(hostTime: beforePause) // delivered after the resume
        check(late != nil && abs(late! - CMTimeSubtract(beforePause, t0).seconds) < 0.01, "late sample from before a pause keeps its time")
        check(clock.offset(forHostTime: duringPause) == nil, "sample inside a pause is dropped")
        let after = clock.recordingTime(hostTime: afterResume) ?? -1
        check(after > 0.25 && after < 0.4, "time after resume excludes the pause (\(String(format: "%.2f", after))s)")
        let total = clock.stop().seconds
        check(total > 0.25 && total < 0.45, "duration excludes the pause (\(String(format: "%.2f", total))s)")
        check(clock.offset(forHostTime: CMTimeAdd(RecordingClock.hostNow, CMTime(seconds: 1, preferredTimescale: 600))) == nil, "samples after stop are dropped")

        // Updater version ordering.
        check(Updater.isNewer("1.1.1", than: "1.1.0"), "1.1.1 > 1.1.0")
        check(!Updater.isNewer("1.1.0", than: "1.1.0"), "same version is not newer")
        check(Updater.isNewer("1.2.0", than: "1.2.0-beta.1"), "release beats its pre-release")
        check(!Updater.isNewer("1.2.0-beta.1", than: "1.2.0"), "pre-release doesn't beat the release")
        check(!Updater.isNewer("1.2", than: "1.1.0"), "malformed tag is ignored")

        // Lenient decoding keeps good values and drops only bad ones.
        let style = decodeWithDefaults(Style.self, from: ["padding": 0.2, "aspect": "futureAspect", "camera": ["size": 0.4, "shape": "hexagon"]], defaults: Style())
        check(abs(style.padding - 0.2) < 0.0001, "valid value survives next to an invalid one")
        check(style.aspect == .auto, "invalid aspect falls back to default")
        check(abs(style.camera.size - 0.4) < 0.0001 && style.camera.shape == .circle, "nested: good kept, bad dropped")

        // ClipOps never leaves slivers and keeps total source coverage when speeding up.
        let clips = ClipOps.apply([(0.03, 2.0), (5.0, 9.97)], to: [Clip(start: 0, end: 10)], speed: 4)
        let covered = clips.reduce(0) { $0 + $1.duration }
        check(abs(covered - 10) < 0.0001, "speed-up keeps all footage (\(clips.count) pieces)")
        check(clips.first?.start == 0 && clips.last?.end == 10, "no slivers at the edges")
        check(zip(clips, clips.dropFirst()).allSatisfy { abs($0.end - $1.start) < 0.0001 }, "pieces are contiguous")
        let merged = ClipOps.apply([(1, 3), (3.3, 6), (9.7, 9.9)], to: [Clip(start: 0, end: 10)], speed: 4)
        check(merged.allSatisfy { $0.duration >= 0.5 }, "no pieces shorter than 0.5 s (\(merged.map { String(format: "%.1f", $0.duration) }))")
        let ts = try? JSONDecoder().decode(TitleStyle.self, from: Data(#"{"card":"bogus","font":"serif","align":"left"}"#.utf8))
        check(ts?.card == .light && ts?.font == .serif && ts?.align == .left, "title style: bad value dropped, good kept")
        let oldTitle = try? JSONDecoder().decode(EffectSegment.self, from: Data(#"{"kind":"text","start":0,"end":2,"text":"Hi"}"#.utf8))
        check(oldTitle?.titleStyle == TitleStyle() && oldTitle?.subtitle == "", "titles from older projects get the classic look")
        // 10 s of audio, silent from 3 to 6 s: one pause found, trimmed so words aren't clipped.
        let wave: [Float] = (0..<100).map { i in (30..<60).contains(i) ? 0.01 : 0.5 }
        let quiet = ActivityAnalyzer.silentRanges(waveform: wave, duration: 10)
        check(quiet.count == 1 && abs(quiet[0].0 - 3.2) < 0.01 && abs(quiet[0].1 - 5.8) < 0.01, "silent pause found and trimmed (\(quiet))")
        let fx = try? JSONDecoder().decode(EffectSegment.self, from: Data(#"{"kind":"annotation","start":0,"end":2,"shape":"spiral"}"#.utf8))
        check(fx?.shape == .arrow && fx?.strokeWidth == 6, "arrow: unknown shape falls back, defaults kept")
        let held = EditMap(clips: [Clip.freezeFrame(at: 0, seconds: 2), Clip(start: Clip.freezeSliver, end: 3)])
        check(abs(held.duration - (2 + 3 - Clip.freezeSliver)) < 0.001 && held.segments.first?.freeze == true,
              "freeze frame adds its hold time (\(String(format: "%.2f", held.duration))s)")
        let map = EditMap(clips: [Clip(start: 0, end: 2), Clip(start: 5, end: 7, speed: 2)])
        check(abs(map.duration - 3) < 0.0001 && abs(map.compTime(source: 6) - 2.5) < 0.0001 && abs(map.compTime(source: 3) - 2) < 0.0001,
              "edited time closes cuts and applies speed")

        // Export cancel must return promptly (it used to hang waiting on the audio input).
        if let video, FileManager.default.fileExists(atPath: video.path) {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("framecast-checks-\(UUID().uuidString)")
            do {
                try await run(video: video, outDir: dir, exportFiles: false)
                let model = try EditorModel(folder: dir.appendingPathComponent("Test.framecast"))
                for _ in 0..<200 where !model.isReady { try await Task.sleep(nanoseconds: 50_000_000) }
                if let job = model.exportJob() {
                    let exp = Exporter()
                    let started = Date()
                    let task = Task { try await exp.export(job: job, settings: ExportSettings(), to: dir.appendingPathComponent("c.mp4")) { _ in } }
                    try await Task.sleep(nanoseconds: 700_000_000)
                    exp.cancel()
                    var cancelled = false
                    do { try await task.value } catch Exporter.ExportError.cancelled { cancelled = true } catch {}
                    let took = Date().timeIntervalSince(started)
                    check(cancelled && took < 5, "export cancel returns (\(String(format: "%.1f", took))s)")
                    check(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("c.mp4").path), "cancelled export leaves no file")
                }
            } catch {
                check(false, "export cancel setup: \(error)")
            }
            try? FileManager.default.removeItem(at: dir)
        }
        return failures
    }

    @MainActor
    private static func run(video: URL, outDir: URL, exportFiles: Bool = true) async throws {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let folder = outDir.appendingPathComponent("Test.framecast")
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent(ProjectFiles.cursors), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: video, to: folder.appendingPathComponent(ProjectFiles.screen))
        // Stand-in webcam so camera layouts and background effects are exercised too.
        try FileManager.default.copyItem(at: video, to: folder.appendingPathComponent(ProjectFiles.webcam))

        let asset = AVURLAsset(url: folder.appendingPathComponent(ProjectFiles.screen))
        let duration = try await asset.load(.duration).seconds
        let track = try await asset.loadTracks(withMediaType: .video).first!
        let size = try await track.load(.naturalSize)

        // Simulated cursor: wander, then click twice in different places.
        var cursor = CursorTrack()
        var t = 0.0
        while t < duration {
            let x = 0.5 + 0.35 * cos(t * 0.9) * (t < 3 ? 1 : 0.4)
            let y = 0.5 + 0.3 * sin(t * 1.3)
            cursor.samples.append(CursorSample(t: t, x: x, y: y))
            t += 1.0 / 120
        }
        cursor.clicks = [ClickEvent(t: 1.5, x: 0.7, y: 0.4, button: 0), ClickEvent(t: 2.2, x: 0.7, y: 0.45, button: 0),
                         ClickEvent(t: duration - 3, x: 0.3, y: 0.6, button: 0)]
        cursor.shapes = [CursorShapeChange(t: 0, id: "c0")]
        cursor.shapeInfo = ["c0": CursorShapeInfo(id: "c0", hotX: 4, hotY: 4, width: 24, height: 32, isArrow: true)]
        ProjectIO.saveCursor(cursor, folder: folder)

        let info = RecordingInfo(duration: duration, pointWidth: size.width / 2, pointHeight: size.height / 2,
                                 pixelWidth: Int(size.width), pixelHeight: Int(size.height),
                                 hasWebcam: true, hasMic: false, hasSystemAudio: false, sourceName: "Self test", hasCursorData: true)
        var style = Style()
        style.keystrokes = .all
        style.camera.background = .blur
        // Exercise the newer render options.
        style.crop = CropRect(x: 0.05, y: 0.04, w: 0.9, h: 0.9)
        style.motionBlur = 1
        style.shadowStyle = .directional
        style.inset = true
        style.cursorStyle = .gradient
        style.cursorRotation = .tilt
        style.background.kind = .gradient
        style.background.customGradient = [RGBA(hex: 0x4776E6), RGBA(hex: 0x8E54E9)]
        let zooms = ZoomGenerator.generate(from: cursor.clicks, duration: duration, scale: 2)
        var title = EffectSegment(kind: .text, start: 0, end: 2.6)
        title.text = "Framecast self-test"
        var blur = EffectSegment(kind: .blur, start: 3.0, end: 6.0)
        blur.x = 0.55; blur.y = 0.08; blur.w = 0.35; blur.h = 0.22
        var spot = EffectSegment(kind: .spotlight, start: 6.5, end: 8.5)
        spot.x = 0.1; spot.y = 0.45; spot.w = 0.4; spot.h = 0.3
        // An intro: a text slide over a 1.5 s freeze of the first frame.
        var slide = EffectSegment(kind: .slide, start: 0, end: Clip.freezeSliver)
        slide.text = "Intro slide"; slide.subtitle = "Freeze frame behind it"; slide.slideBackground = .color
        let effects = [slide, title, blur, spot,
                       EffectSegment(kind: .hideCursor, start: 4.0, end: 5.2),
                       EffectSegment(kind: .cameraFull, start: duration * 0.72, end: duration * 0.93)]
        let captions = [CaptionCue(start: 0.4, end: 3.0, text: "Welcome to Framecast, the screen recorder for your Mac."),
                        CaptionCue(start: 3.2, end: 6.2, text: "Blur hides anything sensitive.")]
        ProjectIO.saveKeys([KeyEvent(t: 0.9, label: "⌘⇧S", isShortcut: true),
                            KeyEvent(t: 3.4, label: "h", isShortcut: false), KeyEvent(t: 3.6, label: "i", isShortcut: false),
                            KeyEvent(t: 3.8, label: "!", isShortcut: false)], folder: folder)
        let doc = ProjectDocument(name: "Self Test", createdAt: Date(), info: info,
                                  clips: [Clip.freezeFrame(at: 0, seconds: 1.5),
                                          Clip(start: Clip.freezeSliver, end: duration * 0.6, speed: 1), Clip(start: duration * 0.7, end: duration, speed: 2)],
                                  zooms: zooms, style: style, effects: effects, captions: captions)
        var docWithChapters = doc
        docWithChapters.chapters = [Chapter(time: 0, title: "Intro"), Chapter(time: duration * 0.75, title: "Second part")]
        ProjectIO.save(docWithChapters, folder: folder)
        let reloaded = try ProjectIO.load(folder: folder)
        print("round-trip: \(reloaded.effects.count) effects, \(reloaded.captions.count) captions")
        let idle = ActivityAnalyzer.idleRanges(cursor: cursor, keys: [], duration: duration)
        let split = ClipOps.apply([(2.0, 4.0)], to: [Clip(start: 0, end: 10)], speed: 4)
        print("idle ranges: \(idle.count), clip ops: \(split.map { String(format: "%.1f-%.1f@%g", $0.start, $0.end, $0.speed) })")
        print("zooms: \(zooms.map { String(format: "%.2f-%.2f", $0.start, $0.end) })")
        guard exportFiles else { return }

        let model = try EditorModel(folder: folder)
        for _ in 0..<200 where !model.isReady { try await Task.sleep(nanoseconds: 50_000_000) }
        guard model.isReady, let job = model.exportJob() else { throw NSError(domain: "selftest", code: 1, userInfo: [NSLocalizedDescriptionKey: model.loadError ?? "not ready"]) }
        print("edited duration: \(job.built.duration.seconds)")

        let exporter = Exporter()
        var settings = ExportSettings()
        settings.resolution = .p1080
        settings.fps = 60
        let mp4 = outDir.appendingPathComponent("selftest.mp4")
        let start = Date()
        try await exporter.export(job: job, settings: settings, to: mp4) { _ in }
        print(String(format: "mp4 exported in %.1fs", Date().timeIntervalSince(start)))
        print("srt:\n\(model.srt())")
        print("webcam track: \(String(describing: job.model.webcamTrackID)), comp video tracks: \(job.built.composition.tracks(withMediaType: .video).count)")
        // Direct overlay render with a synthetic camera frame.
        let fake = CIImage(color: CIColor(red: 0.9, green: 0.3, blue: 0.2)).cropped(to: CGRect(x: 0, y: 0, width: 1280, height: 720))
        let screenImg = CIImage(color: CIColor(red: 0.2, green: 0.4, blue: 0.9)).cropped(to: CGRect(x: 0, y: 0, width: 1920, height: 1200))
        for t in [1.3, 7.4, 9.9] {
            let img = FrameRenderer.shared.compose(model: job.model, compTime: t, screen: screenImg, camera: fake, size: CGSize(width: 1920, height: 1080))
            if let cg = FrameRenderer.shared.ciContext.createCGImage(img, from: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
               let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
                try data.write(to: outDir.appendingPathComponent(String(format: "direct-%.1f.png", t)))
            }
        }

        // Frames for visual checks (edited-timeline seconds).
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: mp4))
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = .zero
        let editedDuration = job.built.duration.seconds
        for t in [1.3, 1.0, 4.6, 7.4, editedDuration - 1.0] {
            if let img = try? await gen.image(at: CMTime(sec: t)).image,
               let data = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]) {
                try data.write(to: outDir.appendingPathComponent(String(format: "frame-%.1f.png", t)))
            }
        }

        settings.format = .gif
        settings.gifWidth = 640
        settings.gifFPS = 15
        try await Exporter().export(job: job, settings: settings, to: outDir.appendingPathComponent("selftest.gif")) { _ in }
        print("gif exported")
    }

    /// Records the main display through the real capture pipeline (screen + system audio + cursor), then exports it.
    @MainActor
    private static func recordTest(seconds: Double, outDir: URL) async throws {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let folder = outDir.appendingPathComponent("Record.framecast")
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent(ProjectFiles.cursors), withIntermediateDirectories: true)

        print("screen permission: \(CGPreflightScreenCaptureAccess())")
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else { throw NSError(domain: "selftest", code: 2) }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let scale = CGFloat(filter.pointPixelScale)
        let w = evenInt(filter.contentRect.width * scale), h = evenInt(filter.contentRect.height * scale)
        let config = SCStreamConfiguration()
        config.width = w; config.height = h
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.showsCursor = false
        config.queueDepth = 8
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        config.capturesAudio = true
        config.sampleRate = 48000
        config.channelCount = 2

        let clock = RecordingClock()
        let screen = try ScreenCaptureSession(url: folder.appendingPathComponent(ProjectFiles.screen), width: w, height: h,
                                              fps: 60, captureAudio: true, clock: clock)
        try await screen.start(filter: filter, configuration: config)
        let cursor = CursorRecorder(clock: clock, captureRect: display.frame, folder: folder)
        try await Task.sleep(nanoseconds: 500_000_000)
        clock.begin()
        screen.beginRecording()
        cursor.start()
        try await Task.sleep(nanoseconds: UInt64(seconds * 0.5 * 1e9))
        clock.pause()
        try await Task.sleep(nanoseconds: 700_000_000)
        clock.resume()
        try await Task.sleep(nanoseconds: UInt64(seconds * 0.5 * 1e9))
        let duration = clock.stop()
        let track = cursor.stop()
        await screen.finish(duration: duration)
        print(String(format: "recorded %.2fs (pause excluded), frames written: %d, cursor samples: %d, shapes: %d",
                     duration.seconds, screen.framesWritten, track.samples.count, track.shapeInfo.count))
        ProjectIO.saveCursor(track, folder: folder)

        let asset = AVURLAsset(url: folder.appendingPathComponent(ProjectFiles.screen))
        let fileDuration = try await asset.load(.duration).seconds
        let audioTracks = try await asset.loadTracks(withMediaType: .audio).count
        print(String(format: "file duration %.2fs, %dx%d, audio tracks: %d", fileDuration, w, h, audioTracks))

        let info = RecordingInfo(duration: duration.seconds, pointWidth: display.frame.width, pointHeight: display.frame.height,
                                 pixelWidth: w, pixelHeight: h, hasWebcam: false, hasMic: false, hasSystemAudio: true,
                                 sourceName: "Record test", hasCursorData: true)
        let doc = ProjectDocument(name: "Record Test", createdAt: Date(), info: info,
                                  clips: [Clip(start: 0, end: duration.seconds)],
                                  zooms: [ZoomSegment(start: 0.5, end: duration.seconds - 0.2, scale: 2)], style: Style())
        ProjectIO.save(doc, folder: folder)
        let model = try EditorModel(folder: folder)
        for _ in 0..<200 where !model.isReady { try await Task.sleep(nanoseconds: 50_000_000) }
        guard let job = model.exportJob() else { throw NSError(domain: "selftest", code: 3) }
        try await Exporter().export(job: job, settings: ExportSettings(), to: outDir.appendingPathComponent("record.mp4")) { _ in }
        print("exported record.mp4")
    }
}
