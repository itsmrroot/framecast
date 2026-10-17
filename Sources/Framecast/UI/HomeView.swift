import SwiftUI
import ScreenCaptureKit
import AppKit
import AVFoundation

struct HomeView: View {
    @ObservedObject private var settings = RecorderSettings.shared
    @ObservedObject private var coordinator = RecordingCoordinator.shared
    @ObservedObject private var library = ProjectLibrary.shared
    @ObservedObject private var catalog = SourceCatalog.shared

    var body: some View {
        HStack(spacing: 0) {
            RecordPanel(settings: settings, coordinator: coordinator, catalog: catalog)
                .frame(width: 340)
                .background(Theme.panel)
            Rectangle().fill(Theme.border).frame(width: 1)
            LibraryView(library: library)
        }
        .background(Theme.bg)
        .focusEffectDisabled()
        .task { await catalog.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await catalog.refresh() }
        }
    }
}

// MARK: - Record panel

private struct RecordPanel: View {
    @ObservedObject var settings: RecorderSettings
    @ObservedObject var coordinator: RecordingCoordinator
    @ObservedObject var catalog: SourceCatalog
    @State private var showWindowPicker = false
    @State private var keysTrusted = KeystrokeRecorder.isTrusted

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(LinearGradient(colors: [Theme.accent, Color(red: 0.2, green: 0.6, blue: 1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "record.circle").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                }
                .frame(width: 28, height: 28)
                Text("Framecast").font(.system(size: 17, weight: .bold))
                    .lineLimit(1)
                    .fixedSize()
                Text("v\(Updater.currentVersion)")
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Theme.fill.opacity(0.08)))
                    .foregroundStyle(Theme.textDim)
                    .fixedSize()
                    .help("Framecast \(Updater.currentVersion)")
                Spacer()
                UpdateBadge()
                AppearanceButton()
            }
            .padding(.top, 38)
            .padding(.horizontal, 20)
            .padding(.bottom, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !catalog.hasScreenPermission { permissionBanner }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Record")
                        PillPicker(options: CaptureKind.homeCases, selection: $settings.kind, label: \.label, icon: \.icon)
                        sourceDetail
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Camera & Audio")
                        deviceRow(icon: "video", label: "Camera", isOn: $settings.cameraEnabled,
                                  devices: catalog.cameras, selection: $settings.cameraID)
                        deviceRow(icon: "mic", label: "Microphone", isOn: $settings.micEnabled,
                                  devices: catalog.microphones, selection: $settings.micID)
                        if settings.micEnabled {
                            Button {
                                AVCaptureDevice.showSystemUserInterface(.microphoneModes)
                            } label: {
                                Label("Mic Mode (Voice Isolation)…", systemImage: "waveform.badge.mic")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.accent)
                            .padding(.leading, 24)
                            .help("Choose Voice Isolation to remove background noise from your microphone")
                        }
                        ToggleRow(label: "System audio", icon: "speaker.wave.2", isOn: $settings.systemAudio)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Options")
                        HStack {
                            Image(systemName: "timer").frame(width: 16).foregroundStyle(Theme.textDim)
                            Text("Countdown").font(.system(size: 12))
                            Spacer()
                            Picker("", selection: $settings.countdown) {
                                Text("Off").tag(0)
                                Text("3s").tag(3)
                                Text("5s").tag(5)
                                Text("10s").tag(10)
                            }
                            .labelsHidden().pickerStyle(.segmented).frame(width: 130)
                        }
                        HStack {
                            Image(systemName: "speedometer").frame(width: 16).foregroundStyle(Theme.textDim)
                            Text("Frame rate").font(.system(size: 12))
                            Spacer()
                            Picker("", selection: $settings.fps) {
                                Text("30 fps").tag(30)
                                Text("60 fps").tag(60)
                            }
                            .labelsHidden().pickerStyle(.segmented).frame(width: 130)
                        }
                        ToggleRow(label: "Automatic zoom on clicks", icon: "plus.magnifyingglass", isOn: $settings.autoZoom)
                        ToggleRow(label: "Hide desktop icons", icon: "eye.slash", isOn: $settings.hideDesktopIcons)
                        ToggleRow(label: "Record keystrokes", icon: "keyboard", isOn: Binding(get: { settings.recordKeystrokes }, set: { on in
                            settings.recordKeystrokes = on
                            if on && !KeystrokeRecorder.isTrusted { KeystrokeRecorder.requestTrust() }
                            keysTrusted = KeystrokeRecorder.isTrusted
                        }))
                        if settings.recordKeystrokes && !keysTrusted {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Allow Framecast under Accessibility so it can show your shortcuts. Password fields are never captured.")
                                    .font(.system(size: 11)).foregroundStyle(Theme.textDim)
                                    .fixedSize(horizontal: false, vertical: true)
                                Button("Open Accessibility Settings") { NSWorkspace.shared.open(KeystrokeRecorder.settingsURL) }
                                    .buttonStyle(SecondaryButtonStyle())
                            }
                            .padding(.leading, 24)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }

            VStack(spacing: 8) {
                VStack(spacing: 6) {
                    TextField("Name this recording (optional)", text: $settings.nextName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 10).frame(height: 30)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.fill.opacity(0.06)))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))
                    TextField("Why are you recording? (optional note)", text: $settings.nextNote)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .padding(.horizontal, 10).frame(height: 26)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Theme.fill.opacity(0.04)))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.border))
                }
                .padding(.bottom, 4)
                Button {
                    coordinator.start()
                } label: {
                    HStack(spacing: 8) {
                        Circle().fill(.white).frame(width: 10, height: 10)
                        Text(coordinator.isActive ? "Recording…" : "Start Recording")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(PrimaryButtonStyle(color: Theme.record))
                .disabled(coordinator.isActive || !canRecord)
                .opacity(canRecord ? 1 : 0.5)
                Text("Press ⌘⇧2 anywhere to start or stop")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textFaint)
            }
            .padding(20)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            keysTrusted = KeystrokeRecorder.isTrusted
        }
        .sheet(isPresented: $showWindowPicker) {
            WindowPickerSheet(catalog: catalog, settings: settings, isPresented: $showWindowPicker)
        }
    }

    private var canRecord: Bool {
        switch settings.kind {
        case .display: return true
        case .window: return settings.windowID != 0
        case .area: return settings.areaRect != nil
        case .device: return catalog.devices.contains { $0.id == settings.deviceID }
        }
    }

    private var permissionBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Screen Recording permission needed", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.orange)
            Text("Allow Framecast in System Settings → Privacy & Security → Screen & System Audio Recording, then reopen the app.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textDim)
            HStack {
                Button("Request Access") {
                    CGRequestScreenCaptureAccess()
                    Task { await catalog.refresh() }
                }
                .buttonStyle(SecondaryButtonStyle())
                Button("Open Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.orange.opacity(0.3)))
    }

    @ViewBuilder
    private var sourceDetail: some View {
        switch settings.kind {
        case .device:
            if catalog.devices.isEmpty {
                Text("Connect an iPhone or iPad with a cable and unlock it.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.textDim)
            } else {
                Picker("", selection: $settings.deviceID) {
                    ForEach(catalog.devices) { d in Text(d.name).tag(d.id) }
                }
                .labelsHidden()
            }
        case .display:
            displayPicker
        case .window:
            Button {
                Task { await catalog.refresh() }
                showWindowPicker = true
            } label: {
                HStack {
                    Image(systemName: "macwindow")
                    Text(settings.windowID == 0 ? "Choose a window…" : settings.windowTitle)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(Theme.textDim)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
        case .area:
            displayPicker
            Button {
                selectArea()
            } label: {
                HStack {
                    Image(systemName: "rectangle.dashed")
                    if let r = settings.areaRect {
                        Text("Area \(Int(r.width)) × \(Int(r.height))")
                    } else {
                        Text("Select area…")
                    }
                    Spacer()
                    Text(settings.areaRect == nil ? "" : "Change").foregroundStyle(Theme.textDim)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    private var displayPicker: some View {
        Picker("", selection: $settings.displayID) {
            ForEach(catalog.displays, id: \.displayID) { d in
                Text(SourceCatalog.name(for: d)).tag(d.displayID)
            }
        }
        .labelsHidden()
    }

    private func deviceRow(icon: String, label: String, isOn: Binding<Bool>, devices: [DeviceCatalog.Device], selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ToggleRow(label: label, icon: icon, isOn: isOn)
            if isOn.wrappedValue {
                if devices.isEmpty {
                    Text("No \(label.lowercased()) found").font(.system(size: 11)).foregroundStyle(Theme.textFaint)
                        .padding(.leading, 24)
                } else {
                    Picker("", selection: selection) {
                        ForEach(devices) { d in Text(d.name).tag(d.id) }
                    }
                    .labelsHidden()
                    .padding(.leading, 24)
                }
            }
        }
    }

    private func selectArea() {
        let screen = NSScreen.screen(for: settings.displayID) ?? NSScreen.main!
        let home = NSApp.keyWindow
        home?.orderOut(nil)
        Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            if let rect = await AreaSelector.select(on: screen, initial: settings.areaRect, confirmTitle: "Use This Area") {
                settings.areaRect = rect
            }
            home?.makeKeyAndOrderFront(nil)
        }
    }
}

// MARK: - Window picker

struct WindowPickerSheet: View {
    @ObservedObject var catalog: SourceCatalog
    @ObservedObject var settings: RecorderSettings
    @Binding var isPresented: Bool
    /// When set (recording toolbar), picking selects the window and a Start button appears below.
    var onPick: (() -> Void)? = nil
    @State private var thumbnails: [CGWindowID: NSImage] = [:]
    @State private var search = ""
    @State private var picked: CGWindowID?

    private var shown: [SCWindow] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return catalog.windows }
        return catalog.windows.filter {
            ($0.owningApplication?.applicationName ?? "").localizedCaseInsensitiveContains(q)
                || ($0.title ?? "").localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text("Choose a window").font(.system(size: 15, weight: .semibold))
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.textDim)
                    TextField("Search apps and windows", text: $search).textFieldStyle(.plain)
                }
                .padding(.horizontal, 10).frame(width: 220, height: 28)
                .background(RoundedRectangle(cornerRadius: 7).fill(Theme.fill.opacity(0.07)))
                Button("Cancel") { isPresented = false }
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
            ScrollView {
                if shown.isEmpty {
                    Text(catalog.windows.isEmpty ? "No windows to record." : "No windows match “\(search)”.")
                        .font(.system(size: 13)).foregroundStyle(Theme.textDim)
                        .frame(maxWidth: .infinity).padding(.top, 60)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 14)], spacing: 14) {
                    ForEach(shown, id: \.windowID) { w in
                        let isPicked = (onPick == nil ? settings.windowID : picked) == w.windowID
                        Button {
                            settings.windowID = w.windowID
                            settings.windowTitle = [w.owningApplication?.applicationName, w.title]
                                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " — ")
                            if onPick == nil {
                                isPresented = false
                            } else {
                                picked = w.windowID
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8).fill(Theme.fill.opacity(0.08))
                                    if let img = thumbnails[w.windowID] {
                                        Image(nsImage: img).resizable().aspectRatio(contentMode: .fit).padding(6)
                                    } else {
                                        ProgressView().controlSize(.small)
                                    }
                                }
                                .frame(height: 120)
                                .overlay(RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(isPicked ? Theme.accent : Theme.border, lineWidth: isPicked ? 2 : 1))
                                HStack(spacing: 4) {
                                    Text(w.owningApplication?.applicationName ?? "Window")
                                        .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                    if !w.isOnScreen {
                                        Text("Hidden").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(Theme.textDim)
                                            .padding(.horizontal, 5).padding(.vertical, 1)
                                            .background(Capsule().fill(Theme.fill.opacity(0.08)))
                                            .help("On another Space or behind other windows")
                                    }
                                }
                                Text(w.title ?? "").font(.system(size: 11)).foregroundStyle(Theme.textDim).lineLimit(1)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isPicked ? .isSelected : [])
                        .simultaneousGesture(TapGesture(count: 2).onEnded {
                            if onPick != nil { start() }
                        })
                        .task { await loadThumbnail(w) }
                    }
                }
            }
            if onPick != nil {
                Divider()
                HStack(spacing: 16) {
                    RecordingNameFields(width: 300)
                    Spacer()
                    StartRecordingButton { start() }
                        .disabled(picked == nil)
                        .opacity(picked == nil ? 0.5 : 1)
                }
            }
        }
        .padding(20)
        .frame(width: onPick == nil ? 700 : 720, height: onPick == nil ? 520 : 600)
        .background(Theme.panel)
    }

    private func start() {
        guard picked != nil else { return }
        isPresented = false
        onPick?()
    }

    private func loadThumbnail(_ w: SCWindow) async {
        guard thumbnails[w.windowID] == nil else { return }
        let filter = SCContentFilter(desktopIndependentWindow: w)
        let config = SCStreamConfiguration()
        let scale = 360 / max(w.frame.width, 1)
        config.width = max(2, Int(w.frame.width * scale))
        config.height = max(2, Int(w.frame.height * scale))
        config.showsCursor = false
        if let cg = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) {
            thumbnails[w.windowID] = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }
    }
}

