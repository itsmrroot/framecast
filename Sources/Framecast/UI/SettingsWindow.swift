import SwiftUI
import AppKit

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, recording, editing, export, shortcuts, advanced
    var id: String { rawValue }
    var label: String {
        switch self {
        case .general: return "General"
        case .recording: return "Recording"
        case .editing: return "Editing"
        case .export: return "Quick export"
        case .shortcuts: return "Shortcuts"
        case .advanced: return "Advanced"
        }
    }
    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .recording: return "record.circle"
        case .editing: return "pencil.tip.crop.circle"
        case .export: return "square.and.arrow.up"
        case .shortcuts: return "command.circle"
        case .advanced: return "gearshape.2"
        }
    }
}

struct SettingsWindowView: View {
    @State private var tab: SettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(SettingsTab.allCases) { t in
                    Button { tab = t } label: {
                        VStack(spacing: 6) {
                            Image(systemName: t.icon).font(.system(size: 19))
                            Text(t.label).font(.system(size: 12, weight: .medium))
                        }
                        .frame(width: 92, height: 62)
                        .background(RoundedRectangle(cornerRadius: 10).fill(tab == t ? Theme.fill.opacity(0.08) : .clear))
                        .foregroundStyle(tab == t ? Theme.text : Theme.textDim)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 30)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity)
            Rectangle().fill(Theme.border).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch tab {
                    case .general: GeneralSettings()
                    case .recording: RecordingSettings()
                    case .editing: EditingSettings()
                    case .export: ExportSettingsPane()
                    case .shortcuts: ShortcutSettings()
                    case .advanced: AdvancedSettings()
                    }
                }
                .padding(.horizontal, 36)
                .padding(.vertical, 24)
            }
        }
        .frame(width: 760, height: 620)
        .background(Theme.bg)
    }
}

// MARK: Building blocks

private struct SettingRow<Control: View>: View {
    let title: String
    var detail: String? = nil
    @ViewBuilder let control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.text)
                if let detail {
                    Text(detail).font(.system(size: 12)).foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control
        }
        .padding(.vertical, 14)
    }
}

private struct SettingToggle: View {
    let title: String
    var detail: String? = nil
    @Binding var isOn: Bool
    var body: some View {
        SettingRow(title: title, detail: detail) {
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch).tint(Theme.accent)
        }
    }
}

private struct Choice<T: Hashable>: View {
    let options: [T]
    @Binding var selection: T
    let label: (T) -> String
    var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.self) { o in
                Button { selection = o } label: {
                    Text(label(o))
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.fill.opacity(selection == o ? 0.1 : 0.04)))
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(selection == o ? Theme.accent.opacity(0.8) : .clear))
                        .foregroundStyle(selection == o ? Theme.text : Theme.textDim)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct Separator: View {
    var body: some View { Rectangle().fill(Theme.border).frame(height: 1).padding(.vertical, 8) }
}

// MARK: Panes

