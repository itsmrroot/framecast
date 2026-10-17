import AppKit
import Combine
import Carbon.HIToolbox

/// Framecast's menu bar item: start a recording from anywhere, control one in progress (with the elapsed time
/// shown in the menu bar), and get to projects and settings, even with the Dock icon hidden.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    static let shared = MenuBarController()

    private var item: NSStatusItem?
    private var subs: Set<AnyCancellable> = []

    func update() {
        // With the Dock icon hidden, the menu bar item is the way back into the app, so it always shows.
        let app = AppSettings.shared
        if CommandLine.arguments.contains("--no-menubar") { remove(); return } // debug: compare without the item
        if app.showMenuBarIcon || app.hideDockIcon { install() } else { remove() }
    }

    private func install() {
        guard item == nil else { return }
        let i = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        i.button?.imagePosition = .imageLeading
        i.button?.setAccessibilityLabel("Framecast")
        let menu = NSMenu()
        menu.delegate = self
        i.menu = menu
        item = i
        let rec = RecordingCoordinator.shared
        rec.$phase.combineLatest(rec.$elapsed)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in self?.refreshButton() }
            .store(in: &subs)
        refreshButton()
    }

    private func remove() {
        subs.removeAll()
        if let item { NSStatusBar.system.removeStatusItem(item) }
        item = nil
    }

    /// Idle: the record symbol. Recording: a red dot and the elapsed time; paused: an orange pause symbol.
    private func refreshButton() {
        guard let button = item?.button else { return }
        let rec = RecordingCoordinator.shared
        switch rec.phase {
        case .recording, .paused:
            let paused = rec.phase == .paused
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
                .applying(.init(paletteColors: [paused ? .systemOrange : .systemRed]))
            button.image = NSImage(systemSymbolName: paused ? "pause.circle.fill" : "record.circle.fill",
                                   accessibilityDescription: paused ? "Paused" : "Recording")?.withSymbolConfiguration(config)
            button.image?.isTemplate = false
            button.attributedTitle = NSAttributedString(string: " " + formatTime(rec.elapsed), attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            ])
        default:
            let img = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "Framecast")?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .medium))
            img?.isTemplate = true
            button.image = img
            button.title = ""
        }
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let rec = RecordingCoordinator.shared
        let app = AppSettings.shared
        func add(_ title: String, icon: String? = nil, shortcut: ShortcutAction? = nil, key: String = "",
                 mods: NSEvent.ModifierFlags = [.command], _ action: @escaping () -> Void) {
            let i = ClosureMenuItem(title: title, action: action)
            if let icon { i.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil) }
            if let shortcut, let combo = app.shortcuts[shortcut] {
                Self.setKeyEquivalent(i, combo)
            } else if !key.isEmpty {
                i.keyEquivalent = key
                i.keyEquivalentModifierMask = mods
            }
            menu.addItem(i)
        }

        if rec.isRecording {
            let header = NSMenuItem(title: "\(rec.phase == .paused ? "Paused" : "Recording") · \(formatTime(rec.elapsed))", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            add("Stop Recording", icon: "stop.circle", shortcut: .toggleRecording) { rec.stop() }
            add(rec.phase == .paused ? "Resume" : "Pause", icon: rec.phase == .paused ? "play.circle" : "pause.circle", shortcut: .pauseResume) { rec.togglePause() }
            add("Restart", icon: "arrow.counterclockwise", shortcut: .restart) { rec.restart() }
            add("Add Flag", icon: "flag", shortcut: .flag) { rec.addFlag() }
            add("Show / Hide Controls", icon: "slider.horizontal.below.rectangle", shortcut: .toggleControls) { rec.toggleControls() }
            menu.addItem(.separator())
            add("Discard Recording", icon: "trash") { rec.cancel() }
        } else {
            add("New Recording…", icon: "record.circle", shortcut: .toggleRecording) { RecordingToolbar.shared.show() }
            menu.addItem(.separator())
            add("Record Display", icon: "menubar.dock.rectangle", shortcut: .recordDisplay) { RecordingToolbar.shared.start(.display, immediate: true) }
            add("Record Window", icon: "macwindow", shortcut: .recordWindow) { RecordingToolbar.shared.start(.window) }
            add("Record Area", icon: "rectangle.dashed", shortcut: .recordArea) { RecordingToolbar.shared.start(.area) }
            add("Record iPhone or iPad", icon: "iphone") { RecordingToolbar.shared.show(); RecordingToolbar.shared.start(.device) }
        }
        add(SpeakerNotes.shared.isVisible ? "Hide Speaker Notes" : "Show Speaker Notes", icon: "text.alignleft", shortcut: .notes) {
            SpeakerNotes.shared.toggle()
        }

        menu.addItem(.separator())
        let recent = Array(ProjectLibrary.shared.projects.prefix(8))
        if let last = recent.first {
            add("Open Last Project", icon: "clock.arrow.circlepath", key: "z", mods: [.command, .option]) {
                WindowManager.shared.openEditor(folder: last.folder)
            }
        }
        if recent.count > 1 {
            let sub = NSMenu()
            for p in recent { sub.addItem(ClosureMenuItem(title: p.name) { WindowManager.shared.openEditor(folder: p.folder) }) }
            let i = NSMenuItem(title: "Recent Projects", action: nil, keyEquivalent: "")
            i.image = NSImage(systemSymbolName: "film.stack", accessibilityDescription: nil)
            i.submenu = sub
            menu.addItem(i)
        }
        add("Open Project…", icon: "folder", key: "o") { Self.openProject() }
        add("Show Recordings", icon: "square.grid.2x2") { WindowManager.shared.showHome() }

        menu.addItem(.separator())
        let dock = ClosureMenuItem(title: "Show Framecast in Dock") { app.hideDockIcon.toggle() }
        dock.state = app.hideDockIcon ? .off : .on
        dock.keyEquivalent = "d"
        dock.keyEquivalentModifierMask = [.command]
        menu.addItem(dock)
        add("Settings…", icon: "gearshape", key: ",") { WindowManager.shared.showSettings() }
        add("Check for Updates…", icon: "arrow.down.circle") { Task { await Updater.shared.check(manual: true) } }
        menu.addItem(.separator())
        add("Quit Framecast", key: "q") { NSApp.terminate(nil) }
    }

    /// Shows a global shortcut next to its menu item (the shortcut itself works system-wide anyway).
    private static func setKeyEquivalent(_ item: NSMenuItem, _ combo: KeyCombo) {
        let special: [Int: String] = [
            kVK_Return: "\r", kVK_Delete: "\u{8}", kVK_Tab: "\t", kVK_Space: " ", kVK_Escape: "\u{1b}",
        ]
        guard let key = special[combo.keyCode] ?? KeyCombo.knownName(combo.keyCode).map({ $0.lowercased() }),
              key.count == 1 else { return }
        item.keyEquivalent = key
        var mods: NSEvent.ModifierFlags = []
        if combo.modifiers & cmdKey != 0 { mods.insert(.command) }
        if combo.modifiers & optionKey != 0 { mods.insert(.option) }
        if combo.modifiers & controlKey != 0 { mods.insert(.control) }
        if combo.modifiers & shiftKey != 0 { mods.insert(.shift) }
        item.keyEquivalentModifierMask = mods
    }

    /// Opens a .framecast project from anywhere on disk.
    static func openProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = ProjectLibrary.shared.root
        panel.message = "Choose a Framecast project (.framecast)"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard FileManager.default.fileExists(atPath: url.appendingPathComponent("project.json").path) else {
            let alert = NSAlert()
            alert.messageText = "That isn't a Framecast project"
            alert.informativeText = "Choose a folder ending in .framecast."
            alert.runModal()
            return
        }
        WindowManager.shared.openEditor(folder: url)
    }
}