// MARK: - Library

private struct LibraryView: View {
    @ObservedObject var library: ProjectLibrary
    @State private var renaming: ProjectSummary?
    @State private var renameText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recordings").font(.system(size: 22, weight: .bold))
                    Text("\(library.projects.count) project\(library.projects.count == 1 ? "" : "s")")
                        .font(.system(size: 12)).foregroundStyle(Theme.textDim)
                }
                Spacer()
                Button {
                    NSWorkspace.shared.open(library.root)
                } label: { Label("Show in Finder", systemImage: "folder") }
                    .buttonStyle(SecondaryButtonStyle())
                Button {
                    library.importVideo()
                } label: { Label("Import Video", systemImage: "square.and.arrow.down") }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .padding(.top, 38)
            .padding(.horizontal, 28)
            .padding(.bottom, 18)

            if library.projects.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 20)], spacing: 22) {
                        ForEach(library.projects) { p in
                            ProjectCard(project: p)
                                .onTapGesture { WindowManager.shared.openEditor(folder: p.folder) }
                                .contextMenu {
                                    Button("Open") { WindowManager.shared.openEditor(folder: p.folder) }
                                    Button("Rename…") { renameText = p.name; renaming = p }
                                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([p.folder]) }
                                    Divider()
                                    Button("Move to Trash…") { if TrashConfirmation.run(name: p.name) { library.delete(p) } }
                                }
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 28)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: $renaming) { p in
            VStack(alignment: .leading, spacing: 12) {
                Text("Rename recording").font(.headline)
                TextField("Name", text: $renameText).textFieldStyle(.roundedBorder).frame(width: 320)
                    .onSubmit { library.rename(p, to: renameText); renaming = nil }
                HStack {
                    Spacer()
                    Button("Cancel") { renaming = nil }.keyboardShortcut(.cancelAction)
                    Button("Rename") { library.rename(p, to: renameText); renaming = nil }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "sparkles.tv")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(Theme.accent)
            Text("No recordings yet").font(.system(size: 17, weight: .semibold))
            Text("Pick what to record on the left and hit Start Recording.\nFramecast adds smooth zooms, a polished cursor and a beautiful background automatically.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ProjectCard: View {
    let project: ProjectSummary
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                Rectangle().fill(Theme.fill.opacity(0.08))
                    .aspectRatio(16.0 / 10.0, contentMode: .fit)
                    .overlay {
                        if let img = project.thumbnail {
                            Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Image(systemName: "film").font(.system(size: 26)).foregroundStyle(Theme.textFaint)
                        }
                    }
                    .clipped()
                Text(formatTime(project.duration))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .foregroundStyle(.white)
                    .background(Capsule().fill(Color.black.opacity(0.65)))
                    .padding(8)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(hover ? Theme.accent.opacity(0.8) : Theme.border, lineWidth: hover ? 2 : 1))
            .scaleEffect(hover ? 1.015 : 1)
            .animation(.easeOut(duration: 0.15), value: hover)

            Text(project.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            if !project.notes.isEmpty {
                Text(project.notes).font(.system(size: 11.5)).foregroundStyle(Theme.textDim).lineLimit(2)
            }
            Text(project.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.system(size: 11)).foregroundStyle(Theme.textDim)
        }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}