private struct GeneralSettings: View {
    @ObservedObject private var app = AppSettings.shared
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        SettingRow(title: "Appearance", detail: "Light, dark, or follow your Mac. The recording toolbar always stays dark.") {
            Choice(options: AppAppearance.allCases, selection: $app.appearance) { $0.label }
        }
        SettingToggle(title: "Start Framecast at login", detail: "Open Framecast automatically when you log in, ready in the menu bar.",
                      isOn: Binding(get: { app.launchAtLogin }, set: { app.launchAtLogin = $0 }))
        SettingToggle(title: "Hide Dock icon",
                      detail: "Hide the Dock icon when no projects are open and nothing is recording. Framecast stays in the menu bar.",
                      isOn: $app.hideDockIcon)
        Separator()
        SettingToggle(title: "Check for updates automatically", detail: "Look for a new version each time Framecast opens.",
                      isOn: $updater.autoCheck)
        SettingRow(title: "Version \(Updater.currentVersion)", detail: updateStatus) {
            Button("Check Now") { Task { await updater.check(manual: true) } }.buttonStyle(SecondaryButtonStyle())
        }
        Separator()
        SettingRow(title: "Reset preferences", detail: "Restore every setting and shortcut to its default. Your recordings aren't touched.") {
            Button("Reset…") {
                let alert = NSAlert()
                alert.messageText = "Reset all preferences?"
                alert.informativeText = "Framecast will quit. Open it again to start with the default settings."
                alert.addButton(withTitle: "Reset and Quit")
                alert.addButton(withTitle: "Cancel")
                if alert.runModal() == .alertFirstButtonReturn {
                    app.resetAll()
                    NSApp.terminate(nil)
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .foregroundStyle(.red)
        }
    }

    private var updateStatus: String {
        if let r = updater.release { return "Version \(r.version) is available." }
        if updater.phase == .upToDate { return "You have the latest version." }
        if updater.phase == .checking { return "Checking…" }
        return "Framecast updates itself from GitHub releases."
    }
}

private struct RecordingSettings: View {
    @ObservedObject private var app = AppSettings.shared
    @ObservedObject private var rec = RecorderSettings.shared
    @ObservedObject private var library = ProjectLibrary.shared

    var body: some View {
        SettingRow(title: "Save new projects to", detail: (library.root.path as NSString).abbreviatingWithTildeInPath) {
            Button("Change Folder…") { library.changeFolder() }.buttonStyle(SecondaryButtonStyle())
        }
        SettingToggle(title: "Highlight recorded area during recording",
                      detail: "Dims the parts of the screen that aren't being recorded.", isOn: $app.highlightRecordedArea)
        SettingToggle(title: "Create zooms automatically",
                      detail: "Adds zooms around your clicks in every new recording.", isOn: $rec.autoZoom)
        SettingToggle(title: "Show recording widget",
                      detail: "Shows the floating timer with stop, pause, restart and cancel while recording.", isOn: $app.showRecordingWidget)
        SettingToggle(title: "Show camera preview",
                      detail: "Shows a floating live view of your camera so you can see yourself. It isn't recorded on screen.",
                      isOn: $app.showCameraPreview)
        SettingRow(title: "Maximum camera resolution",
                   detail: "Higher resolutions look sharper but use more processing power while recording.") {
            Choice(options: [720, 1080, 2160], selection: $app.cameraResolution) { $0 == 2160 ? "4K" : "\($0)p" }
        }
        SettingRow(title: "Countdown", detail: "Seconds to get ready before recording starts.") {
            Choice(options: [0, 3, 5], selection: $rec.countdown) { $0 == 0 ? "Off" : "\($0)s" }
        }
        SettingRow(title: "Frame rate", detail: "60 fps looks smoother; 30 fps makes smaller files.") {
            Choice(options: [30, 60], selection: $rec.fps) { "\($0) fps" }
        }
        SettingToggle(title: "Hide desktop icons", detail: "Keeps desktop files out of display recordings.", isOn: $rec.hideDesktopIcons)
    }
}

private struct EditingSettings: View {
    @ObservedObject private var app = AppSettings.shared
    @ObservedObject private var presets = PresetStore.shared

    var body: some View {
        SettingToggle(title: "Use last project settings as default for new recordings",
                      detail: "New recordings get the style of the last project you edited.",
                      isOn: $app.useLastProjectStyle)
        SettingToggle(title: "Use autosave",
                      detail: "Saves your edits automatically as you work. When off, projects are saved when you close them or press ⌘S.",
                      isOn: $app.autosave)
        Separator()
        Text("STYLE PRESETS").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.textDim).padding(.top, 6)
        if presets.presets.isEmpty {
            Text("Save a preset from the Presets menu in the editor.").font(.system(size: 12)).foregroundStyle(Theme.textDim).padding(.vertical, 10)
        }
        ForEach(presets.presets) { p in
            SettingRow(title: p.name) {
                Button("Delete") { presets.remove(p) }.buttonStyle(SecondaryButtonStyle())
            }
        }
        SettingRow(title: "Default style", detail: "The style new recordings start with.") {
            Button("Reset to Framecast Default") { presets.setDefault(Style()) }.buttonStyle(SecondaryButtonStyle())
        }
    }
}

