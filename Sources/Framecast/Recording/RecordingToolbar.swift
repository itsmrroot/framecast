import AppKit
import SwiftUI
import AVFoundation
import ScreenCaptureKit

// MARK: - Toolbar

/// The floating "what do you want to record?" bar, opened with ⌘⇧2 or New Recording.
@MainActor
final class RecordingToolbar: ObservableObject {
    static let shared = RecordingToolbar()

    private var panel: NSPanel?
    private var pickerPanel: NSPanel?
    var isVisible: Bool { panel != nil }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    func show() {
        guard RecordingCoordinator.shared.phase == .idle else { return }
        Task { await SourceCatalog.shared.refresh() }
        let screen = NSScreen.withMouse
        if panel == nil {
            let host = NSHostingView(rootView: RecordingToolbarView(toolbar: self))
            let size = host.fittingSize
            let p = FloatingPanel(contentRect: CGRect(origin: .zero, size: size))
            p.contentView = host
            p.isMovableByWindowBackground = true
            panel = p
        }
        if let p = panel {
            func place() {
                let size = p.contentView?.fittingSize ?? p.frame.size
                // Centred on screen, where it's easy to find and doesn't cover the Dock.
                p.setFrame(CGRect(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.midY - size.height / 2,
                                  width: size.width, height: size.height), display: true)
            }
            place()
            p.orderFrontRegardless()
            p.makeKey()
            // SwiftUI may resize the panel once laid out (keeping its top edge), so place it again.
            DispatchQueue.main.async { place() }
        }
        CameraPreview.shared.refresh()
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        closePicker()
        if RecordingCoordinator.shared.phase == .idle { CameraPreview.shared.hide() }
    }

    /// Picks the source for `kind` (window picker, area selection…), then starts recording.
    /// `immediate` skips the display confirm step (used by the global "record display" shortcut).
    func start(_ kind: CaptureKind, immediate: Bool = false) {
        guard RecordingCoordinator.shared.phase == .idle else { return }
        let settings = RecorderSettings.shared
        let screen = NSScreen.withMouse
        switch kind {
        case .display where immediate:
            settings.displayID = screen.displayID
            begin(.display)
        case .display:
            // Confirm on the display itself first (hover a display, then Start recording).
            panel?.orderOut(nil)
            Task {
                if let picked = await DisplayPicker.pick() {
                    settings.displayID = picked.displayID
                    begin(.display)
                } else {
                    panel?.orderFrontRegardless()
                }
            }
        case .area:
            panel?.orderOut(nil)
            Task {
                try? await Task.sleep(nanoseconds: 150_000_000)
                let initial = settings.displayID == screen.displayID ? settings.areaRect : nil
                if let rect = await AreaSelector.select(on: screen, initial: initial) {
                    settings.displayID = screen.displayID
                    settings.areaRect = rect
                    begin(.area)
                } else {
                    panel?.orderFrontRegardless()
                }
            }
        case .window:
            showWindowPicker()
        case .device:
            if SourceCatalog.shared.devices.isEmpty {
                NSSound.beep()
                return
            }
            if settings.deviceID.isEmpty || !SourceCatalog.shared.devices.contains(where: { $0.id == settings.deviceID }) {
                settings.deviceID = SourceCatalog.shared.devices[0].id
            }
            begin(.device)
        }
    }

    private func begin(_ kind: CaptureKind) {
        RecorderSettings.shared.kind = kind
        panel?.orderOut(nil)
        panel = nil
        closePicker()
        RecordingCoordinator.shared.start()
    }

    private func showWindowPicker() {
        closePicker()
        Task { await SourceCatalog.shared.refresh() }
        let binding = Binding<Bool>(get: { true }, set: { [weak self] shown in if !shown { self?.closePicker() } })
        let view = WindowPickerSheet(catalog: SourceCatalog.shared, settings: RecorderSettings.shared, isPresented: binding) { [weak self] in
            self?.begin(.window)
        }
        let host = NSHostingView(rootView: view.preferredColorScheme(.dark))
        let p = FloatingPanel(contentRect: CGRect(x: 0, y: 0, width: 700, height: 520), keyable: true)
        p.contentView = host
        p.center()
        p.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        pickerPanel = p
    }

