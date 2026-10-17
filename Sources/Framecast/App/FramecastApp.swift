import SwiftUI
import AppKit

@main
struct FramecastApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var recorder = RecordingCoordinator.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(recorder: recorder)
        } label: {
            if recorder.isRecording {
                HStack(spacing: 4) {
                    Image(systemName: recorder.phase == .paused ? "pause.circle.fill" : "record.circle.fill")
                    Text(formatTime(recorder.elapsed)).monospacedDigit()
                }
            } else {
                Image(systemName: "record.circle")
            }
        }

        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { Task { await Updater.shared.check(manual: true) } }
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { WindowManager.shared.showSettings() }
                    .keyboardShortcut(",", modifiers: [.command])
            }
            CommandGroup(replacing: .newItem) {
                Button("New Recording…") { RecordingToolbar.shared.show() }
                    .keyboardShortcut("n", modifiers: [.command])
                Button("Show Recordings") { WindowManager.shared.showHome() }
                    .keyboardShortcut("0", modifiers: [.command])
                Divider()
                Button("Import Video…") { ProjectLibrary.shared.importVideo() }
                    .keyboardShortcut("i", modifiers: [.command])
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") { WindowManager.shared.activeEditor?.saveNow() }
                    .keyboardShortcut("s", modifiers: [.command])
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { WindowManager.shared.undo() }
                    .keyboardShortcut("z", modifiers: [.command])
                Button("Redo") { WindowManager.shared.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
            }
            CommandMenu("Edit Video") {
                Button("Play / Pause") { WindowManager.shared.activeEditor?.togglePlay() }
                Button("Split at Playhead") { WindowManager.shared.activeEditor?.splitAtPlayhead() }
                Button("Add Zoom at Playhead") {
                    if let e = WindowManager.shared.activeEditor { e.addZoom(at: e.sourceTime) }
                }
                Menu("Add Effect at Playhead") {
                    ForEach(EffectKind.allCases) { kind in
                        Button(kind.label) { WindowManager.shared.activeEditor?.addEffect(kind) }
                    }
                }
                Button("Crop Recording…") { WindowManager.shared.activeEditorController?.showCrop() }
                Button("Loop Playback") { WindowManager.shared.activeEditor?.loopPlayback.toggle() }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                Divider()
                Button("Command Palette…") { WindowManager.shared.activeEditorController?.showPalette() }
                    .keyboardShortcut("k", modifiers: [.command])
                Divider()
                Button("Export…") { WindowManager.shared.activeEditorController?.showExport() }
                    .keyboardShortcut("e", modifiers: [.command])
                Button("Quick Export to Clipboard") { WindowManager.shared.activeEditorController?.quickExport(toFile: false) }
                    .keyboardShortcut("c", modifiers: [.command, .option])
                Button("Quick Export to File…") { WindowManager.shared.activeEditorController?.quickExport(toFile: true) }
                    .keyboardShortcut("s", modifiers: [.command, .option])
            }
            CommandGroup(after: .toolbar) {
                ForEach(InspectorTab.allCases) { tab in
                    Button("\(tab.label) Panel") { WindowManager.shared.activeEditorController?.showPanel(tab) }
                        .keyboardShortcut(KeyEquivalent(Character("\(tab.number)")), modifiers: [.command])
                }
            }
        }
    }
}

struct MenuBarContent: View {
    @ObservedObject var recorder: RecordingCoordinator

