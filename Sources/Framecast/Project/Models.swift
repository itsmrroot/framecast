import Foundation
import CoreGraphics

// MARK: - Cursor data (recorded separately from the video so it can be restyled later)

/// Positions are normalised to the captured area: (0,0) top-left, (1,1) bottom-right.
struct CursorSample: Codable { var t: Double; var x: Double; var y: Double }
struct ClickEvent: Codable { var t: Double; var x: Double; var y: Double; var button: Int }
struct CursorShapeChange: Codable { var t: Double; var id: String }

struct CursorShapeInfo: Codable {
    var id: String
    /// Hotspot and size in points, top-left origin.
    var hotX: Double
    var hotY: Double
    var width: Double
    var height: Double
    var isArrow: Bool
}

struct CursorTrack: Codable {
    var samples: [CursorSample] = []
    var clicks: [ClickEvent] = []
    var shapes: [CursorShapeChange] = []
    var shapeInfo: [String: CursorShapeInfo] = [:]

    var isEmpty: Bool { samples.isEmpty }
}

// MARK: - Keystrokes

/// A key press recorded during capture. `label` is display-ready, e.g. "⌘⇧S", "⏎" or "a".
struct KeyEvent: Codable, Equatable {
    var t: Double
    var label: String
    /// True for shortcuts (⌘, ⌃ or ⌥ held) and special keys like ⏎ or ⌫; false for plain typing.
    var isShortcut: Bool
}

// MARK: - Recording info

struct RecordingInfo: Codable {
    var duration: Double
    /// Size of the captured area in points (cursor coordinates are relative to this).
    var pointWidth: Double
    var pointHeight: Double
    var pixelWidth: Int
    var pixelHeight: Int
    var hasWebcam: Bool
    var hasMic: Bool
    var hasSystemAudio: Bool
    var sourceName: String
    var hasCursorData: Bool
}

// MARK: - Timeline edits

/// A kept piece of the source recording. Gaps between clips are cuts.
struct Clip: Codable, Identifiable, Equatable {
    var id = UUID()
    var start: Double
    var end: Double
    var speed: Double = 1
    var duration: Double { end - start }
}

enum ZoomMode: String, Codable, CaseIterable, Identifiable {
    case followCursor, fixed
    var id: String { rawValue }
    var label: String { self == .followCursor ? "Follow cursor" : "Fixed point" }
}

struct ZoomSegment: Codable, Identifiable, Equatable {
    var id = UUID()
    var start: Double
    var end: Double
    var scale: Double = 2
    var mode: ZoomMode = .followCursor
    /// Fixed focus, normalised top-left.
    var focusX: Double = 0.5
    var focusY: Double = 0.5
    var isAuto = false
    var duration: Double { end - start }
}

enum EffectKind: String, Codable, CaseIterable, Identifiable {
    case blur, spotlight, text, hideCursor, cameraFull, cameraHidden
    var id: String { rawValue }
    var label: String {
        switch self {
        case .blur: return "Blur"
        case .spotlight: return "Spotlight"
        case .text: return "Text"
        case .hideCursor: return "Hide cursor"
        case .cameraFull: return "Camera full screen"
        case .cameraHidden: return "Hide camera"
        }
    }
    var icon: String {
        switch self {
        case .blur: return "eye.slash"
        case .spotlight: return "flashlight.on.fill"
        case .text: return "textformat"
        case .hideCursor: return "cursorarrow.slash"
        case .cameraFull: return "person.crop.rectangle"
        case .cameraHidden: return "video.slash"
        }
    }
    /// Effects that apply to an area of the recording.
    var hasRegion: Bool { self == .blur || self == .spotlight }
    var needsCamera: Bool { self == .cameraFull || self == .cameraHidden }
}

enum TextPlacement: String, Codable, CaseIterable, Identifiable {
    case top, center, bottom
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// A timed overlay: blur/spotlight an area, show a title, hide the cursor, or change the camera layout.
struct EffectSegment: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: EffectKind
    var start: Double
    var end: Double
    /// Area of the recording, normalised top-left (blur and spotlight).
    var x: Double = 0.3
    var y: Double = 0.3
    var w: Double = 0.4
    var h: Double = 0.25
    /// Blur strength or spotlight dimming, 0...1.
    var intensity: Double = 0.6
    var pixelate = false
    var text = "Add your title"
    var placement: TextPlacement = .center
    var textSize: Double = 1
    var duration: Double { end - start }
    var region: CGRect { CGRect(x: x, y: y, width: w, height: h) }

