import Foundation
import AppKit
import ServiceManagement
import Carbon.HIToolbox

/// App-wide preferences (the Settings window). Recording source options live in `RecorderSettings`.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    // General
    /// What appears when Framecast opens: the recording toolbar (like a camera app) or the home window.
    @Published var launchView: LaunchView { didSet { d.set(launchView.rawValue, forKey: "app.launchView") } }
    @Published var appearance: AppAppearance { didSet { d.set(appearance.rawValue, forKey: "app.appearance"); applyAppearance() } }
    @Published var hideDockIcon: Bool { didSet { d.set(hideDockIcon, forKey: "app.hideDock"); WindowManager.shared.updateDockIcon(); MenuBarController.shared.update() } }
    @Published var showWaveform: Bool { didSet { d.set(showWaveform, forKey: "app.waveform") } }
    @Published var showMenuBarIcon: Bool { didSet { d.set(showMenuBarIcon, forKey: "app.menuBarIcon"); MenuBarController.shared.update() } }

    // Recording
    @Published var projectsFolder: String { didSet { d.set(projectsFolder, forKey: "app.projectsFolder") } }
    @Published var highlightRecordedArea: Bool { didSet { d.set(highlightRecordedArea, forKey: "app.highlightArea") } }
    /// Keep Framecast's own windows on screen (and in the recording), for recording tutorials about Framecast.
    @Published var recordFramecastWindows: Bool { didSet { d.set(recordFramecastWindows, forKey: "app.recordOwnWindows") } }
    @Published var showRecordingWidget: Bool { didSet { d.set(showRecordingWidget, forKey: "app.recordingWidget") } }
    @Published var cameraResolution: Int { didSet { d.set(cameraResolution, forKey: "app.cameraResolution") } }
    @Published var showCameraPreview: Bool { didSet { d.set(showCameraPreview, forKey: "app.cameraPreview") } }

    // Editing
    @Published var useLastProjectStyle: Bool { didSet { d.set(useLastProjectStyle, forKey: "app.useLastStyle") } }
    @Published var autosave: Bool { didSet { d.set(autosave, forKey: "app.autosave") } }

    // Quick export
    @Published var exportFormat: String { didSet { d.set(exportFormat, forKey: "export.format") } }
    @Published var exportFPS: Int { didSet { d.set(exportFPS, forKey: "export.fps") } }
    @Published var exportResolution: Int { didSet { d.set(exportResolution, forKey: "export.resolution") } }
    @Published var exportQuality: String { didSet { d.set(exportQuality, forKey: "export.quality") } }
    @Published var exportCodec: String { didSet { d.set(exportCodec, forKey: "export.codec") } }
    @Published var showQuickExportWidget: Bool { didSet { d.set(showQuickExportWidget, forKey: "export.widget") } }
    /// What happens when a recording stops.
    @Published var afterRecording: AfterRecording { didSet { d.set(afterRecording.rawValue, forKey: "rec.after") } }

    // Advanced
    @Published var disableHardwareAcceleration: Bool { didSet { d.set(disableHardwareAcceleration, forKey: "adv.noHW") } }

    // Shortcuts
    @Published private(set) var shortcuts: [ShortcutAction: KeyCombo] = [:]

    private init() {
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies")
        d.register(defaults: [
            "app.projectsFolder": movies.appendingPathComponent("Framecast").path,
            "app.highlightArea": true,
            "app.recordingWidget": true,
            "app.menuBarIcon": true,
            "app.waveform": true,
            "app.cameraResolution": 1080,
            "app.cameraPreview": true,
            "app.autosave": true,
            "export.format": ExportFormat.mp4.rawValue,
            "export.fps": 60,
            "export.resolution": ExportResolution.p1080.rawValue,
            "export.quality": ExportQuality.high.rawValue,
            "export.codec": ExportCodec.h264.rawValue,
        ])
        launchView = LaunchView(rawValue: d.string(forKey: "app.launchView") ?? "") ?? .toolbar
        appearance = AppAppearance(rawValue: d.string(forKey: "app.appearance") ?? "") ?? .dark
        hideDockIcon = d.bool(forKey: "app.hideDock")
        showMenuBarIcon = d.bool(forKey: "app.menuBarIcon")
        showWaveform = d.bool(forKey: "app.waveform")
        projectsFolder = d.string(forKey: "app.projectsFolder") ?? movies.appendingPathComponent("Framecast").path
        highlightRecordedArea = d.bool(forKey: "app.highlightArea")
        recordFramecastWindows = d.bool(forKey: "app.recordOwnWindows")
        showRecordingWidget = d.bool(forKey: "app.recordingWidget")
        cameraResolution = d.integer(forKey: "app.cameraResolution")
        showCameraPreview = d.bool(forKey: "app.cameraPreview")
        useLastProjectStyle = d.bool(forKey: "app.useLastStyle")
        autosave = d.bool(forKey: "app.autosave")
        exportFormat = d.string(forKey: "export.format") ?? "mp4"
        exportFPS = d.integer(forKey: "export.fps")
        exportResolution = d.integer(forKey: "export.resolution")
        exportQuality = d.string(forKey: "export.quality") ?? "high"
        exportCodec = d.string(forKey: "export.codec") ?? "h264"
        showQuickExportWidget = d.bool(forKey: "export.widget")
        afterRecording = AfterRecording(rawValue: d.string(forKey: "rec.after") ?? "") ?? .createProject
        disableHardwareAcceleration = d.bool(forKey: "adv.noHW")

        var map: [ShortcutAction: KeyCombo] = [:]
        let saved = d.dictionary(forKey: "shortcuts") as? [String: [Int]] ?? [:]
        for a in ShortcutAction.allCases {
            if let v = saved[a.rawValue] {
                if v.count == 2 { map[a] = KeyCombo(keyCode: v[0], modifiers: v[1]) }
                // An empty array means the user removed the shortcut.
            } else {
                map[a] = a.defaultCombo
            }
        }
        shortcuts = map
    }

    /// Default export settings for the export sheet and the quick export widget.
    var exportSettings: ExportSettings {
        var s = ExportSettings()
        s.format = ExportFormat(rawValue: exportFormat) ?? .mp4
        s.fps = ExportSettings.frameRates.contains(exportFPS) ? exportFPS : 60
        s.resolution = ExportResolution(rawValue: exportResolution) ?? .p1080
        s.quality = ExportQuality(rawValue: exportQuality) ?? .high
        s.codec = ExportCodec(rawValue: exportCodec) ?? .h264
        s.disableHardwareAcceleration = disableHardwareAcceleration
        return s
    }

    // MARK: Appearance

    func applyAppearance() {
        switch appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    /// Whether the app is showing dark mode right now (resolving "System").
    var isDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    /// The sun / moon button: switches between light and dark.
    func toggleAppearance() {
        appearance = isDark ? .light : .dark
    }

    // MARK: Launch at login

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Framecast: launch at login change failed: \(error)")
            }
            if newValue && SMAppService.mainApp.status != .enabled {
                // macOS wants the user to allow it in Login Items.
                SMAppService.openSystemSettingsLoginItems()
            }
        }
    }

    // MARK: Shortcuts

    func setShortcut(_ combo: KeyCombo?, for action: ShortcutAction) {
        // One combo can only trigger one action.
        if let combo {
            for (other, c) in shortcuts where other != action && c == combo { shortcuts[other] = nil }
        }
        shortcuts[action] = combo
        var out: [String: [Int]] = [:]
        for a in ShortcutAction.allCases {
            if let c = shortcuts[a] { out[a.rawValue] = [c.keyCode, c.modifiers] } else { out[a.rawValue] = [] }
        }
        d.set(out, forKey: "shortcuts")
        HotKeyCenter.shared.registerAll()
    }

    func resetShortcuts() {
        d.removeObject(forKey: "shortcuts")
        for a in ShortcutAction.allCases { shortcuts[a] = a.defaultCombo }
        HotKeyCenter.shared.registerAll()
    }

    func resetAll() {
        for key in d.dictionaryRepresentation().keys where key.hasPrefix("app.") || key.hasPrefix("export.")
            || key.hasPrefix("adv.") || key.hasPrefix("rec.") || key == "shortcuts" || key == "update.auto"
            || key == "defaultStyle" {
            d.removeObject(forKey: key)
        }
        try? SMAppService.mainApp.unregister()
    }
}