    var body: some View {
        if recorder.isRecording {
            Button("Stop Recording  ⌘⇧2") { recorder.stop() }
            Button(recorder.phase == .paused ? "Resume" : "Pause") { recorder.togglePause() }
            Button("Restart") { recorder.restart() }
            Button("Cancel Recording") { recorder.cancel() }
        } else {
            Button("New Recording…  ⌘⇧2") { RecordingToolbar.shared.show() }
                .disabled(recorder.isActive)
            Button("Record Display") { RecordingToolbar.shared.start(.display) }
                .disabled(recorder.isActive)
        }
        Divider()
        Button("Open Framecast") { WindowManager.shared.showHome() }
        Button("Check for Updates…") { Task { await Updater.shared.check(manual: true) } }
        Button("Settings…") { WindowManager.shared.showSettings() }
        Divider()
        Button("Quit Framecast") { NSApp.terminate(nil) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--updatecheck") {
            Task { @MainActor in
                do {
                    let r = try await Updater.fetchLatest()
                    print("current \(Updater.currentVersion), suffix \(Updater.assetSuffix)")
                    print(r.map { "newer: \($0.version) asset: \($0.asset?.name ?? "none") sha256: \($0.asset?.sha256 ?? "none")" } ?? "up to date")
                    // End-to-end test: download, verify and replace this copy of the app.
                    guard r != nil, CommandLine.arguments.contains("--install") else { exit(0) }
                    let updater = Updater.shared
                    await updater.check(manual: false)
                    updater.updateNow()
                    while true {
                        try await Task.sleep(nanoseconds: 500_000_000)
                        if case .failed(let msg) = updater.phase { print("install failed: \(msg)"); exit(1) }
                    }
                } catch {
                    print("check failed: \(error)")
                    exit(1)
                }
            }
            return
        }
        // Renders the recording toolbar to a PNG (floating panels are hidden from screenshots): --snapshot-toolbar <file>
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot-toolbar"), CommandLine.arguments.count > i + 1 {
            let out = URL(fileURLWithPath: CommandLine.arguments[i + 1])
            Task { @MainActor in
                await SourceCatalog.shared.refresh()
                let r = ImageRenderer(content: RecordingToolbarView(toolbar: RecordingToolbar.shared).padding(20).background(Color(white: 0.3)))
                r.scale = 2
                if let cg = r.cgImage, let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
                    try? data.write(to: out)
                }
                exit(0)
            }
            return
        }
        if CommandLine.arguments.contains("--selftest") || CommandLine.arguments.contains("--recordtest")
            || CommandLine.arguments.contains("--checks") {
            SelfTest.runIfRequested()
            return
        }
        NSApp.setActivationPolicy(.regular)
        AppSettings.shared.applyAppearance()
        HotKeyCenter.shared.registerAll()
        MenuBarController.shared.update()
        let opensProject = CommandLine.arguments.contains("--open")
        if AppSettings.shared.launchView == .home || opensProject {
            WindowManager.shared.showHome()
        } else {
            // Ready to record straight away; the home window is one click away (folder button).
            RecordingToolbar.shared.show()
        }
        Updater.shared.checkOnLaunch()
        // Opens a window on launch (handy for screenshots): --show toolbar | settings
        if let i = CommandLine.arguments.firstIndex(of: "--show"), CommandLine.arguments.count > i + 1 {
            switch CommandLine.arguments[i + 1] {
            case "toolbar": RecordingToolbar.shared.show()
            case "settings": WindowManager.shared.showSettings()
            case let v:
                // Editor views, once an editor opened with --open is up: crop, palette, panel:<name>.
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    guard let c = WindowManager.shared.activeEditorController ?? WindowManager.shared.anyEditorController else { return }
                    if v == "crop" { c.showCrop() }
                    if v == "palette" { c.showPalette() }
                    if v == "blade" { c.model.bladeMode = true }
                    if v.hasPrefix("panel:"), let tab = InspectorTab(rawValue: String(v.dropFirst(6))) { c.showPanel(tab) }
                    if v.hasPrefix("select:"), let kind = EffectKind(rawValue: String(v.dropFirst(7))),
                       let e = c.model.doc.effects.first(where: { $0.kind == kind }) {
                        c.model.selection = .effect(e.id)
                        c.model.seek(source: e.start + min(0.3, e.duration / 2))
                    }
                }
            }
        }
        if let i = CommandLine.arguments.firstIndex(of: "--open"), CommandLine.arguments.count > i + 1 {
            WindowManager.shared.openEditor(folder: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Clicking the Dock icon: the toolbar first (if that's the launch choice), the home window when the toolbar is already up.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated {
            if WindowManager.shared.hasOpenWindows || WindowManager.shared.hasMinimizedWindows {
                WindowManager.shared.bringWindowsForward()
                return
            }
            if AppSettings.shared.launchView == .toolbar && !RecordingToolbar.shared.isVisible
                && RecordingCoordinator.shared.phase == .idle {
                RecordingToolbar.shared.show()
            } else {
                WindowManager.shared.showHome()
            }
        }
        return true
    }

    /// Right-click on the Dock icon.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        MainActor.assumeIsolated {
            let menu = NSMenu()
            func item(_ title: String, _ action: @escaping () -> Void) -> NSMenuItem {
                let i = ClosureMenuItem(title: title, action: action)
                return i
            }
            let rec = RecordingCoordinator.shared
            if rec.isRecording {
                menu.addItem(item("Stop Recording") { rec.stop() })
                menu.addItem(item(rec.phase == .paused ? "Resume" : "Pause") { rec.togglePause() })
            } else {
                menu.addItem(item("New Recording…") { RecordingToolbar.shared.show() })
                menu.addItem(item("Record Display") { RecordingToolbar.shared.start(.display, immediate: true) })
            }
            menu.addItem(.separator())
            let recent = Array(ProjectLibrary.shared.projects.prefix(5))
            if let last = recent.first {
                menu.addItem(item("Open Last Project") { WindowManager.shared.openEditor(folder: last.folder) })
            }
            if recent.count > 1 {
                let sub = NSMenu()
                for p in recent { sub.addItem(item(p.name) { WindowManager.shared.openEditor(folder: p.folder) }) }
                let recentItem = NSMenuItem(title: "Recent Projects", action: nil, keyEquivalent: "")
                recentItem.submenu = sub
                menu.addItem(recentItem)
            }
            menu.addItem(item("Show Recordings") { WindowManager.shared.showHome() })
            menu.addItem(.separator())
            let dock = item("Show Framecast in Dock") { AppSettings.shared.hideDockIcon.toggle() }
            dock.state = AppSettings.shared.hideDockIcon ? .off : .on
            menu.addItem(dock)
            menu.addItem(item("Settings…") { WindowManager.shared.showSettings() })
            return menu
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        WindowManager.shared.saveAll()
    }
}