    init(kind: EffectKind, start: Double, end: Double) {
        self.kind = kind
        self.start = start
        self.end = end
        if kind == .spotlight { intensity = 0.55 }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = EffectSegment(kind: .blur, start: 0, end: 0)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decode(EffectKind.self, forKey: .kind)
        start = try c.decode(Double.self, forKey: .start)
        end = try c.decode(Double.self, forKey: .end)
        x = try c.decodeIfPresent(Double.self, forKey: .x) ?? d.x
        y = try c.decodeIfPresent(Double.self, forKey: .y) ?? d.y
        w = try c.decodeIfPresent(Double.self, forKey: .w) ?? d.w
        h = try c.decodeIfPresent(Double.self, forKey: .h) ?? d.h
        intensity = try c.decodeIfPresent(Double.self, forKey: .intensity) ?? d.intensity
        pixelate = try c.decodeIfPresent(Bool.self, forKey: .pixelate) ?? d.pixelate
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? d.text
        placement = try c.decodeIfPresent(TextPlacement.self, forKey: .placement) ?? d.placement
        textSize = try c.decodeIfPresent(Double.self, forKey: .textSize) ?? d.textSize
    }
}

/// One caption line, in source time.
struct CaptionCue: Codable, Identifiable, Equatable {
    var id = UUID()
    var start: Double
    var end: Double
    var text: String
}

// MARK: - Style

struct RGBA: Codable, Equatable, Hashable {
    var r: Double, g: Double, b: Double, a: Double = 1
    var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
    init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) { self.r = r; self.g = g; self.b = b; self.a = a }
    init(hex: UInt32) {
        r = Double((hex >> 16) & 0xff) / 255
        g = Double((hex >> 8) & 0xff) / 255
        b = Double(hex & 0xff) / 255
        a = 1
    }
}

enum BackgroundKind: String, Codable, CaseIterable, Identifiable {
    case wallpaper, gradient, solid, image
    var id: String { rawValue }
    var label: String {
        switch self {
        case .wallpaper: return "Wallpaper"
        case .gradient: return "Gradient"
        case .solid: return "Color"
        case .image: return "Image"
        }
    }
}

struct BackgroundStyle: Codable, Equatable {
    var kind: BackgroundKind = .wallpaper
    var gradientIndex: Int = 0
    var solid = RGBA(hex: 0x1E1E24)
    var wallpaperPath: String? = nil
    var imagePath: String? = nil
    var blur: Double = 0
}

enum AspectRatio: String, Codable, CaseIterable, Identifiable {
    case auto, wide, classic, fiveFour, square, fourFive, vertical, portrait
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: return "Auto"
        case .wide: return "16:9 Wide"
        case .classic: return "4:3 Classic"
        case .fiveFour: return "5:4"
        case .fourFive: return "4:5 Social"
        case .square: return "1:1 Square"
        case .vertical: return "9:16 Vertical"
        case .portrait: return "3:4 Portrait"
        }
    }
    var shortLabel: String {
        switch self {
        case .auto: return "Auto"
        case .wide: return "16:9"
        case .classic: return "4:3"
        case .fiveFour: return "5:4"
        case .square: return "1:1"
        case .fourFive: return "4:5"
        case .vertical: return "9:16"
        case .portrait: return "3:4"
        }
    }
    func value(source: CGSize, padding: Double) -> CGFloat {
        switch self {
        case .auto:
            // Keep the source aspect, accounting for equal padding on all sides.
            guard source.width > 0, source.height > 0 else { return 16.0 / 9.0 }
            let a = source.width / source.height
            let p = CGFloat(clamp(padding, 0, 0.45))
            // Padding is p * min(W, H) on every side; pick the canvas so the screen fits exactly.
            if a >= 1 {
                return a * (1 - 2 * p) + 2 * p
            } else {
                return 1 / ((1 - 2 * p) / a + 2 * p)
            }
        case .wide: return 16.0 / 9.0
        case .classic: return 4.0 / 3.0
        case .fiveFour: return 5.0 / 4.0
        case .square: return 1
        case .fourFive: return 4.0 / 5.0
        case .vertical: return 9.0 / 16.0
        case .portrait: return 3.0 / 4.0
        }
    }
}

