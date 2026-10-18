import SwiftUI
import AppKit
import Carbon.HIToolbox

@MainActor
final class EditorUIState: ObservableObject {
    @Published var showExport = false
    @Published var showCrop = false
    @Published var showPalette = false
    @Published var inspectorTab: InspectorTab = .background
    /// Quick export in progress (0…1) and its status line.
    @Published var quickProgress: Double?
    @Published var quickStatus: String?
}

@MainActor
final class EditorWindowController: NSWindowController, NSWindowDelegate {
    let model: EditorModel
    let ui = EditorUIState()
    var onClose: (() -> Void)?
    private var keyMonitor: Any?

    init(model: EditorModel) {
        self.model = model
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 920),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = model.doc.name
        window.minSize = NSSize(width: 1080, height: 700)
        window.backgroundColor = Theme.nsBg
        window.isReleasedWhenClosed = false
        // After a recording, the editor opens on the Space you're on, not the one it was last on.
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.tabbingMode = .disallowed
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: EditorView(model: model, ui: ui))
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            let w = min(1440, f.width * 0.92), h = min(920, f.height * 0.92)
            window.setFrame(NSRect(x: f.midX - w / 2, y: f.midY - h / 2, width: w, height: h), display: false)
        }
        installKeyMonitor()
    }

    required init?(coder: NSCoder) { fatalError() }

    func showExport() { ui.showExport = true }
    func showCrop() { ui.showCrop = true }
    func showPalette() { ui.showPalette = true }

    func showPanel(_ tab: InspectorTab) {
        model.selection = .none
        ui.inspectorTab = tab
    }

    /// Exports with the Quick export settings: to the clipboard (and the Exports folder), or to a file you choose.
    func quickExport(toFile: Bool) {
        guard ui.quickProgress == nil, let job = model.exportJob() else { NSSound.beep(); return }
        let settings = AppSettings.shared.exportSettings
        let ext = settings.format.fileExtension
        let url: URL
        if toFile {
            let panel = SavePanels.make(name: model.doc.name, ext: ext, types: [settings.format == .mp4 ? .mpeg4Movie : .gif])
            guard let u = SavePanels.run(panel) else { return }
            url = u
        } else {
            url = ProjectLibrary.shared.uniqueExportURL(name: model.doc.name, ext: ext)
        }
        model.player.pause()
        ui.quickProgress = 0
        ui.quickStatus = toFile ? "Exporting…" : "Exporting to clipboard…"
        let ui = self.ui
        Task {
            do {
                try await Exporter().export(job: job, settings: settings, to: url) { p in
                    DispatchQueue.main.async { ui.quickProgress = p }
                }
                if toFile {
                    ui.quickStatus = "Saved \(url.lastPathComponent)"
                } else {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([url as NSURL])
                    ui.quickStatus = "Copied. Paste it anywhere."
                }
            } catch {
                ui.quickStatus = "Export failed: \(error.localizedDescription)"
            }
            ui.quickProgress = nil
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if ui.quickProgress == nil { ui.quickStatus = nil }
        }
    }

    /// Everything the command palette offers.
    func paletteCommands() -> [PaletteCommand] {
        let m = model
        var c: [PaletteCommand] = [
            PaletteCommand(id: "play", group: "Playback", title: m.isPlaying ? "Pause" : "Play", icon: "playpause", shortcut: "Space") { m.togglePlay() },
            PaletteCommand(id: "start", group: "Playback", title: "Go to start", icon: "backward.end", shortcut: "Home") { m.seek(comp: 0) },
            PaletteCommand(id: "loop", group: "Playback", title: "Loop playback", icon: "repeat", isOn: m.loopPlayback) { m.loopPlayback.toggle() },
            PaletteCommand(id: "split", group: "Timeline", title: "Cut clip at playhead", icon: "scissors", shortcut: "C") { m.splitAtPlayhead() },
            PaletteCommand(id: "blade", group: "Timeline", title: "Split tool", icon: "scissors.circle", shortcut: "S",
                           hint: "Click anywhere on the timeline to cut; hold ⌥ for a quick cut", isOn: m.bladeMode) { m.bladeMode.toggle() },
            PaletteCommand(id: "slice", group: "Timeline", title: "Remove slice before playhead", icon: "scissors.badge.ellipsis", shortcut: "X") { m.removeSliceBefore() },
            PaletteCommand(id: "resetSpeed", group: "Timeline", title: "Reset all speeds to 1×", icon: "gauge.with.dots.needle.33percent") { m.resetSpeeds() },
            PaletteCommand(id: "idle4", group: "Smart speed", title: "Speed up idle moments 4×", icon: "hare") { m.applySmartSpeed(.idle, speed: 4) },
            PaletteCommand(id: "idleCut", group: "Smart speed", title: "Cut idle moments", icon: "hare") { m.applySmartSpeed(.idle, speed: nil) },
            PaletteCommand(id: "typing", group: "Smart speed", title: "Speed up typing 2×", icon: "keyboard", enabled: !m.keys.isEmpty) { m.applySmartSpeed(.typing, speed: 2) },
            PaletteCommand(id: "addZoom", group: "Zoom", title: "Add zoom at playhead", icon: "plus.magnifyingglass", shortcut: "Z") { m.addZoom(at: m.sourceTime) },
            PaletteCommand(id: "genZoom", group: "Zoom", title: "Generate zooms from clicks", icon: "wand.and.stars",
                           enabled: !m.cursorTrack.clicks.isEmpty) { m.regenerateAutoZooms() },
            PaletteCommand(id: "offZoom", group: "Zoom", title: "Disable all zooms", icon: "eye.slash", isOn: m.doc.style.zoomsDisabled) {
                m.edit(.render) { $0.style.zoomsDisabled.toggle() }
            },
            PaletteCommand(id: "rmZoom", group: "Zoom", title: "Remove all zooms", icon: "trash", enabled: !m.doc.zooms.isEmpty) { m.removeAllZooms() },
            PaletteCommand(id: "crop", group: "Editor", title: "Crop recording…", icon: "crop") { [weak self] in self?.showCrop() },
            PaletteCommand(id: "export", group: "Export", title: "Export…", icon: "square.and.arrow.up", shortcut: "⌘E") { [weak self] in self?.showExport() },
            PaletteCommand(id: "qcopy", group: "Export", title: "Quick export to clipboard", icon: "doc.on.clipboard", shortcut: "⌥⌘C") { [weak self] in self?.quickExport(toFile: false) },
            PaletteCommand(id: "qsave", group: "Export", title: "Quick export to file…", icon: "square.and.arrow.down", shortcut: "⌥⌘S") { [weak self] in self?.quickExport(toFile: true) },
            PaletteCommand(id: "finder", group: "Project", title: "Show project in Finder", icon: "folder") { NSWorkspace.shared.activateFileViewerSelecting([m.folder]) },
            PaletteCommand(id: "save", group: "Project", title: "Save", icon: "square.and.arrow.down.on.square", shortcut: "⌘S") { m.saveNow() },
            PaletteCommand(id: "undo", group: "Project", title: "Undo", icon: "arrow.uturn.backward", shortcut: "⌘Z", enabled: m.canUndo) { m.undo() },
            PaletteCommand(id: "redo", group: "Project", title: "Redo", icon: "arrow.uturn.forward", shortcut: "⇧⌘Z", enabled: m.canRedo) { m.redo() },
            PaletteCommand(id: "quality", group: "View", title: "Preview quality: \(m.previewQuality.next.label.lowercased())",
                           icon: "circle.hexagongrid") { m.previewQuality = m.previewQuality.next },
            PaletteCommand(id: "theme", group: "View", title: "Switch light / dark mode", icon: "circle.lefthalf.filled") { AppSettings.shared.toggleAppearance() },
            PaletteCommand(id: "settings", group: "Application", title: "Settings…", icon: "gearshape", shortcut: "⌘,") { WindowManager.shared.showSettings() },
        ]
        for kind in EffectKind.allCases {
            c.append(PaletteCommand(id: "fx-\(kind.rawValue)", group: "Effects", title: "Add \(kind.label.lowercased())", icon: kind.icon,
                                    shortcut: kind == .blur ? "B" : (kind == .text ? "T" : nil),
                                    enabled: !kind.needsCamera || m.doc.info.hasWebcam) { m.addEffect(kind) })
        }
        for tab in InspectorTab.allCases {
            c.append(PaletteCommand(id: "panel-\(tab.rawValue)", group: "Sidebar", title: "Show \(tab.label) panel", icon: tab.icon,
                                    shortcut: "⌘\(tab.number)") { [weak self] in self?.showPanel(tab) })
        }
        for p in PresetStore.shared.presets {
            c.append(PaletteCommand(id: "preset-\(p.id)", group: "Presets", title: "Apply preset “\(p.name)”", icon: "sparkles") { m.applyPreset(p.style) })
        }
        return c
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, window.isKeyWindow, window.attachedSheet == nil, !self.ui.showExport else { return event }
            // Let text fields handle their own typing.
            if window.firstResponder is NSTextView { return event }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if !mods.subtracting([.function, .numericPad, .capsLock]).isEmpty { return event }
            switch Int(event.keyCode) {
            case kVK_Space:
                self.model.togglePlay(); return nil
            case kVK_ANSI_S:
                self.model.bladeMode.toggle(); return nil
            case kVK_ANSI_C:
                self.model.splitAtPlayhead(); return nil
            case kVK_ANSI_X:
                self.model.removeSliceBefore(); return nil
            case kVK_ANSI_J:
                self.model.shuttle(-1); return nil
            case kVK_ANSI_K:
                self.model.shuttle(0); return nil
            case kVK_ANSI_L:
                self.model.shuttle(1); return nil
            case kVK_ANSI_Z:
                self.model.addZoom(at: self.model.sourceTime); return nil
            case kVK_ANSI_B:
                self.model.addEffect(.blur); return nil
            case kVK_ANSI_T:
                self.model.addEffect(.text); return nil
            case kVK_ANSI_F:
                FullScreenPlayer.show(model: self.model); return nil
            case kVK_Delete, kVK_ForwardDelete:
                self.model.deleteSelection(); return nil
            case kVK_LeftArrow:
                self.model.step(frames: -1); return nil
            case kVK_RightArrow:
                self.model.step(frames: 1); return nil
            case kVK_Escape:
                if self.model.bladeMode { self.model.bladeMode = false } else { self.model.selection = .none }
                return nil
            case kVK_Home:
                self.model.seek(comp: 0); return nil
            default:
                return event
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        model.close()
        let m = model
        if !m.isTrashed { Task { await m.writeThumbnail(); ProjectLibrary.shared.reload() } }
        onClose?()
    }
}