@MainActor
final class WindowManager: NSObject, NSWindowDelegate {
    static let shared = WindowManager()

    private var homeWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var editors: [URL: EditorWindowController] = [:]
    private var hiddenForRecording: [NSWindow] = []

    var activeEditorController: EditorWindowController? {
        if let key = NSApp.keyWindow, let c = editors.values.first(where: { $0.window === key }) { return c }
        if let main = NSApp.mainWindow, let c = editors.values.first(where: { $0.window === main }) { return c }
        return nil
    }

    var activeEditor: EditorModel? { activeEditorController?.model }

    func undo() {
        // While typing, ⌘Z undoes the text, not the project.
        if NSApp.keyWindow?.firstResponder is NSTextView || activeEditor == nil {
            NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
        } else {
            activeEditor?.undo()
        }
    }

    func redo() {
        if NSApp.keyWindow?.firstResponder is NSTextView || activeEditor == nil {
            NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
        } else {
            activeEditor?.redo()
        }
    }

    var anyEditorController: EditorWindowController? { editors.values.first }

    /// Whether the home window, Settings or an editor is on screen.
    var hasMinimizedWindows: Bool {
        appWindows.contains { $0.isMiniaturized }
    }

    private var appWindows: [NSWindow] {
        [homeWindow, settingsWindow].compactMap { $0 } + editors.values.compactMap { $0.window }
    }

