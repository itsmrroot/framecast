import Foundation
import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Records key presses as data so shortcuts can be shown on screen (and typing detected) after recording.
/// macOS withholds keys typed into password fields (secure input), so passwords are never captured.
final class KeystrokeRecorder: @unchecked Sendable {
    private let clock: RecordingClock
    private var monitor: Any?
    private let lock = NSLock()
    private var events: [KeyEvent] = []

    init(clock: RecordingClock) {
        self.clock = clock
    }

    /// Global key monitoring needs Accessibility permission.
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    func start() {
        DispatchQueue.main.async { [self] in
            monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in self?.handle(e) }
        }
    }

    func stop() -> [KeyEvent] {
        let m = monitor
        monitor = nil
        if let m { DispatchQueue.main.async { NSEvent.removeMonitor(m) } }
        return lock.withLock { events }
    }

    private func handle(_ e: NSEvent) {
        guard !e.isARepeat, let t = clock.recordingTime(hostTime: RecordingClock.hostNow),
              let (label, shortcut) = Self.describe(e) else { return }
        lock.withLock { events.append(KeyEvent(t: t, label: label, isShortcut: shortcut)) }
    }

    private static let special: [Int: String] = [
        kVK_Return: "⏎", kVK_ANSI_KeypadEnter: "⌤", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_Escape: "esc", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    /// Display label and whether it counts as a shortcut (vs. plain typing).
    static func describe(_ e: NSEvent) -> (String, Bool)? {
        let flags = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var mods = ""
        if flags.contains(.control) { mods += "⌃" }
        if flags.contains(.option) { mods += "⌥" }
        if flags.contains(.shift) { mods += "⇧" }
        if flags.contains(.command) { mods += "⌘" }
        let combo = flags.contains(.command) || flags.contains(.control) || flags.contains(.option)
        let code = Int(e.keyCode)

        if code == kVK_Space {
            return combo ? (mods + "Space", true) : (" ", false)
        }
        if let symbol = special[code] {
            return (mods + symbol, true)
        }
        if combo {
            guard let base = e.charactersIgnoringModifiers, !base.isEmpty else { return nil }
            return (mods + base.uppercased(), true)
        }
        guard let typed = e.characters, !typed.isEmpty,
              typed.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return (typed, false)
    }
}