enum ClickEffect: String, Codable, CaseIterable, Identifiable {
    case none, ripple, ring
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum CameraShape: String, Codable, CaseIterable, Identifiable {
    case circle, rounded, square
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum CameraCorner: String, Codable, CaseIterable, Identifiable {
    case topLeft, topRight, bottomLeft, bottomRight
    var id: String { rawValue }
}

enum CameraBackground: String, Codable, CaseIterable, Identifiable {
    case none, blur, remove
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "Original"
        case .blur: return "Blur"
        case .remove: return "Remove"
        }
    }
}

enum KeystrokeMode: String, Codable, CaseIterable, Identifiable {
    case off, shortcuts, all
    var id: String { rawValue }
    var label: String {
        switch self {
        case .off: return "Off"
        case .shortcuts: return "Shortcuts"
        case .all: return "All keys"
        }
    }
}

struct CameraStyle: Codable, Equatable {
    var visible = true
    var shape: CameraShape = .circle
    var size: Double = 0.24
    var corner: CameraCorner = .bottomRight
    var mirror = true
    var shrinkOnZoom = true
    var border = true
    var background: CameraBackground = .none
}

struct Style: Codable, Equatable {
    var background = BackgroundStyle()
    var aspect: AspectRatio = .auto
    var padding: Double = 0.07
    var cornerRadius: Double = 16
    var shadow: Double = 0.55
    var shadowBlur: Double = 40

    var showCursor = true
    var cursorSize: Double = 1.6
    var cursorSmoothing: Double = 0.55
    var highResCursor = true
    var hideIdleCursor = false
    var cursorMotionBlur = true
    var clickEffect: ClickEffect = .ripple

    var zoomTransition: Double = 0.9
    var defaultZoomScale: Double = 2.0

    var camera = CameraStyle()

    var keystrokes: KeystrokeMode = .shortcuts
    var keystrokeSize: Double = 1

    var showCaptions = true
    var captionSize: Double = 1

    var systemVolume: Double = 1
    var micVolume: Double = 1

    static let `default` = Style()
}

// MARK: - Project document

struct ProjectDocument: Codable {
    var version = 1
    var name: String
    var createdAt: Date
    var info: RecordingInfo
    var clips: [Clip]
    var zooms: [ZoomSegment]
    var style: Style
    var effects: [EffectSegment] = []
    var captions: [CaptionCue] = []

    init(name: String, createdAt: Date, info: RecordingInfo, clips: [Clip], zooms: [ZoomSegment], style: Style,
         effects: [EffectSegment] = [], captions: [CaptionCue] = []) {
        self.name = name
        self.createdAt = createdAt
        self.info = info
        self.clips = clips
        self.zooms = zooms
        self.style = style
        self.effects = effects
        self.captions = captions
    }

    // Older projects don't have effects or captions.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        name = try c.decode(String.self, forKey: .name)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        info = try c.decode(RecordingInfo.self, forKey: .info)
        clips = try c.decode([Clip].self, forKey: .clips)
        zooms = try c.decode([ZoomSegment].self, forKey: .zooms)
        style = try c.decode(Style.self, forKey: .style)
        effects = try c.decodeIfPresent([EffectSegment].self, forKey: .effects) ?? []
        captions = try c.decodeIfPresent([CaptionCue].self, forKey: .captions) ?? []
    }
}

enum ProjectFiles {
    static let document = "project.json"
    static let screen = "screen.mov"
    static let webcam = "webcam.mov"
    static let mic = "mic.m4a"
    static let cursor = "cursor.json"
    static let cursors = "cursors"
    static let thumbnail = "thumbnail.jpg"
    static let keys = "keys.json"
}
