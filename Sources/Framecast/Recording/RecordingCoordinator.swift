import Foundation
import AppKit
import ScreenCaptureKit
import AVFoundation

enum RecordingError: LocalizedError {
    case noScreenPermission
    case sourceUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .noScreenPermission:
            return "Framecast needs Screen Recording permission. Enable it in System Settings → Privacy & Security → Screen & System Audio Recording, then try again."
        case .sourceUnavailable(let s):
            return s
        }
    }
}

@MainActor
final class RecordingCoordinator: ObservableObject {
    static let shared = RecordingCoordinator()

    enum Phase: Equatable { case idle, preparing, countdown, recording, paused, finishing }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var elapsed: Double = 0

    var isActive: Bool { phase != .idle }
    var isRecording: Bool { phase == .recording || phase == .paused }

    private var clock: RecordingClock?
    private var screen: ScreenCaptureSession?
    private var camMic: CameraMicCapture?
    private var cursor: CursorRecorder?
    private var keys: KeystrokeRecorder?
    private var device: DeviceCapture?
    private var flags: [Double] = []
    private var controlsHidden = false
    private var folder: URL?
    private var targetScreen: NSScreen?
    private var info: RecordingInfo?
    private var ticker: Timer?
    private let controlBar = ControlBarPanel()

    private let settings = RecorderSettings.shared

    func toggleRecording() {
        switch phase {
        case .idle: start()
        case .recording, .paused: stop()
        default: break
        }
    }

    func start() {
        guard phase == .idle else { return }
        Task { await startRecording() }
    }

