import Foundation
import AVFoundation
import AppKit
import ScreenCaptureKit

/// Headless render check: `Framecast --selftest <video> <outDir>`
/// Builds a project from a video with simulated cursor movement and clicks, then exports MP4 + GIF.
enum SelfTest {
    static func runIfRequested() {
        let args = CommandLine.arguments
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

    @MainActor
    private static func run(video: URL, outDir: URL) async throws {
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
        style.background.kind = .wallpaper
        style.keystrokes = .all
        style.camera.background = .blur
        let zooms = ZoomGenerator.generate(from: cursor.clicks, duration: duration, scale: 2)
        var title = EffectSegment(kind: .text, start: 0, end: 2.6)
        title.text = "Framecast self-test"
        var blur = EffectSegment(kind: .blur, start: 3.0, end: 6.0)
        blur.x = 0.55; blur.y = 0.08; blur.w = 0.35; blur.h = 0.22
        var spot = EffectSegment(kind: .spotlight, start: 6.5, end: 8.5)
        spot.x = 0.1; spot.y = 0.45; spot.w = 0.4; spot.h = 0.3
        let effects = [title, blur, spot,
                       EffectSegment(kind: .hideCursor, start: 4.0, end: 5.2),
                       EffectSegment(kind: .cameraFull, start: duration * 0.72, end: duration * 0.93)]
        let captions = [CaptionCue(start: 0.4, end: 3.0, text: "Welcome to Framecast, the screen recorder for your Mac."),
                        CaptionCue(start: 3.2, end: 6.2, text: "Blur hides anything sensitive.")]
        ProjectIO.saveKeys([KeyEvent(t: 0.9, label: "⌘⇧S", isShortcut: true),
                            KeyEvent(t: 3.4, label: "h", isShortcut: false), KeyEvent(t: 3.6, label: "i", isShortcut: false),
                            KeyEvent(t: 3.8, label: "!", isShortcut: false)], folder: folder)
        let doc = ProjectDocument(name: "Self Test", createdAt: Date(), info: info,
                                  clips: [Clip(start: 0, end: duration * 0.6, speed: 1), Clip(start: duration * 0.7, end: duration, speed: 2)],
                                  zooms: zooms, style: style, effects: effects, captions: captions)
        ProjectIO.save(doc, folder: folder)
        let reloaded = try ProjectIO.load(folder: folder)
        print("round-trip: \(reloaded.effects.count) effects, \(reloaded.captions.count) captions")
        let idle = ActivityAnalyzer.idleRanges(cursor: cursor, keys: [], duration: duration)
        let split = ClipOps.apply([(2.0, 4.0)], to: [Clip(start: 0, end: 10)], speed: 4)
        print("idle ranges: \(idle.count), clip ops: \(split.map { String(format: "%.1f-%.1f@%g", $0.start, $0.end, $0.speed) })")
        print("zooms: \(zooms.map { String(format: "%.2f-%.2f", $0.start, $0.end) })")

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
        for t in [1.3, 4.6, 7.4, editedDuration - 1.0] {
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