    /// Dock click with windows open: bring them forward (from other Spaces or the Dock), as macOS apps do.
    func bringWindowsForward() {
        NSApp.setActivationPolicy(.regular)
        let windows = appWindows.filter { $0.isVisible || $0.isMiniaturized }
        for w in windows where w.isMiniaturized { w.deminiaturize(nil) }
        let front = windows.first { $0.isKeyWindow } ?? windows.last
        for w in windows where w !== front { w.orderFront(nil) }
        front?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    var hasOpenWindows: Bool {
        [homeWindow, settingsWindow].contains { $0?.isVisible == true } || editors.values.contains { $0.window?.isVisible == true }
    }

    func editorController(for model: EditorModel) -> EditorWindowController? {
        editors.values.first { $0.model === model }
    }

    func editor(for folder: URL) -> EditorModel? {
        editors.first { $0.key.standardizedFileURL.path == folder.standardizedFileURL.path }?.value.model
    }

    func showHome() {
        restoreHidden()
        if homeWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Framecast"
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 860, height: 560)
            w.backgroundColor = Theme.nsBg
            w.contentView = NSHostingView(rootView: HomeView())
            w.center()
            w.setFrameAutosaveName("FramecastHome")
            w.delegate = self
            homeWindow = w
        }
        NSApp.setActivationPolicy(.regular)
        homeWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showSettings(tab: SettingsTab) {
        SettingsNavigation.shared.tab = tab
        showSettings()
    }

    func showSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: SettingsWindowView.height),
                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.title = "Settings"
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.backgroundColor = Theme.nsBg
            w.contentView = NSHostingView(rootView: SettingsWindowView())
            w.center()
            w.setFrameAutosaveName("FramecastSettings")
            w.delegate = self
            settingsWindow = w
        }
        NSApp.setActivationPolicy(.regular)
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// With "Hide Dock icon" on, the icon only shows while a window is open or a recording is running.
    func updateDockIcon() {
        let visible = [homeWindow, settingsWindow].contains { $0?.isVisible == true } || !editors.isEmpty
            || RecordingCoordinator.shared.isActive
        let policy: NSApplication.ActivationPolicy = AppSettings.shared.hideDockIcon && !visible ? .accessory : .regular
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { self.updateDockIcon() }
    }

    func hideAllForRecording() {
        // Added to (not replaced): a restart hides again while the first start's windows are still hidden.
        let visible = NSApp.windows.filter { w in
            w.isVisible && (w === homeWindow || w === settingsWindow || editors.values.contains { $0.window === w })
        }
        for w in visible where !hiddenForRecording.contains(where: { $0 === w }) { hiddenForRecording.append(w) }
        editors.values.forEach { $0.model.player.pause() }
        for w in visible { w.orderOut(nil) }
    }

    /// Brings back every window hidden for a recording that was cancelled, including the home window.
    func restoreHiddenWindows() {
        for w in hiddenForRecording { w.orderFront(nil) }
        hiddenForRecording = []
    }

    private func restoreHidden() {
        for w in hiddenForRecording where w !== homeWindow { w.orderFront(nil) }
        hiddenForRecording = []
    }

    func openEditor(folder: URL) {
        hiddenForRecording = hiddenForRecording.filter { $0 !== homeWindow }
        restoreHidden()
        if let existing = editors[folder] {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        do {
            let model = try EditorModel(folder: folder)
            let controller = EditorWindowController(model: model)
            controller.onClose = { [weak self] in
                self?.editors[folder] = nil
                ProjectLibrary.shared.reload()
                self?.updateDockIcon()
            }
            NSApp.setActivationPolicy(.regular)
            editors[folder] = controller
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn't open recording"
            alert.runModal()
        }
    }

    func closeEditor(folder: URL) {
        editors[folder]?.window?.close()
    }

    func saveAll() {
        for e in editors.values { e.model.saveNow() }
    }
}

/// A menu item that runs a closure (for menus built in code, like the Dock menu).
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, action handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func run() { handler() }
}