enum AfterRecording: String, CaseIterable, Identifiable {
    case createProject, copyToClipboard, saveToFile
    var id: String { rawValue }
    var label: String {
        switch self {
        case .createProject: return "Create project"
        case .copyToClipboard: return "Export and copy to clipboard"
        case .saveToFile: return "Export and save to file"
        }
    }
    var shortLabel: String {
        switch self {
        case .createProject: return "Edit"
        case .copyToClipboard: return "Export & copy"
        case .saveToFile: return "Export & save"
        }
    }
}

enum LaunchView: String, CaseIterable, Identifiable {
    case toolbar, home
    var id: String { rawValue }
    var label: String { self == .toolbar ? "Recording toolbar" : "Home window" }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }
}

// MARK: - Shortcuts

enum ShortcutAction: String, CaseIterable, Identifiable {
    case toggleRecording, pauseResume, restart, flag, recordDisplay, recordWindow, recordArea, toggleControls, notes, prompter
    var id: String { rawValue }

    var title: String {
        switch self {
        case .toggleRecording: return "Start new recording / Finish recording"
        case .pauseResume: return "Resume / pause recording in progress"
        case .restart: return "Restart recording in progress"
        case .flag: return "Create recording flag"
        case .recordDisplay: return "Record entire display"
        case .recordWindow: return "Record single window"
        case .recordArea: return "Record area"
        case .toggleControls: return "Show / hide recording controls"
        case .notes: return "Show / hide speaker notes"
        case .prompter: return "Start / stop scrolling speaker notes"
        }
    }