    private func startRecording() async {
        phase = .preparing
        do {
            try await prepare()
        } catch {
            await teardown(deleteFolder: true)
            phase = .idle
            WindowManager.shared.showHome()
            presentError(error)
            return
        }

        WindowManager.shared.hideAllForRecording()
        phase = .countdown
        await Countdown.run(seconds: settings.countdown, on: targetScreen ?? NSScreen.main!)
        guard phase == .countdown, let clock else { return }

        clock.begin()
        screen?.beginRecording()
        cursor?.start()
        keys?.start()
        phase = .recording
        controlsHidden = !AppSettings.shared.showRecordingWidget
        if !controlsHidden { controlBar.show(on: targetScreen ?? NSScreen.main!, coordinator: self) }
        if AppSettings.shared.highlightRecordedArea, let rect = highlightRect { AreaHighlight.shared.show(around: rect) }
        ticker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.elapsed = self?.clock?.elapsed ?? 0 }
        }
    }

    private func prepare() async throws {
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
            throw RecordingError.noScreenPermission
        }
        if settings.cameraEnabled { _ = await AVCaptureDevice.requestAccess(for: .video) }
        if settings.micEnabled { _ = await AVCaptureDevice.requestAccess(for: .audio) }

        flags = []
        highlightRect = nil
        if settings.kind == .device {
            try await prepareDevice()
            return
        }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let pid = ProcessInfo.processInfo.processIdentifier
        var excluded = content.windows.filter { $0.owningApplication?.processID == pid }
        if settings.hideDesktopIcons {
            excluded += content.windows.filter {
                $0.owningApplication?.bundleIdentifier == "com.apple.finder" && $0.windowLayer < 0
            }
        }

        let filter: SCContentFilter
        var captureRect: CGRect          // global points, top-left origin
        var sourceName: String
        var sourceRect: CGRect? = nil
        var display: SCDisplay?

        switch settings.kind {
        case .device:
            throw RecordingError.sourceUnavailable("Device recording is set up separately.")
        case .display, .area:
            guard let d = content.displays.first(where: { $0.displayID == settings.displayID }) ?? content.displays.first else {
                throw RecordingError.sourceUnavailable("No display available to record.")
            }
            display = d
            filter = SCContentFilter(display: d, excludingWindows: excluded)
            captureRect = d.frame
            sourceName = NSScreen.screen(for: d.displayID)?.localizedName ?? "Display"
            if settings.kind == .area {
                guard let area = settings.areaRect, area.width > 10, area.height > 10 else {
                    throw RecordingError.sourceUnavailable("Select an area to record first.")
                }
                let clipped = area.intersection(CGRect(origin: .zero, size: d.frame.size))
                sourceRect = clipped
                captureRect = clipped.offsetBy(dx: d.frame.minX, dy: d.frame.minY)
                sourceName = "Area of \(sourceName)"
            }
        case .window:
            guard let w = content.windows.first(where: { $0.windowID == settings.windowID }) else {
                throw RecordingError.sourceUnavailable("The selected window is no longer available. Choose a window again.")
            }
            filter = SCContentFilter(desktopIndependentWindow: w)
            captureRect = w.frame
            sourceName = [w.owningApplication?.applicationName, w.title].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " — ")
            display = content.displays.first { $0.frame.intersects(w.frame) }
        }

        targetScreen = display.flatMap { NSScreen.screen(for: $0.displayID) } ?? NSScreen.main
        if let primary = NSScreen.screens.first {
            // Global top-left points → AppKit bottom-left coordinates, for the area highlight.
            highlightRect = CGRect(x: captureRect.minX, y: primary.frame.maxY - captureRect.maxY,
                                   width: captureRect.width, height: captureRect.height)
        }

        let scale = CGFloat(filter.pointPixelScale)
        let pointSize = sourceRect?.size ?? filter.contentRect.size
        let width = evenInt(pointSize.width * scale)
        let height = evenInt(pointSize.height * scale)

        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(settings.fps))
        config.showsCursor = false
        config.queueDepth = 8
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        config.capturesAudio = settings.systemAudio
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48000
        config.channelCount = 2
        if let sourceRect { config.sourceRect = sourceRect }

        let folder = ProjectLibrary.shared.newProjectFolder()
        self.folder = folder
        let clock = RecordingClock()
        self.clock = clock

        let screen = try ScreenCaptureSession(url: folder.appendingPathComponent(ProjectFiles.screen),
                                              width: width, height: height, fps: settings.fps,
                                              captureAudio: settings.systemAudio, clock: clock)
        screen.onError = { [weak self] error in
            Task { @MainActor in self?.handleStreamError(error) }
        }
        try await screen.start(filter: filter, configuration: config)
        self.screen = screen

        let camID = settings.cameraEnabled && !settings.cameraID.isEmpty ? settings.cameraID : nil
        let micID = settings.micEnabled && !settings.micID.isEmpty ? settings.micID : nil
        try await startCameraMic(folder: folder, clock: clock)

        cursor = CursorRecorder(clock: clock, captureRect: captureRect, folder: folder)
        if settings.recordKeystrokes && KeystrokeRecorder.isTrusted {
            keys = KeystrokeRecorder(clock: clock)
        }

        info = RecordingInfo(duration: 0, pointWidth: pointSize.width, pointHeight: pointSize.height,
                             pixelWidth: width, pixelHeight: height,
                             hasWebcam: camMic?.hasCamera ?? false, hasMic: camMic?.hasMic ?? false,
                             hasSystemAudio: settings.systemAudio, sourceName: sourceName, hasCursorData: true)
    }

    private var highlightRect: CGRect?

    private func startCameraMic(folder: URL, clock: RecordingClock) async throws {
        let camID = settings.cameraEnabled && !settings.cameraID.isEmpty ? settings.cameraID : nil
        let micID = settings.micEnabled && !settings.micID.isEmpty ? settings.micID : nil
        if camID != nil || micID != nil {
            let cm = try CameraMicCapture(cameraID: camID, micID: micID, folder: folder, clock: clock,
                                          cameraResolution: AppSettings.shared.cameraResolution)
            if cm.hasCamera { CameraPreview.shared.attach(to: cm.session) }
            await cm.startRunning()
            camMic = cm
        }
    }

    /// iPhone / iPad screen recording.
    private func prepareDevice() async throws {
        guard let dev = DeviceCatalog.iosDevice(id: settings.deviceID) else {
            throw RecordingError.sourceUnavailable("Connect your iPhone or iPad with a cable, unlock it and trust this Mac, then try again.")
        }
        targetScreen = NSScreen.withMouse
        let folder = ProjectLibrary.shared.newProjectFolder()
        self.folder = folder
        let clock = RecordingClock()
        self.clock = clock
        let capture = try DeviceCapture(device: dev, url: folder.appendingPathComponent(ProjectFiles.screen), clock: clock)
        await capture.startRunning()
        device = capture
        try await startCameraMic(folder: folder, clock: clock)
        let px = capture.pixelSize
        info = RecordingInfo(duration: 0, pointWidth: px.width / 3, pointHeight: px.height / 3,
                             pixelWidth: Int(px.width), pixelHeight: Int(px.height),
                             hasWebcam: camMic?.hasCamera ?? false, hasMic: camMic?.hasMic ?? false,
                             hasSystemAudio: capture.hasAudio, sourceName: dev.localizedName, hasCursorData: false)
    }

    /// Marks this moment; flags show up on the timeline.
    func addFlag() {
        guard isRecording, let clock else { return }
        flags.append(clock.elapsed)
        NSSound(named: "Pop")?.play()
    }

    func toggleControls() {
        guard isRecording else { return }
        controlsHidden.toggle()
        if controlsHidden { controlBar.hide() } else { controlBar.show(on: targetScreen ?? NSScreen.main!, coordinator: self) }
    }

    func togglePause() {
        guard let clock else { return }
        if phase == .recording {
            clock.pause()
            phase = .paused
        } else if phase == .paused {
            clock.resume()
            phase = .recording
        }
    }

    func stop() {
        guard phase == .recording || phase == .paused else { return }
        Task { await finishRecording() }
    }

    private func finishRecording() async {
        guard let clock, let folder, var info else { return }
        phase = .finishing
        ticker?.invalidate()
        controlBar.hide()

        AreaHighlight.shared.hide()
        CameraPreview.shared.hide()
        let duration = clock.stop()
        let track = cursor?.stop() ?? CursorTrack()
        let keyEvents = keys?.stop() ?? []
        await screen?.finish(duration: duration)
        await device?.finish(duration: duration)
        await camMic?.finish(duration: duration)

        // Some devices may never deliver a frame; reflect what was actually written.
        let fm = FileManager.default
        info.duration = duration.seconds
        info.hasWebcam = info.hasWebcam && fm.fileExists(atPath: folder.appendingPathComponent(ProjectFiles.webcam).path)
        info.hasMic = info.hasMic && fm.fileExists(atPath: folder.appendingPathComponent(ProjectFiles.mic).path)

        ProjectIO.saveCursor(track, folder: folder)
        if !keyEvents.isEmpty { ProjectIO.saveKeys(keyEvents, folder: folder) }
        let style = PresetStore.shared.defaultStyle
        let zooms = settings.autoZoom
            ? ZoomGenerator.generate(from: track.clicks, duration: info.duration, scale: style.defaultZoomScale)
            : []
        var style2 = style
        if !info.hasCursorData { style2.showCursor = false }
        var doc = ProjectDocument(name: info.hasCursorData ? ProjectLibrary.defaultName() : "\(info.sourceName) \(ProjectLibrary.defaultName())",
                                  createdAt: Date(), info: info,
                                  clips: [Clip(start: 0, end: info.duration)], zooms: zooms, style: style2)
        doc.flags = flags.filter { $0 < info.duration }
        ProjectIO.save(doc, folder: folder)
        await Thumbnailer.writeRawThumbnail(videoURL: folder.appendingPathComponent(ProjectFiles.screen),
                                            to: folder.appendingPathComponent(ProjectFiles.thumbnail))

        await teardown(deleteFolder: false)
        phase = .idle
        elapsed = 0
        ProjectLibrary.shared.reload()
        NSSound(named: "Glass")?.play()
        if AppSettings.shared.showQuickExportWidget {
            QuickExportWidget.shared.show(folder: folder)
        } else {
            WindowManager.shared.openEditor(folder: folder)
        }
    }

    func cancel() {
        guard isActive else { return }
        Task {
            ticker?.invalidate()
            controlBar.hide()
            clock?.stop()
            _ = cursor?.stop()
            _ = keys?.stop()
            await screen?.cancel()
            device?.cancel()
            camMic?.cancel()
            AreaHighlight.shared.hide()
            CameraPreview.shared.hide()
            await teardown(deleteFolder: true)
            phase = .idle
            elapsed = 0
            WindowManager.shared.showHome()
        }
    }

    func restart() {
        guard isRecording else { return }
        Task {
            ticker?.invalidate()
            controlBar.hide()
            clock?.stop()
            _ = cursor?.stop()
            _ = keys?.stop()
            await screen?.cancel()
            device?.cancel()
            camMic?.cancel()
            AreaHighlight.shared.hide()
            await teardown(deleteFolder: true)
            phase = .idle
            elapsed = 0
            await startRecording()
        }
    }

    private func handleStreamError(_ error: Error) {
        guard isRecording else { return }
        // The stream was interrupted (e.g. the window closed) — save what we have.
        stop()
    }

    private func teardown(deleteFolder: Bool) async {
        if deleteFolder, let folder {
            try? FileManager.default.removeItem(at: folder)
        }
        screen = nil
        camMic = nil
        cursor = nil
        keys = nil
        device = nil
        clock = nil
        folder = nil
        info = nil
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Couldn't start recording"
        alert.informativeText = error.localizedDescription
        if case RecordingError.noScreenPermission = error {
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
            }
        } else {
            alert.runModal()
        }
    }
}
