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
        window.backgroundColor = NSColor(Theme.bg)
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
            if !mods.subtracting([.function, .numericPad]).isEmpty { return event }
            switch Int(event.keyCode) {
            case kVK_Space:
                self.model.togglePlay(); return nil
            case kVK_ANSI_S:
                self.model.splitAtPlayhead(); return nil
            case kVK_ANSI_Z:
                self.model.addZoom(at: self.model.sourceTime); return nil
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
        Task { await m.writeThumbnail(); ProjectLibrary.shared.reload() }
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
                Rectangle().fill(Theme.border).frame(width: 1)
                InspectorView(model: model, ui: ui)
                    .frame(width: 330)
                    .background(Theme.panel)
            }
            Rectangle().fill(Theme.border).frame(height: 1)
            TimelineView(model: model)
                .frame(height: 230)
                .background(Theme.panel)
        }
        .background(Theme.bg)
        .preferredColorScheme(.dark)
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

    private func commitName() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { model.rename(trimmed) }
        editingName = false
        model.objectWillChange.send()
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    var body: some View {
        HStack(spacing: 10) {
            Spacer().frame(width: 70)
            Group {
                if editingName {
                    TextField("Untitled", text: $name)
                        .textFieldStyle(.plain)
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
            .frame(maxWidth: 320, alignment: .leading)

            Spacer()

            IconButton(icon: "arrow.uturn.backward", help: "Undo (⌘Z)", disabled: !model.canUndo) { model.undo() }
            IconButton(icon: "arrow.uturn.forward", help: "Redo (⇧⌘Z)", disabled: !model.canRedo) { model.redo() }

            Rectangle().fill(Theme.border).frame(width: 1, height: 18)

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

            Menu {
                if presets.presets.isEmpty {
                    Text("No presets yet")
                }
                ForEach(presets.presets) { p in
                    Button(p.name) { model.applyPreset(p.style) }
                }
                Divider()
                Button("Save Current Style as Preset…") { presetName = ""; showSavePreset = true }
                Button("Use Current Style for New Recordings") { presets.setDefault(model.doc.style) }
                Button("Reset Style to Default") { model.applyPreset(Style()) }
            } label: {
                Label("Presets", systemImage: "paintpalette")
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
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(Theme.panel)
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

// MARK: - Preview

private struct PreviewArea: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let avail = CGSize(width: geo.size.width - 48, height: geo.size.height - 32)
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

    var body: some View {
        HStack(spacing: 12) {
            Text(formatTime(model.compTime, fraction: true))
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.text)
                .frame(width: 64, alignment: .trailing)

            IconButton(icon: "backward.end.fill", help: "Go to start") { model.seek(comp: 0) }
            Button {
                model.togglePlay()
            } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.white.opacity(0.12)))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .help("Play / pause (Space)")
            IconButton(icon: "forward.end.fill", help: "Go to end") { model.seek(comp: model.duration) }

            Text(formatTime(model.duration, fraction: true))
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.textDim)
                .frame(width: 64, alignment: .leading)
        }
        .frame(height: 54)
        .frame(maxWidth: .infinity)
    }
}
