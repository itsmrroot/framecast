import SwiftUI
import AppKit
import Carbon.HIToolbox

@MainActor
final class EditorUIState: ObservableObject {
    @Published var showExport = false
    @Published var inspectorTab: InspectorTab = .background
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
            case kVK_ANSI_S, kVK_ANSI_C:
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
            case kVK_Delete, kVK_ForwardDelete:
                self.model.deleteSelection(); return nil
            case kVK_LeftArrow:
                self.model.step(frames: -1); return nil
            case kVK_RightArrow:
                self.model.step(frames: 1); return nil
            case kVK_Escape:
                self.model.selection = .none; return nil
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
                InspectorRail(model: model, ui: ui)
                InspectorView(model: model, ui: ui)
                    .frame(width: 330)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.panel))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding([.top, .bottom, .trailing], 10)
            }
            Rectangle().fill(Theme.border).frame(height: 1)
            TimelineView(model: model)
                .frame(height: 262)
                .background(Theme.bg)
        }
        .background(Theme.bg)
        .focusEffectDisabled()
        .sheet(isPresented: $ui.showExport) {
            ExportSheet(model: model, isPresented: $ui.showExport)
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
    @State private var confirmTrash = false

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
                IconButton(icon: "trash", help: "Move project to Trash") { confirmTrash = true }
                Spacer()
                AppearanceButton()
                IconButton(icon: "command", help: "Keyboard shortcuts") { showShortcuts.toggle() }
                    .popover(isPresented: $showShortcuts, arrowEdge: .bottom) { ShortcutsPopover() }
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
        .confirmationDialog("Move “\(model.doc.name)” to the Trash?", isPresented: $confirmTrash) {
            Button("Move to Trash", role: .destructive) {
                if model.moveToTrash() { WindowManager.shared.closeEditor(folder: model.folder) }
            }
            Button("Cancel", role: .cancel) {}
        }
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
                        Button {
                            model.edit(.render) { $0.style.aspect = a }
                        } label: {
                            if model.doc.style.aspect == a { Label(a.label, systemImage: "checkmark") } else { Text(a.label) }
                        }
                    }
                } label: {
                    Label(model.doc.style.aspect.shortLabel, systemImage: "aspectratio")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Aspect ratio")
                Spacer()
                Menu {
                    Button { model.previewFull = true } label: { if model.previewFull { Label("Full", systemImage: "checkmark") } else { Text("Full") } }
                    Button { model.previewFull = false } label: { if !model.previewFull { Label("Half (faster)", systemImage: "checkmark") } else { Text("Half (faster)") } }
                } label: {
                    Label("Preview quality: \(model.previewFull ? "Full" : "Half")", systemImage: "circle.hexagongrid")
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
                        .onTapGesture { model.togglePlay() }
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
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "\(model.doc.name.replacingOccurrences(of: "/", with: "-")) frame.png"
            panel.allowedContentTypes = [.png]
            panel.directoryURL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            guard panel.runModal() == .OK, let url = panel.url,
                  let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return }
            try? data.write(to: url)
        }
    }

    var body: some View {
        ZStack {
            HStack {
                IconButton(icon: "scissors", help: "Cut clip at playhead (C)") { model.splitAtPlayhead() }
                Spacer()
                IconButton(icon: "camera", help: "Save this frame as an image") { saveFrame() }
                    .disabled(!model.isReady)
                Menu {
                    ForEach([0.5, 1, 1.5, 2, 4] as [Float], id: \.self) { r in
                        Button { model.setPlaybackRate(r) } label: {
                            if abs(model.playbackRate - r) < 0.01 { Label("\(r, specifier: "%g")×", systemImage: "checkmark") } else { Text("\(r, specifier: "%g")×") }
                        }
                    }
                } label: {
                    Text("\(model.playbackRate, specifier: "%g")×").font(.system(size: 12, weight: .semibold).monospacedDigit())
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Preview playback speed (J / K / L)")
            }
            HStack(spacing: 14) {
                Text(formatTime(model.compTime, fraction: true))
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
