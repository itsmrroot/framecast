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
                Divider()
                Button("Export…") { WindowManager.shared.activeEditorController?.showExport() }
                    .keyboardShortcut("e", modifiers: [.command])
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
        if CommandLine.arguments.contains("--selftest") || CommandLine.arguments.contains("--recordtest") {
            SelfTest.runIfRequested()
            return
        }
        NSApp.setActivationPolicy(.regular)
        AppSettings.shared.applyAppearance()
        DeviceCapture.enableDiscovery()
        HotKeyCenter.shared.registerAll()
        WindowManager.shared.showHome()
        Updater.shared.checkOnLaunch()
        // Opens a window on launch (handy for screenshots): --show toolbar | settings
        if let i = CommandLine.arguments.firstIndex(of: "--show"), CommandLine.arguments.count > i + 1 {
            switch CommandLine.arguments[i + 1] {
            case "toolbar": RecordingToolbar.shared.show()
            case "settings": WindowManager.shared.showSettings()
            default: break
            }
        }
        if let i = CommandLine.arguments.firstIndex(of: "--open"), CommandLine.arguments.count > i + 1 {
            WindowManager.shared.openEditor(folder: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { WindowManager.shared.showHome() }
        return true
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
        if let e = activeEditor { e.undo() } else { NSApp.sendAction(Selector(("undo:")), to: nil, from: nil) }
    }

    func redo() {
        if let e = activeEditor { e.redo() } else { NSApp.sendAction(Selector(("redo:")), to: nil, from: nil) }
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

    func showSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 620),
                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.title = "Settings"
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.backgroundColor = Theme.nsBg
            w.contentView = NSHostingView(rootView: SettingsWindowView())
            w.center()
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
        hiddenForRecording = NSApp.windows.filter { w in
            w.isVisible && (w === homeWindow || editors.values.contains { $0.window === w })
        }
        editors.values.forEach { $0.model.player.pause() }
        for w in hiddenForRecording { w.orderOut(nil) }
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