struct EditorView: View {
    @ObservedObject var model: EditorModel
    @ObservedObject var ui: EditorUIState

    var body: some View {
        VStack(spacing: 0) {
            EditorToolbar(model: model, ui: ui)
            Rectangle().fill(Theme.border).frame(height: 1)
            HStack(spacing: 0) {
                PreviewArea(model: model)
                    .overlay(alignment: .bottom) { quickToast }
                    .overlay(alignment: .top) {
                        if let notice = model.notice {
                            Label(notice, systemImage: "info.circle")
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(Capsule().fill(Theme.raised).shadow(color: .black.opacity(0.3), radius: 10, y: 4))
                                .padding(.top, 52)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .animation(.easeOut(duration: 0.2), value: model.notice)
                    .animation(.easeOut(duration: 0.2), value: ui.quickStatus)
                InspectorRail(model: model, ui: ui)
                InspectorView(model: model, ui: ui)
                    .frame(width: 330)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.panel))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding([.top, .bottom, .trailing], 10)
            }
            Rectangle().fill(Theme.border).frame(height: 1)
            TimelineView(model: model)
                .background(Theme.bg)
        }
        .background(Theme.bg)
        .focusEffectDisabled()
        .sheet(isPresented: $ui.showExport) {
            ExportSheet(model: model, isPresented: $ui.showExport)
        }
        .sheet(isPresented: $ui.showCrop) {
            CropSheet(model: model, isPresented: $ui.showCrop)
        }
        .sheet(isPresented: $ui.showPalette) {
            CommandPaletteView(commands: WindowManager.shared.editorController(for: model)?.paletteCommands() ?? [],
                               isPresented: $ui.showPalette)
        }
        .overlay {
            if let err = model.loadError {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 30)).foregroundStyle(.orange)
                    Text("Couldn't load this recording").font(.headline)
                    Text(err).font(.system(size: 12)).foregroundStyle(Theme.textDim)
                }
                .padding(30)
                .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))
            }
        }
    }

    /// Quick-export progress, over the bottom of the preview (clear of the header).
    @ViewBuilder
    private var quickToast: some View {
        if let status = ui.quickStatus {
            HStack(spacing: 10) {
                if let p = ui.quickProgress {
                    ProgressView(value: p).tint(Theme.accent).frame(width: 120)
                    Text("\(Int(p * 100))%").font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.textDim)
                } else {
                    Image(systemName: status.hasPrefix("Export failed") ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(status.hasPrefix("Export failed") ? .orange : .green)
                }
                Text(status).font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Capsule().fill(Theme.raised).shadow(color: .black.opacity(0.3), radius: 10, y: 4))
            .padding(.bottom, 72)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Toolbar

private struct EditorToolbar: View {
    @ObservedObject var model: EditorModel
    @ObservedObject var ui: EditorUIState
    @ObservedObject private var presets = PresetStore.shared
    @State private var name = ""
    @State private var editingName = false
    @FocusState private var nameFocused: Bool
    @State private var showSavePreset = false
    @State private var presetName = ""
    @State private var showShortcuts = false
    @State private var showNotes = false

    private func commitName() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { model.rename(trimmed) }
        editingName = false
        model.objectWillChange.send()
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    var body: some View {
        ZStack {
            HStack(spacing: 6) {
                Spacer().frame(width: 72)
                IconButton(icon: "folder", help: "Show project in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([model.folder])
                }
                IconButton(icon: "trash", help: "Move project to Trash") {
                    if TrashConfirmation.run(name: model.doc.name), model.moveToTrash() {
                        WindowManager.shared.closeEditor(folder: model.folder)
                    }
                }
                IconButton(icon: model.doc.notes.isEmpty ? "note.text" : "note.text.badge.plus",
                           help: model.doc.notes.isEmpty ? "Add a note about this recording" : model.doc.notes,
                           tint: model.doc.notes.isEmpty ? Theme.text : Theme.accent) { showNotes.toggle() }
                    .popover(isPresented: $showNotes, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Note").font(.system(size: 13, weight: .semibold))
                            Text("What is this recording for? Shown in your library.")
                                .font(.system(size: 11)).foregroundStyle(Theme.textDim)
                            TextEditor(text: Binding(get: { model.doc.notes }, set: { model.setNotes($0) }))
                                .font(.system(size: 13))
                                .frame(width: 300, height: 110)
                                .scrollContentBackground(.hidden)
                                .padding(6)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.fill.opacity(0.06)))
                        }
                        .padding(14)
                    }
                Spacer()
                AppearanceButton()
                IconButton(icon: "command", help: "Command palette (⌘K)") { ui.showPalette = true }
                Rectangle().fill(Theme.border).frame(width: 1, height: 18)
                IconButton(icon: "arrow.uturn.backward", help: "Undo (⌘Z)", disabled: !model.canUndo) { model.undo() }
                IconButton(icon: "arrow.uturn.forward", help: "Redo (⇧⌘Z)", disabled: !model.canRedo) { model.redo() }
                Rectangle().fill(Theme.border).frame(width: 1, height: 18)
                Menu {
                    if presets.presets.isEmpty { Text("No presets yet") }
                    ForEach(presets.presets) { p in
                        Button(p.name) { model.applyPreset(p.style) }
                    }
                    Divider()
                    Button("Save Current Style as Preset…") { presetName = ""; showSavePreset = true }
                    Button("Use Current Style for New Recordings") { presets.setDefault(model.doc.style) }
                    Button("Reset Style to Default") { model.applyPreset(Style()) }
                } label: {
                    Label("Presets", systemImage: "sparkles")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Button {
                    ui.showExport = true
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!model.isReady)
            }

            Group {
                if editingName {
                    TextField("Untitled", text: $name)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.center)
                        .focused($nameFocused)
                        .onSubmit { commitName() }
                        .onChange(of: nameFocused) { _, focused in if !focused { commitName() } }
                        .onExitCommand { name = model.doc.name; editingName = false }
                } else {
                    Text(model.doc.name)
                        .lineLimit(1)
                        .onTapGesture {
                            name = model.doc.name
                            editingName = true
                            DispatchQueue.main.async { nameFocused = true }
                        }
                        .help("Click to rename")
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .frame(maxWidth: 380)
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(Theme.bg)
        .sheet(isPresented: $showSavePreset) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Save style preset").font(.headline)
                TextField("Preset name", text: $presetName).textFieldStyle(.roundedBorder).frame(width: 300)
                HStack {
                    Spacer()
                    Button("Cancel") { showSavePreset = false }.keyboardShortcut(.cancelAction)
                    Button("Save") {
                        presets.add(name: presetName.isEmpty ? "Preset \(presets.presets.count + 1)" : presetName, style: model.doc.style)
                        showSavePreset = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
        }
    }
}

private struct ShortcutsPopover: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Keyboard shortcuts").font(.system(size: 13, weight: .semibold)).padding(.bottom, 4)
            ForEach(EditorShortcut.all, id: \.keys) { s in
                HStack {
                    Image(systemName: s.icon).frame(width: 18).foregroundStyle(Theme.textDim)
                    Text(s.title).font(.system(size: 12))
                    Spacer(minLength: 20)
                    Text(s.keys).font(.system(size: 12, weight: .medium).monospaced()).foregroundStyle(Theme.textDim)
                }
            }
        }
        .padding(16)
        .frame(width: 330)
    }
}