    func showAudioAppPicker() {
        closePicker()
        let binding = Binding<Bool>(get: { true }, set: { [weak self] shown in if !shown { self?.closePicker() } })
        let host = NSHostingView(rootView: AudioAppPicker(isPresented: binding).environment(\.colorScheme, .dark))
        let p = FloatingPanel(contentRect: CGRect(x: 0, y: 0, width: 360, height: 440), keyable: true)
        p.contentView = host
        p.center()
        p.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        pickerPanel = p
    }

    private func closePicker() {
        pickerPanel?.orderOut(nil)
        pickerPanel = nil
    }
}

/// Borderless floating panel kept out of screen recordings.
final class FloatingPanel: NSPanel {
    private let keyable: Bool

    init(contentRect: CGRect, keyable: Bool = false) {
        self.keyable = keyable
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        sharingType = .none
        isReleasedWhenClosed = false
        // Recording UI floats over whatever you record, so it stays dark in both modes.
        appearance = NSAppearance(named: .darkAqua)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { keyable }
}

extension NSScreen {
    static var withMouse: NSScreen {
        let p = NSEvent.mouseLocation
        return screens.first { $0.frame.contains(p) } ?? main ?? screens[0]
    }
}

struct RecordingToolbarView: View {
    @ObservedObject var toolbar: RecordingToolbar
    @ObservedObject private var settings = RecorderSettings.shared
    @ObservedObject private var catalog = SourceCatalog.shared
    @ObservedObject private var app = AppSettings.shared

    var body: some View {
        HStack(spacing: 0) {
            Button { toolbar.hide() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.white.opacity(0.92)))
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
            .keyboardShortcut(.cancelAction)
            .padding(.horizontal, 16)

            divider

            HStack(spacing: 4) {
                source(.display, "Display", "display")
                source(.window, "Window", "macwindow")
                source(.area, "Area", "rectangle.dashed")
                source(.device, "Device", "iphone")
            }
            .padding(.horizontal, 10)

            divider

            HStack(spacing: 6) {
                deviceMenu(icon: settings.cameraEnabled ? "video" : "video.slash",
                           title: settings.cameraEnabled ? name(catalog.cameras, settings.cameraID) ?? "Camera" : "No camera",
                           on: settings.cameraEnabled) {
                    Button { settings.cameraEnabled = false; CameraPreview.shared.refresh() } label: { check("No camera", !settings.cameraEnabled) }
                    Divider()
                    ForEach(catalog.cameras) { cam in
                        Button {
                            settings.cameraID = cam.id
                            settings.cameraEnabled = true
                            CameraPreview.shared.refresh()
                        } label: { check(cam.name, settings.cameraEnabled && settings.cameraID == cam.id) }
                    }
                    Divider()
                    Toggle("Show camera preview", isOn: Binding(get: { app.showCameraPreview }, set: {
                        app.showCameraPreview = $0
                        CameraPreview.shared.refresh()
                    }))
                }
                deviceMenu(icon: settings.micEnabled ? "mic" : "mic.slash",
                           title: settings.micEnabled ? name(catalog.microphones, settings.micID) ?? "Microphone" : "No microphone",
                           on: settings.micEnabled) {
                    Button { settings.micEnabled = false } label: { check("No microphone", !settings.micEnabled) }
                    Divider()
                    ForEach(catalog.microphones) { mic in
                        Button {
                            settings.micID = mic.id
                            settings.micEnabled = true
                        } label: { check(mic.name, settings.micEnabled && settings.micID == mic.id) }
                    }
                    Divider()
                    Button("Mic Mode (Voice Isolation)…") { AVCaptureDevice.showSystemUserInterface(.microphoneModes) }
                }
                deviceMenu(icon: settings.systemAudio ? "speaker.wave.2" : "speaker.slash",
                           title: !settings.systemAudio ? "No system audio"
                               : (settings.audioFromSelectedApps ? "\(settings.audioApps.count) app\(settings.audioApps.count == 1 ? "" : "s")" : "System audio"),
                           on: settings.systemAudio) {
                    Button { settings.systemAudio = true; settings.audioFromSelectedApps = false } label: {
                        check("Record system audio from all apps", settings.systemAudio && !settings.audioFromSelectedApps)
                    }
                    Button { toolbar.showAudioAppPicker() } label: {
                        check("Record system audio from selected apps…", settings.systemAudio && settings.audioFromSelectedApps)
                    }
                    Divider()
                    Button { settings.systemAudio = false } label: { check("Don't record system audio", !settings.systemAudio) }
                }
                .help("Record the sound your Mac plays")
            }
            .padding(.horizontal, 10)

            divider

            Button {
                toolbar.hide()
                WindowManager.shared.showHome()
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 17))
                    .frame(width: 46, height: 42)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverHighlight(resting: 0.06)
            .help("Open Framecast: your recordings and settings")
            .padding(.leading, 12)

