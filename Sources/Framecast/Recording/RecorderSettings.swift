import Foundation
import AppKit
import ScreenCaptureKit

enum CaptureKind: String, CaseIterable, Identifiable {
    case display, window, area, device
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .display: return "display"
        case .window: return "macwindow"
        case .area: return "rectangle.dashed"
        case .device: return "iphone"
        }
    }
    /// Sources offered on the home screen (devices are picked from the recording toolbar).
    static let homeCases: [CaptureKind] = [.display, .window, .area]
}

@MainActor
final class RecorderSettings: ObservableObject {
    static let shared = RecorderSettings()
    private let d = UserDefaults.standard

    @Published var kind: CaptureKind { didSet { d.set(kind.rawValue, forKey: "rec.kind") } }
    @Published var displayID: UInt32 { didSet { d.set(Int(displayID), forKey: "rec.display") } }
    @Published var windowID: UInt32 = 0
    @Published var windowTitle: String = ""
    @Published var areaRect: CGRect? {
        didSet {
            if let r = areaRect { d.set(NSStringFromRect(r), forKey: "rec.area") } else { d.removeObject(forKey: "rec.area") }
        }
    }
    @Published var cameraEnabled: Bool { didSet { d.set(cameraEnabled, forKey: "rec.camera") } }
    @Published var cameraID: String { didSet { d.set(cameraID, forKey: "rec.cameraID") } }
    @Published var micEnabled: Bool { didSet { d.set(micEnabled, forKey: "rec.mic") } }
    @Published var micID: String { didSet { d.set(micID, forKey: "rec.micID") } }
    @Published var systemAudio: Bool { didSet { d.set(systemAudio, forKey: "rec.system") } }
    @Published var countdown: Int { didSet { d.set(countdown, forKey: "rec.countdown") } }
    @Published var hideDesktopIcons: Bool { didSet { d.set(hideDesktopIcons, forKey: "rec.hideDesktop") } }
    @Published var fps: Int { didSet { d.set(fps, forKey: "rec.fps") } }
    @Published var autoZoom: Bool { didSet { d.set(autoZoom, forKey: "rec.autoZoom") } }
    @Published var recordKeystrokes: Bool { didSet { d.set(recordKeystrokes, forKey: "rec.keys") } }
    @Published var deviceID: String { didSet { d.set(deviceID, forKey: "rec.deviceID") } }
    /// Name and note for the next recording (cleared once it's saved).
    @Published var nextName = ""
    @Published var nextNote = ""
    /// System audio: everything, only some apps (bundle ids), or nothing (`systemAudio` off).
    @Published var audioFromSelectedApps: Bool { didSet { d.set(audioFromSelectedApps, forKey: "rec.audioSelected") } }
    @Published var audioApps: [String] { didSet { d.set(audioApps, forKey: "rec.audioApps") } }

    private init() {
        d.register(defaults: [
            "rec.kind": CaptureKind.display.rawValue,
            "rec.countdown": 3,
            "rec.system": true,
            "rec.fps": 60,
            "rec.autoZoom": true,
        ])
        kind = CaptureKind(rawValue: d.string(forKey: "rec.kind") ?? "") ?? .display
        displayID = UInt32(d.integer(forKey: "rec.display"))
        if let s = d.string(forKey: "rec.area") { areaRect = NSRectFromString(s) } else { areaRect = nil }
        cameraEnabled = d.bool(forKey: "rec.camera")
        cameraID = d.string(forKey: "rec.cameraID") ?? ""
        micEnabled = d.bool(forKey: "rec.mic")
        micID = d.string(forKey: "rec.micID") ?? ""
        systemAudio = d.bool(forKey: "rec.system")
        countdown = d.integer(forKey: "rec.countdown")
        hideDesktopIcons = d.bool(forKey: "rec.hideDesktop")
        fps = d.integer(forKey: "rec.fps")
        autoZoom = d.bool(forKey: "rec.autoZoom")
        recordKeystrokes = d.bool(forKey: "rec.keys")
        deviceID = d.string(forKey: "rec.deviceID") ?? ""
        audioFromSelectedApps = d.bool(forKey: "rec.audioSelected")
        audioApps = d.stringArray(forKey: "rec.audioApps") ?? []
    }
}

/// Available displays, windows, cameras and microphones.
@MainActor
final class SourceCatalog: ObservableObject {
    static let shared = SourceCatalog()

    @Published private(set) var displays: [SCDisplay] = []
    @Published private(set) var windows: [SCWindow] = []
    @Published private(set) var cameras: [DeviceCatalog.Device] = []
    @Published private(set) var microphones: [DeviceCatalog.Device] = []
    /// Connected iPhones and iPads.
    @Published private(set) var devices: [DeviceCatalog.Device] = []
    @Published private(set) var hasScreenPermission = CGPreflightScreenCaptureAccess()

    func refresh() async {
        cameras = DeviceCatalog.cameras()
        microphones = DeviceCatalog.microphones()
        devices = DeviceCatalog.iosDevices()
        let settings = RecorderSettings.shared
        if settings.cameraID.isEmpty || !cameras.contains(where: { $0.id == settings.cameraID }) {
            settings.cameraID = cameras.first?.id ?? ""
        }
        if settings.micID.isEmpty || !microphones.contains(where: { $0.id == settings.micID }) {
            settings.micID = microphones.first?.id ?? ""
        }
        hasScreenPermission = CGPreflightScreenCaptureAccess()
        guard hasScreenPermission else { return }
        do {
            // Off-screen windows too (other Spaces, behind full-screen apps), so every real window can be picked.
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            displays = content.displays
            let pid = ProcessInfo.processInfo.processIdentifier
            windows = content.windows.filter { w in
                w.windowLayer == 0 && w.frame.width > 120 && w.frame.height > 80
                    && w.owningApplication?.processID != pid
                    && w.owningApplication != nil
                    && !(w.owningApplication?.applicationName.isEmpty ?? true)
                    // Off-screen ones only when titled; untitled hidden windows are usually app internals.
                    && (w.isOnScreen || !(w.title ?? "").isEmpty)
            }
            .sorted { a, b in
                if a.isOnScreen != b.isOnScreen { return a.isOnScreen }
                let an = a.owningApplication?.applicationName ?? "", bn = b.owningApplication?.applicationName ?? ""
                return an.localizedCaseInsensitiveCompare(bn) == .orderedAscending
            }
            if !displays.contains(where: { $0.displayID == settings.displayID }) {
                settings.displayID = displays.first?.displayID ?? CGMainDisplayID()
            }
        } catch {
            NSLog("Framecast: failed to load shareable content: \(error)")
        }
    }

    static func name(for display: SCDisplay) -> String {
        let screen = NSScreen.screens.first { $0.displayID == display.displayID }
        let name = screen?.localizedName ?? "Display \(display.displayID)"
        return "\(name) — \(display.width)×\(display.height)"
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        screens.first { $0.displayID == displayID }
    }
}