    var detail: String? {
        switch self {
        case .toggleRecording: return "Opens the recording toolbar from anywhere, and stops the current recording."
        case .flag: return "Marks a moment while recording. Flags appear on the timeline."
        case .toggleControls: return "Shows or hides the floating controls while recording."
        default: return nil
        }
    }

    var icon: String {
        switch self {
        case .toggleRecording: return "record.circle"
        case .pauseResume: return "playpause"
        case .restart: return "arrow.counterclockwise"
        case .flag: return "flag"
        case .recordDisplay: return "display"
        case .recordWindow: return "macwindow"
        case .recordArea: return "rectangle.dashed"
        case .toggleControls: return "rectangle.inset.bottomright.filled"
        case .notes: return "text.alignleft"
        case .prompter: return "text.line.first.and.arrowtriangle.forward"
        }
    }

    var defaultCombo: KeyCombo {
        let co = cmdKey | optionKey
        switch self {
        case .toggleRecording: return KeyCombo(keyCode: kVK_ANSI_2, modifiers: cmdKey | shiftKey)
        case .pauseResume: return KeyCombo(keyCode: kVK_ANSI_P, modifiers: co)
        case .restart: return KeyCombo(keyCode: kVK_Delete, modifiers: co)
        case .flag: return KeyCombo(keyCode: kVK_ANSI_F, modifiers: co | controlKey)
        case .recordDisplay: return KeyCombo(keyCode: kVK_ANSI_3, modifiers: co)
        case .recordWindow: return KeyCombo(keyCode: kVK_ANSI_4, modifiers: co)
        case .recordArea: return KeyCombo(keyCode: kVK_ANSI_5, modifiers: co)
        case .toggleControls: return KeyCombo(keyCode: kVK_ANSI_Quote, modifiers: co)
        case .notes: return KeyCombo(keyCode: kVK_ANSI_Slash, modifiers: co)
        case .prompter: return KeyCombo(keyCode: kVK_ANSI_Period, modifiers: co)
        }
    }
}

/// A key plus Carbon modifier flags.
struct KeyCombo: Equatable, Hashable {
    var keyCode: Int
    var modifiers: Int

