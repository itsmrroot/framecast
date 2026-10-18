import SwiftUI
import AppKit
import Carbon.HIToolbox

/// The app's menus, laid out like Screen Studio's, with an icon on every item.
struct FramecastCommands: Commands {
    @ObservedObject private var app = AppSettings.shared
    @ObservedObject private var rec = RecorderSettings.shared

    private static let repo = URL(string: "https://github.com/itsmrroot/framecast")!

    var body: some Commands {
        // Framecast menu
        CommandGroup(replacing: .appInfo) {
            Button { NSApp.orderFrontStandardAboutPanel(nil); NSApp.activate(ignoringOtherApps: true) } label: {
                Label("About Framecast", systemImage: "info.circle")
            }
            Divider()
            Button { Task { await Updater.shared.check(manual: true) } } label: {
                Label("Check for Updates…", systemImage: "arrow.down.circle")
            }
            Button { NSWorkspace.shared.open(Self.repo.appendingPathComponent("releases/tag/v\(Updater.currentVersion)")) } label: {
                Label("What's New in This Version?", systemImage: "sparkles")
            }
            Divider()
            Button { NSWorkspace.shared.open(Self.repo) } label: {
                Label("Open Framecast Website", systemImage: "safari")
            }
            Button { NSWorkspace.shared.open(Self.repo.appendingPathComponent("issues/new")) } label: {
                Label("Send Feedback", systemImage: "envelope")
            }
        }
        CommandGroup(replacing: .appSettings) {
            Button { WindowManager.shared.showSettings() } label: { Label("Settings…", systemImage: "gearshape") }
                .keyboardShortcut(",", modifiers: [.command])
        }

        // File menu
        CommandGroup(replacing: .newItem) {
            Button { RecordingToolbar.shared.show() } label: { Label("New Recording…", systemImage: "record.circle") }
                .keyboardShortcut(.return, modifiers: [.command, .control])
            Divider()
            Button { RecordingToolbar.shared.start(.display, immediate: true) } label: { Label("Record Display", systemImage: "menubar.dock.rectangle") }
                .shortcut(app.shortcuts[.recordDisplay])
            Button { RecordingToolbar.shared.start(.window) } label: { Label("Record Window", systemImage: "macwindow") }
                .shortcut(app.shortcuts[.recordWindow])
            Button { RecordingToolbar.shared.start(.area) } label: { Label("Record Area", systemImage: "rectangle.dashed") }
                .shortcut(app.shortcuts[.recordArea])
            Button { RecordingToolbar.shared.show(); RecordingToolbar.shared.start(.device) } label: { Label("Record iPhone or iPad", systemImage: "iphone") }
            Divider()
            Section("After Recording") {
                Picker("After Recording", selection: $app.afterRecording) {
                    ForEach(AfterRecording.allCases) { a in Text(a.label).tag(a) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Toggle("Automatically Create Zooms", isOn: $rec.autoZoom)
            Divider()
            Menu {
                ForEach(ProjectLibrary.shared.projects.prefix(10)) { p in
                    Button(p.name) { WindowManager.shared.openEditor(folder: p.folder) }
                }
            } label: { Label("Open Recent", systemImage: "clock") }
            Button { MenuBarController.openProject() } label: { Label("Open Project…", systemImage: "folder") }
                .keyboardShortcut("o", modifiers: [.command])
            Button {
                if let last = ProjectLibrary.shared.projects.first { WindowManager.shared.openEditor(folder: last.folder) }
            } label: { Label("Open Last Project", systemImage: "arrow.counterclockwise") }
                .keyboardShortcut("z", modifiers: [.command, .option])
            Button { WindowManager.shared.showHome() } label: { Label("Show Recordings", systemImage: "square.grid.2x2") }
                .keyboardShortcut("0", modifiers: [.command])
            Divider()
            Button { ProjectLibrary.shared.importVideo() } label: { Label("Create Project from Video…", systemImage: "film") }
                .keyboardShortcut("i", modifiers: [.command])
        }
        CommandGroup(replacing: .saveItem) {
            Button { WindowManager.shared.activeEditor?.saveNow() } label: { Label("Save", systemImage: "square.and.arrow.down") }
                .keyboardShortcut("s", modifiers: [.command])
        }
        CommandGroup(replacing: .undoRedo) {
            Button { WindowManager.shared.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                .keyboardShortcut("z", modifiers: [.command])
            Button { WindowManager.shared.redo() } label: { Label("Redo", systemImage: "arrow.uturn.forward") }
                .keyboardShortcut("z", modifiers: [.command, .shift])
        }

        // Edit Video menu
        CommandMenu("Edit Video") {
            Button { WindowManager.shared.activeEditor?.togglePlay() } label: { Label("Play / Pause", systemImage: "playpause") }
            Button { WindowManager.shared.activeEditor?.bladeMode.toggle() } label: { Label("Split Tool", systemImage: "scissors") }
            Button { WindowManager.shared.activeEditor?.splitAtPlayhead() } label: { Label("Cut at Playhead", systemImage: "scissors.badge.ellipsis") }
            Button {
                if let e = WindowManager.shared.activeEditor { e.addZoom(at: e.sourceTime) }
            } label: { Label("Add Zoom at Playhead", systemImage: "plus.magnifyingglass") }
            Menu {
                ForEach(EffectKind.allCases.filter { $0 != .slide }) { kind in
                    Button { WindowManager.shared.activeEditor?.addEffect(kind) } label: { Label(kind.label, systemImage: kind.icon) }
                }
            } label: { Label("Add Effect at Playhead", systemImage: "plus.square.on.square") }
            Menu {
                Button { WindowManager.shared.activeEditor?.addSlide(.intro) } label: { Label("Intro Slide", systemImage: "rectangle.lefthalf.inset.filled") }
                Button { WindowManager.shared.activeEditor?.addSlide(.outro) } label: { Label("Outro Slide", systemImage: "rectangle.righthalf.inset.filled") }
                Button { WindowManager.shared.activeEditor?.addSlide(.here) } label: { Label("Text Slide at Playhead", systemImage: "rectangle.inset.filled") }
            } label: { Label("Add Slide", systemImage: "rectangle.inset.filled") }
            Button {
                if let e = WindowManager.shared.activeEditor, let f = e.insertFreezeFrame(at: e.sourceTime) { e.selection = .clip(f.id) }
            } label: { Label("Freeze Frame at Playhead", systemImage: "snowflake") }
            Button {
                if let e = WindowManager.shared.activeEditor { e.addChapter(at: e.sourceTime) }
            } label: { Label("Chapter Marker at Playhead", systemImage: "list.bullet.rectangle") }
            Divider()
            Button { WindowManager.shared.activeEditorController?.showCrop() } label: { Label("Crop Recording…", systemImage: "crop") }
            Button { WindowManager.shared.activeEditorController?.showPalette() } label: { Label("Command Palette…", systemImage: "command") }
                .keyboardShortcut("k", modifiers: [.command])
            Divider()
            Button { WindowManager.shared.activeEditorController?.showExport() } label: { Label("Export…", systemImage: "square.and.arrow.up") }
                .keyboardShortcut("e", modifiers: [.command])
            Button { WindowManager.shared.activeEditorController?.quickExport(toFile: false) } label: {
                Label("Quick Export to Clipboard", systemImage: "doc.on.clipboard")
            }
            .keyboardShortcut("c", modifiers: [.command, .option])
            Button { WindowManager.shared.activeEditorController?.quickExport(toFile: true) } label: {
                Label("Quick Export to File…", systemImage: "square.and.arrow.down.on.square")
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
        }

        // View menu
        CommandGroup(after: .toolbar) {
            ForEach(InspectorTab.allCases) { tab in
                Button { WindowManager.shared.activeEditorController?.showPanel(tab) } label: { Label(tab.label, systemImage: tab.icon) }
                    .keyboardShortcut(KeyEquivalent(Character("\(tab.number)")), modifiers: [.command])
            }
            Divider()
            Toggle(isOn: $app.showWaveform) { Label("Show Audio Waveform", systemImage: "waveform") }
            Button {
                WindowManager.shared.activeEditor?.loopPlayback.toggle()
            } label: { Label("Loop Playback", systemImage: "repeat") }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            Divider()
            Button { SpeakerNotes.shared.toggle() } label: { Label("Show Speaker Notes", systemImage: "text.alignleft") }
                .shortcut(app.shortcuts[.notes])
            Toggle(isOn: $app.showRecordingWidget) { Label("Show Recording Widget", systemImage: "record.circle") }
            Button {
                if let e = WindowManager.shared.activeEditor { FullScreenPlayer.show(model: e) }
            } label: { Label("Watch Full Screen", systemImage: "arrow.up.left.and.arrow.down.right") }
        }

        // Window menu
        CommandGroup(after: .windowArrangement) {
            Divider()
            Button { WindowManager.shared.resetWindowPositions() } label: { Label("Reset Window Positions", systemImage: "macwindow.on.rectangle") }
            Divider()
            Button { RecordingToolbar.shared.show() } label: { Label("Start Recording", systemImage: "record.circle") }
        }
    }
}

private extension View {
    /// Shows a global shortcut (set in Settings → Shortcuts) next to a menu item.
    @ViewBuilder
    func shortcut(_ combo: KeyCombo?) -> some View {
        if let combo, let ks = combo.keyboardShortcut { self.keyboardShortcut(ks) } else { self }
    }
}

extension KeyCombo {
    var keyboardShortcut: KeyboardShortcut? {
        var mods: SwiftUI.EventModifiers = []
        if modifiers & cmdKey != 0 { mods.insert(.command) }
        if modifiers & optionKey != 0 { mods.insert(.option) }
        if modifiers & controlKey != 0 { mods.insert(.control) }
        if modifiers & shiftKey != 0 { mods.insert(.shift) }
        switch keyCode {
        case kVK_Return: return KeyboardShortcut(.return, modifiers: mods)
        case kVK_Delete: return KeyboardShortcut(.delete, modifiers: mods)
        case kVK_Space: return KeyboardShortcut(.space, modifiers: mods)
        default:
            guard let name = KeyCombo.knownName(keyCode), name.count == 1, let ch = name.lowercased().first else { return nil }
            return KeyboardShortcut(KeyEquivalent(ch), modifiers: mods)
        }
    }
}