private struct ExportSettingsPane: View {
    @ObservedObject private var app = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Quick export settings", systemImage: "square.and.arrow.up").font(.system(size: 14, weight: .medium))
            Text("Used as the defaults in the export window and by the quick export widget.")
                .font(.system(size: 12)).foregroundStyle(Theme.textDim)
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 40) {
                    group("Format", icon: "film") {
                        Choice(options: ["mp4", "gif"], selection: $app.exportFormat) { $0.uppercased() }
                    }
                    group("Frame rate", icon: "speedometer") {
                        Choice(options: [24, 30, 60], selection: $app.exportFPS) { "\($0) FPS" }
                    }
                }
                group("Resolution", icon: "rectangle.dashed") {
                    Choice(options: ExportResolution.allCases.map(\.rawValue), selection: $app.exportResolution) {
                        ExportResolution(rawValue: $0)?.label ?? ""
                    }
                }
                group("Compression", icon: "scribble") {
                    Choice(options: ExportQuality.allCases.map(\.rawValue), selection: $app.exportQuality) {
                        ExportQuality(rawValue: $0)?.label ?? ""
                    }
                    Text(ExportQuality(rawValue: app.exportQuality)?.detail ?? "")
                        .font(.system(size: 12)).foregroundStyle(Theme.textDim)
                }
                group("Codec", icon: "cpu") {
                    Choice(options: ExportCodec.allCases.map(\.rawValue), selection: $app.exportCodec) {
                        $0 == "h264" ? "H.264 (compatible)" : "HEVC (smaller)"
                    }
                }
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.fill.opacity(0.03)))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.border))
        }
        .padding(.bottom, 8)
        SettingToggle(title: "Show quick export widget after recording",
                      detail: "After recording, a small widget lets you export and copy the video right away. When off, the editor opens.",
                      isOn: $app.showQuickExportWidget)
    }

    private func group<C: View>(_ title: String, icon: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.system(size: 13, weight: .medium))
            content()
        }
    }
}

private struct ShortcutSettings: View {
    @ObservedObject private var app = AppSettings.shared
    @State private var section = 0

    var body: some View {
        HStack {
            Spacer()
            Choice(options: [0, 1], selection: $section) { $0 == 0 ? "Recording" : "Editing" }
            Spacer()
        }
        .padding(.bottom, 10)
        if section == 0 {
            ForEach(ShortcutAction.allCases) { a in
                HStack(alignment: .center, spacing: 16) {
                    Image(systemName: a.icon).font(.system(size: 15)).frame(width: 22).foregroundStyle(Theme.textDim)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(a.title).font(.system(size: 14, weight: .medium))
                        if let d = a.detail { Text(d).font(.system(size: 12)).foregroundStyle(Theme.textDim) }
                    }
                    Spacer()
                    Button { app.setShortcut(nil, for: a) } label: { Image(systemName: "trash") }
                        .buttonStyle(.plain).foregroundStyle(Theme.textDim).help("Remove shortcut")
                    ShortcutRecorder(combo: app.shortcuts[a]) { app.setShortcut($0, for: a) }
                }
                .padding(.vertical, 10)
            }
            HStack {
                Spacer()
                Button("Restore Default Shortcuts") { app.resetShortcuts() }.buttonStyle(SecondaryButtonStyle())
            }
            .padding(.top, 10)
        } else {
            ForEach(EditorShortcut.all, id: \.keys) { s in
                HStack(spacing: 16) {
                    Image(systemName: s.icon).font(.system(size: 15)).frame(width: 22).foregroundStyle(Theme.textDim)
                    Text(s.title).font(.system(size: 14, weight: .medium))
                    Spacer()
                    Text(s.keys)
                        .font(.system(size: 14, weight: .medium))
                        .frame(minWidth: 120).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.fill.opacity(0.05)))
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.border))
                }
                .padding(.vertical, 6)
            }
        }
    }
}