    init(keyCode: Int, modifiers: Int) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init?(event: NSEvent) {
        let f = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var m = 0
        if f.contains(.command) { m |= cmdKey }
        if f.contains(.option) { m |= optionKey }
        if f.contains(.control) { m |= controlKey }
        if f.contains(.shift) { m |= shiftKey }
        // Global shortcuts need at least ⌘, ⌥ or ⌃.
        guard m & (cmdKey | optionKey | controlKey) != 0 else { return nil }
        // Keys that can't be shown (modifier-only or unmapped keys) would save as a blank shortcut.
        guard KeyCombo.knownName(Int(event.keyCode)) != nil else { return nil }
        keyCode = Int(event.keyCode)
        modifiers = m
    }

    var display: String {
        var s = ""
        if modifiers & controlKey != 0 { s += "⌃" }
        if modifiers & optionKey != 0 { s += "⌥" }
        if modifiers & shiftKey != 0 { s += "⇧" }
        if modifiers & cmdKey != 0 { s += "⌘" }
        return s + KeyCombo.keyName(keyCode)
    }

    static func keyName(_ code: Int) -> String { knownName(code) ?? "?" }

    /// The key's label on the current keyboard layout (so "/" shows as "-" on a German keyboard), or nil.
    static func knownName(_ code: Int) -> String? {
        let special: [Int: String] = [
            kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
            kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_ANSI_KeypadEnter: "⌤",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        ]
        if let s = special[code] { return s }
        // Ask the current keyboard layout for the character.
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var dead: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var len = 0
        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
            return UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, 4, &len, &chars)
        }
        guard status == noErr, len > 0 else { return nil }
        let name = String(utf16CodeUnits: chars, count: len).uppercased()
        // Control characters and blanks can't be shown.
        guard !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              !name.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return name
    }
}

/// Registers the global shortcuts and routes them to their actions.
@MainActor
final class HotKeyCenter: ObservableObject {
    static let shared = HotKeyCenter()
    /// Shortcuts macOS refused because another app (Screen Studio, for one) already uses them.
    @Published private(set) var conflicts: Set<ShortcutAction> = []
    private var refs: [EventHotKeyRef] = []
    private var handlerInstalled = false
    private let signature = OSType(0x46524D43) // "FRMC"

    func registerAll() {
        if !handlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var id = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
                let index = Int(id.id)
                DispatchQueue.main.async {
                    guard index < ShortcutAction.allCases.count else { return }
                    HotKeyCenter.perform(ShortcutAction.allCases[index])
                }
                return noErr
            }, 1, &spec, nil, nil)
            handlerInstalled = true
        }
        for r in refs { UnregisterEventHotKey(r) }
        refs.removeAll()
        var failed: Set<ShortcutAction> = []
        for (i, action) in ShortcutAction.allCases.enumerated() {
            guard let combo = AppSettings.shared.shortcuts[action] else { continue }
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: signature, id: UInt32(i))
            if RegisterEventHotKey(UInt32(combo.keyCode), UInt32(combo.modifiers), id, GetApplicationEventTarget(), 0, &ref) == noErr,
               let ref {
                refs.append(ref)
            } else {
                failed.insert(action)
            }
        }
        conflicts = failed
    }

    /// Global shortcuts are paused while a new shortcut is being recorded in Settings.
    func suspend() {
        for r in refs { UnregisterEventHotKey(r) }
        refs.removeAll()
    }

    static func perform(_ action: ShortcutAction) {
        let rec = RecordingCoordinator.shared
        switch action {
        case .toggleRecording:
            if rec.isRecording { rec.stop() } else if rec.phase == .idle { RecordingToolbar.shared.toggle() }
        case .pauseResume: rec.togglePause()
        case .restart: rec.restart()
        case .flag: rec.addFlag()
        case .recordDisplay: RecordingToolbar.shared.start(.display, immediate: true)
        case .recordWindow: RecordingToolbar.shared.start(.window)
        case .recordArea: RecordingToolbar.shared.start(.area)
        case .toggleControls: rec.toggleControls()
        case .notes: SpeakerNotes.shared.toggle()
        case .prompter: SpeakerNotes.shared.toggleScrolling()
        }
    }
}