// MARK: - Inspector rail

/// Vertical icon tabs between the preview and the inspector.
private struct InspectorRail: View {
    @ObservedObject var model: EditorModel
    @ObservedObject var ui: EditorUIState

    var body: some View {
        VStack(spacing: 6) {
            ForEach(InspectorTab.allCases) { tab in
                let selected = ui.inspectorTab == tab && model.selection == .none
                Button {
                    model.selection = .none
                    ui.inspectorTab = tab
                } label: {
                    Image(systemName: tab.icon)
                        .font(.system(size: 16, weight: selected ? .semibold : .regular))
                        .frame(width: 38, height: 38)
                        .background(RoundedRectangle(cornerRadius: 9).fill(selected ? Theme.accent.opacity(0.22) : .clear))
                        .foregroundStyle(selected ? Theme.text : Theme.textDim)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(tab.label)
            }
            Spacer()
        }
        .padding(.top, 18)
        .frame(width: 54)
    }
}

// MARK: - Preview

private struct PreviewArea: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Menu {
                    ForEach(AspectRatio.allCases) { a in
                        MenuCheck(a.label, model.doc.style.aspect == a) {
                            model.edit(.render) { $0.style.aspect = a }
                        }
                    }
                } label: {
                    Label(model.doc.style.aspect.shortLabel, systemImage: "aspectratio")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Aspect ratio")
                Button {
                    WindowManager.shared.editorController(for: model)?.showCrop()
                } label: {
                    Label(model.doc.style.crop == nil ? "Crop" : "Cropped", systemImage: "crop")
                        .foregroundStyle(model.doc.style.crop == nil ? Theme.text : Theme.accent)
                }
                .buttonStyle(.plain)
                .help("Crop the recording")
                Spacer()
                Menu {
                    ForEach(PreviewQuality.allCases) { q in
                        MenuCheck(q.label, model.previewQuality == q) { model.previewQuality = q }
                    }
                } label: {
                    Label("Preview quality: \(model.previewQuality.short)", systemImage: "circle.hexagongrid")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Lower preview quality plays more smoothly; exports are always full quality")
            }
            .font(.system(size: 12.5))
            .padding(.horizontal, 24)
            .frame(height: 40)

            GeometryReader { geo in
                let avail = CGSize(width: geo.size.width - 48, height: geo.size.height - 16)
                let fit = CGRect(origin: .zero, size: avail).aspectFit(aspect: model.outputAspect)
                ZStack {
                    PlayerLayerView(player: AVPlayerWrapper(player: model.player))
                        .frame(width: max(1, fit.width), height: max(1, fit.height))
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
                        // Click a title or blur/spotlight area to edit it; anywhere else plays or pauses.
                        .gesture(SpatialTapGesture().onEnded { v in
                            let size = CGSize(width: max(1, fit.width), height: max(1, fit.height))
                            if let e = PreviewHitTest.effect(at: v.location, model: model, size: size) {
                                model.player.pause()
                                model.selection = .effect(e.id)
                            } else if !PreviewHitTest.isOnScreen(v.location, model: model, size: size) {
                                // The wallpaper around the recording: open its settings, as Screen Studio does.
                                WindowManager.shared.editorController(for: model)?.showPanel(.background)
                            } else if model.selection != .none, case .effect = model.selection {
                                model.selection = .none
                            } else {
                                model.togglePlay()
                            }
                        })
                    // Edit the selected blur / spotlight area or title right on the video (while paused).
                    // Only while the effect is on screen at the playhead, so you can't drag something you can't see.
                    if !model.isPlaying, let e = model.selectedEffect, !e.disabled,
                       model.sourceTime >= e.start, model.sourceTime <= e.end {
                        let size = CGSize(width: max(1, fit.width), height: max(1, fit.height))
                        if e.kind.hasRegion {
                            // Clipped: while zoomed in, part of the area can be outside the visible frame.
                            RegionCanvasOverlay(model: model, effect: e, size: size).frame(width: size.width, height: size.height)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        } else if e.kind == .text {
                            TitleCanvasOverlay(model: model, effect: e, size: size).frame(width: size.width, height: size.height)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        } else if e.kind == .image {
                            ImageCanvasOverlay(model: model, effect: e, size: size).frame(width: size.width, height: size.height)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .id(e.imageFile)
                        }
                    }
                    if !model.isReady && model.loadError == nil {
                        ProgressView().controlSize(.large)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            TransportBar(model: model)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TransportBar: View {
    @ObservedObject var model: EditorModel

    private func saveFrame() {
        model.player.pause()
        Task {
            guard let image = await model.currentFrameImage() else { NSSound.beep(); return }
            let panel = SavePanels.make(name: "\(model.doc.name) frame", ext: "png", types: [.png])
            guard let url = SavePanels.run(panel),
                  let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return }
            try? data.write(to: url)
        }
    }

    var body: some View {
        ZStack {
            HStack {
                IconButton(icon: "scissors",
                           help: "Split tool: click anywhere on the timeline to cut, until you turn it off (S). C cuts at the playhead.",
                           tint: model.bladeMode ? Theme.accent : Theme.text, active: model.bladeMode) { model.bladeMode.toggle() }
                    .accessibilityLabel(model.bladeMode ? "Turn off split tool" : "Split tool")
                Spacer()
                IconButton(icon: "camera", help: "Save this frame as an image") { saveFrame() }
                    .disabled(!model.isReady)
                IconButton(icon: "arrow.up.left.and.arrow.down.right", help: "Watch full screen (F)") { FullScreenPlayer.show(model: model) }
                    .disabled(!model.isReady)
                    .accessibilityLabel("Watch full screen")
                Menu {
                    ForEach([0.5, 1, 1.5, 2, 4] as [Float], id: \.self) { r in
                        MenuCheck(String(format: "%g×", r), abs(model.playbackRate - r) < 0.01) { model.setPlaybackRate(r) }
                    }
                } label: {
                    Text("\(model.playbackRate, specifier: "%g")×").font(.system(size: 12, weight: .semibold).monospacedDigit())
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Preview playback speed (J / K / L)")
            }
            HStack(spacing: 14) {
                // While hovering the timeline: the hovered time (the preview shows that frame), as Screen Studio does.
                Text(formatTime(model.hoverTime ?? model.compTime, fraction: true))
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.textDim)
                    .frame(width: 64, alignment: .trailing)
                IconButton(icon: "backward.end", help: "Go to start") { model.seek(comp: 0) }
                Button {
                    model.togglePlay()
                } label: {
                    Image(systemName: model.isPlaying ? "pause.circle" : "play.circle")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(Theme.text)
                }
                .buttonStyle(.plain)
                .help("Play / pause (Space)")
                IconButton(icon: "forward.end", help: "Go to end") { model.seek(comp: model.duration) }
                Text(formatTime(model.duration, fraction: true))
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.textDim)
                    .frame(width: 64, alignment: .leading)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 54)
    }
}
