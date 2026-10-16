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

        Settings {
            SettingsView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Recording") { RecordingCoordinator.shared.toggleRecording() }
                Button("Show Recordings") { WindowManager.shared.showHome() }
                    .keyboardShortcut("0", modifiers: [.command])
                Divider()
                Button("Import Video…") { ProjectLibrary.shared.importVideo() }
                    .keyboardShortcut("i", modifiers: [.command])
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
            Button("Start Recording  ⌘⇧2") { recorder.start() }
                .disabled(recorder.isActive)
        }
        Divider()
        Button("Open Framecast") { WindowManager.shared.showHome() }
        Divider()
        Button("Quit Framecast") { NSApp.terminate(nil) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--selftest") || CommandLine.arguments.contains("--recordtest") {
            SelfTest.runIfRequested()
            return
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        GlobalHotKey.shared.register {
            RecordingCoordinator.shared.toggleRecording()
        }
        WindowManager.shared.showHome()
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
            w.backgroundColor = NSColor(Theme.bg)
            w.contentView = NSHostingView(rootView: HomeView())
            w.center()
            w.setFrameAutosaveName("FramecastHome")
            homeWindow = w
        }
        homeWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
            }
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