            Menu {
                Section("While recording") {
                    Toggle("Hide desktop icons", isOn: $settings.hideDesktopIcons)
                    Toggle("Highlight recorded area", isOn: $app.highlightRecordedArea)
                    Toggle("Record keystrokes", isOn: Binding(get: { settings.recordKeystrokes }, set: { on in
                        settings.recordKeystrokes = on
                        if on && !KeystrokeRecorder.isTrusted { KeystrokeRecorder.requestTrust() }
                    }))
                    Button(SpeakerNotes.shared.isVisible ? "Hide Speaker Notes" : "Show Speaker Notes") { SpeakerNotes.shared.toggle() }
                }
                Section("After recording") {
                    Toggle("Create zooms automatically", isOn: $settings.autoZoom)
                    Toggle("Open quick export widget", isOn: $app.showQuickExportWidget)
                }
                Picker("Countdown", selection: $settings.countdown) {
                    Text("No countdown").tag(0); Text("3 seconds").tag(3); Text("5 seconds").tag(5); Text("10 seconds").tag(10)
                }
                Picker("Frame rate", selection: $settings.fps) {
                    Text("30 fps").tag(30); Text("60 fps").tag(60)
                }
                Divider()
                Button("Open Framecast Window") { toolbar.hide(); WindowManager.shared.showHome() }
                Button("Settings…") { WindowManager.shared.showSettings() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "gearshape")
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                }
                .font(.system(size: 17))
                .frame(width: 54, height: 42)
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .hoverHighlight()
            .padding(.horizontal, 10)
        }
        .foregroundStyle(Theme.text)
        .frame(height: 64)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.11, green: 0.11, blue: 0.125).opacity(0.97))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.1)))
        )
        .preferredColorScheme(.dark)
        .fixedSize()
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1, height: 36)
    }

    private func source(_ kind: CaptureKind, _ title: String, _ icon: String) -> some View {
        ToolbarSourceButton(title: title, icon: icon,
                            disabled: kind == .device && catalog.devices.isEmpty,
                            help: help(kind)) { toolbar.start(kind) }
    }

    private func help(_ kind: CaptureKind) -> String {
        switch kind {
        case .display: return "Record the display under the pointer"
        case .window: return "Pick a window to record"
        case .area: return "Drag out an area to record"
        case .device: return catalog.devices.isEmpty
            ? "Connect an iPhone or iPad with a cable and unlock it to record its screen"
            : "Record \(catalog.devices.first?.name ?? "your device")"
        }
    }

    private func name(_ devices: [DeviceCatalog.Device], _ id: String) -> String? {
        devices.first { $0.id == id }?.name
    }

    @ViewBuilder
    private func check(_ title: String, _ on: Bool) -> some View {
        if on { Label(title, systemImage: "checkmark") } else { Text(title) }
    }

    private func pill(icon: String, title: String, on: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 15))
            Text(title).font(.system(size: 13, weight: .medium)).lineLimit(1).frame(maxWidth: 130, alignment: .leading)
        }
        .foregroundStyle(on ? Theme.text : Theme.textDim)
        .padding(.horizontal, 10)
        .frame(height: 42)
        .contentShape(Rectangle())
    }

    private func deviceMenu<Content: View>(icon: String, title: String, on: Bool, @ViewBuilder content: () -> Content) -> some View {
        Menu { content() } label: { pill(icon: icon, title: title, on: on) }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .hoverHighlight()
    }
}