/// Editor keyboard shortcuts (fixed), listed in Settings and the editor's shortcut popover.
struct EditorShortcut {
    let icon: String
    let title: String
    let keys: String

    static let all: [EditorShortcut] = [
        EditorShortcut(icon: "playpause", title: "Play / pause", keys: "Space"),
        EditorShortcut(icon: "scissors", title: "Cut clip at current time", keys: "C  or  S"),
        EditorShortcut(icon: "scissors.badge.ellipsis", title: "Remove slice before current time", keys: "X"),
        EditorShortcut(icon: "play", title: "Play or increase speed", keys: "L"),
        EditorShortcut(icon: "play.fill", title: "Play backward or increase speed", keys: "J"),
        EditorShortcut(icon: "stop", title: "Stop and reset playback speed", keys: "K"),
        EditorShortcut(icon: "plus.magnifyingglass", title: "Add zoom at playhead", keys: "Z"),
        EditorShortcut(icon: "eye.slash", title: "Add blur at playhead", keys: "B"),
        EditorShortcut(icon: "textformat", title: "Add title at playhead", keys: "T"),
        EditorShortcut(icon: "delete.left", title: "Delete selection", keys: "⌫"),
        EditorShortcut(icon: "arrow.left.and.right", title: "Step one frame", keys: "←  →"),
        EditorShortcut(icon: "arrow.uturn.backward", title: "Undo / redo", keys: "⌘Z  ⇧⌘Z"),
        EditorShortcut(icon: "square.and.arrow.down", title: "Save project", keys: "⌘S"),
        EditorShortcut(icon: "square.and.arrow.up", title: "Export", keys: "⌘E"),
    ]
}

/// Click, then press a key combination (with ⌘, ⌥ or ⌃) to set a global shortcut. Esc cancels.
private struct ShortcutRecorder: View {
    let combo: KeyCombo?
    let onChange: (KeyCombo) -> Void
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? "Press keys…" : (combo?.display ?? "Not set"))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(recording ? Theme.accent : (combo == nil ? Theme.textFaint : Theme.text))
                .frame(minWidth: 150).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 9).fill(Theme.fill.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(recording ? Theme.accent : Theme.border))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if e.keyCode == 53 { stop(); return nil } // Esc
            if let c = KeyCombo(event: e) {
                onChange(c)
                stop()
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

private struct AdvancedSettings: View {
    @ObservedObject private var app = AppSettings.shared

    var body: some View {
        SettingToggle(title: "Disable hardware accelerated video encoding",
                      detail: "May help with export problems on some Intel Macs, but exports take longer and use more CPU.",
                      isOn: $app.disableHardwareAcceleration)
        Separator()
        SettingRow(title: "Permissions", detail: "Open System Settings to review Screen Recording, Camera, Microphone and Accessibility access.") {
            Button("Open Privacy Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")!)
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        SettingRow(title: "Diagnostics", detail: "Copy your Mac model, macOS version and Framecast version, to paste into a bug report.") {
            Button("Copy Diagnostics") {
                let info = ProcessInfo.processInfo
                var size = 0
                sysctlbyname("hw.model", nil, &size, nil, 0)
                var model = [CChar](repeating: 0, count: max(size, 1))
                sysctlbyname("hw.model", &model, &size, nil, 0)
                let text = """
                Framecast \(Updater.currentVersion) (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"))
                macOS \(info.operatingSystemVersionString)
                Mac \(String(cString: model)) · \(info.processorCount) cores · \(info.physicalMemory / 1_073_741_824) GB
                """
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        SettingRow(title: "Report a problem", detail: "Open an issue on GitHub.") {
            Button("Open GitHub Issues") {
                NSWorkspace.shared.open(URL(string: "https://github.com/\(Updater.repo)/issues")!)
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }
}