/// A soft rounded highlight behind a toolbar item while the pointer is over it.
private struct HoverHighlight: ViewModifier {
    var resting: Double = 0
    @State private var hover = false

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(hover ? max(resting, 0) + 0.1 : resting)))
            .animation(.easeOut(duration: 0.12), value: hover)
            .onHover { hover = $0 }
    }
}

private extension View {
    func hoverHighlight(resting: Double = 0) -> some View { modifier(HoverHighlight(resting: resting)) }
}

private struct ToolbarSourceButton: View {
    let title: String
    let icon: String
    var disabled = false
    let help: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 19, weight: .regular)).frame(height: 22)
                Text(title).font(.system(size: 11, weight: .medium))
            }
            .frame(width: 64, height: 52)
            .background(RoundedRectangle(cornerRadius: 10).fill(hover && !disabled ? Color.white.opacity(0.1) : .clear))
            .foregroundStyle(disabled ? Theme.textFaint : Theme.text)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}

// MARK: - Camera preview

/// Floating live view of the webcam, so you can see yourself while recording.
/// Like the other floating panels, it's excluded from the screen recording; the camera is composited in the editor.
@MainActor
final class CameraPreview {
    static let shared = CameraPreview()

    private var panel: NSPanel?
    private var ownSession: AVCaptureSession?
    private var ownCameraID: String?
    private let preview = AVCaptureVideoPreviewLayer()

    private init() {
        preview.videoGravity = .resizeAspectFill
    }

    /// Shows or hides the preview to match the camera setting.
    func refresh() {
        let s = RecorderSettings.shared
        guard s.cameraEnabled, !s.cameraID.isEmpty, AppSettings.shared.showCameraPreview else {
            hide()
            return
        }
        Task {
            guard await AVCaptureDevice.requestAccess(for: .video) else { return }
            showPanel()
            if !RecordingCoordinator.shared.isRecording { startOwnSession(cameraID: s.cameraID) }
        }
    }

    /// While recording, the preview shows the recording session's frames instead of running its own.
    func attach(to session: AVCaptureSession) {
        guard panel != nil || (AppSettings.shared.showCameraPreview && RecorderSettings.shared.cameraEnabled) else { return }
        showPanel()
        stopOwnSession()
        preview.session = session
        mirror()
    }

    func hide() {
        stopOwnSession()
        preview.session = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func showPanel() {
        guard panel == nil else { return }
        let side: CGFloat = 220
        let screen = NSScreen.withMouse
        let frame = CGRect(x: screen.visibleFrame.maxX - side - 24, y: screen.visibleFrame.maxY - side - 24, width: side, height: side)
        let p = FloatingPanel(contentRect: frame)
        p.isMovableByWindowBackground = true
        let view = NSView(frame: CGRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        view.layer?.cornerRadius = 28
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        view.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
        view.layer?.borderWidth = 1
        preview.frame = view.bounds
        preview.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer?.addSublayer(preview)
        p.contentView = view
        p.orderFrontRegardless()
        panel = p
    }

    private func startOwnSession(cameraID: String) {
        if ownSession != nil, ownCameraID == cameraID { return }
        stopOwnSession()
        guard let device = DeviceCatalog.camera(id: cameraID), let input = try? AVCaptureDeviceInput(device: device) else { return }
        let session = AVCaptureSession()
        session.beginConfiguration()
        if session.canAddInput(input) { session.addInput(input) }
        if session.canSetSessionPreset(.high) { session.sessionPreset = .high }
        session.commitConfiguration()
        ownSession = session
        ownCameraID = cameraID
        preview.session = session
        mirror()
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
    }

    private func stopOwnSession() {
        guard let s = ownSession else { return }
        ownSession = nil
        ownCameraID = nil
        if preview.session === s { preview.session = nil }
        DispatchQueue.global(qos: .userInitiated).async { s.stopRunning() }
    }

    private func mirror() {
        if let c = preview.connection, c.isVideoMirroringSupported {
            c.automaticallyAdjustsVideoMirroring = false
            c.isVideoMirrored = true
        }
    }
}

// MARK: - Recorded area highlight

/// Dims everything outside the recorded area while recording (never captured itself).
@MainActor
final class AreaHighlight {
    static let shared = AreaHighlight()
    private var windows: [NSWindow] = []

    /// `rect` is in global AppKit coordinates (bottom-left origin).
    func show(around rect: CGRect) {
        hide()
        for screen in NSScreen.screens {
            // A screen recorded in full needs no dimming.
            if rect.insetBy(dx: -1, dy: -1).contains(screen.frame) { continue }
            let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.level = .floating
            w.isOpaque = false
            w.backgroundColor = .clear
            w.ignoresMouseEvents = true
            w.sharingType = .none
            w.hasShadow = false
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            let local = rect.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
            w.contentView = DimView(hole: local)
            w.setFrame(screen.frame, display: true)
            w.orderFrontRegardless()
            windows.append(w)
        }
    }

    func hide() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    private final class DimView: NSView {
        let hole: CGRect
        init(hole: CGRect) {
            self.hole = hole
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError() }

        override func draw(_ dirtyRect: NSRect) {
            NSColor.black.withAlphaComponent(0.4).setFill()
            bounds.fill()
            guard hole.intersects(bounds) else { return }
            NSColor.clear.setFill()
            hole.fill(using: .copy)
            let border = NSBezierPath(rect: hole.insetBy(dx: -1, dy: -1))
            border.lineWidth = 2
            NSColor.white.withAlphaComponent(0.5).setStroke()
            border.stroke()
        }
    }
}

/// Pick which apps' sound is recorded.
private struct AudioAppPicker: View {
    @Binding var isPresented: Bool
    @ObservedObject private var settings = RecorderSettings.shared
    @State private var apps: [(id: String, name: String, icon: NSImage?)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Record audio from").font(.system(size: 15, weight: .semibold))
            Text("Only these apps' sound is recorded. Video still shows everything.")
                .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.6))
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(apps, id: \.id) { app in
                        let on = settings.audioApps.contains(app.id)
                        Button {
                            if on { settings.audioApps.removeAll { $0 == app.id } } else { settings.audioApps.append(app.id) }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(on ? Theme.accent : .white.opacity(0.4))
                                if let icon = app.icon { Image(nsImage: icon).resizable().frame(width: 20, height: 20) }
                                Text(app.name).font(.system(size: 13))
                                Spacer()
                            }
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack {
                Button("Cancel") { isPresented = false }.buttonStyle(SecondaryButtonStyle())
                Spacer()
                Button("Use \(settings.audioApps.count) App\(settings.audioApps.count == 1 ? "" : "s")") {
                    settings.systemAudio = true
                    settings.audioFromSelectedApps = !settings.audioApps.isEmpty
                    isPresented = false
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(settings.audioApps.isEmpty)
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(width: 360, height: 440)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(white: 0.1).opacity(0.97)))
        .task {
            // Regular apps that are running now, alphabetically.
            apps = NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
                .compactMap { a in a.bundleIdentifier.map { (id: $0, name: a.localizedName ?? $0, icon: a.icon) } }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }
}
