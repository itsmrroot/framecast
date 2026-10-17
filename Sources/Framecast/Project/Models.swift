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
    /// Cut straight in and out, without easing.
    var instant = false
    var duration: Double { end - start }

    init(id: UUID = UUID(), start: Double, end: Double, scale: Double = 2, mode: ZoomMode = .followCursor,
         focusX: Double = 0.5, focusY: Double = 0.5, isAuto: Bool = false, instant: Bool = false) {
        self.id = id; self.start = start; self.end = end; self.scale = scale; self.mode = mode
        self.focusX = focusX; self.focusY = focusY; self.isAuto = isAuto; self.instant = instant
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        start = try c.decode(Double.self, forKey: .start)
        end = try c.decode(Double.self, forKey: .end)
        scale = try c.decodeIfPresent(Double.self, forKey: .scale) ?? 2
        mode = (try? c.decodeIfPresent(ZoomMode.self, forKey: .mode)) ?? .followCursor
        focusX = try c.decodeIfPresent(Double.self, forKey: .focusX) ?? 0.5
        focusY = try c.decodeIfPresent(Double.self, forKey: .focusY) ?? 0.5
        isAuto = try c.decodeIfPresent(Bool.self, forKey: .isAuto) ?? false
        instant = try c.decodeIfPresent(Bool.self, forKey: .instant) ?? false
    }
}

enum EffectKind: String, Codable, CaseIterable, Identifiable {
    case blur, spotlight, text, image, annotation, hideCursor, cameraFull, cameraHidden, cameraMove
    var id: String { rawValue }
    var label: String {
        switch self {
        case .blur: return "Blur"
        case .spotlight: return "Spotlight"
        case .text: return "Text"
        case .image: return "Image"
        case .annotation: return "Arrow or shape"
        case .cameraMove: return "Move camera"
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
        case .image: return "photo"
        case .annotation: return "arrow.up.right"
        case .cameraMove: return "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left"
        case .hideCursor: return "cursorarrow.slash"
        case .cameraFull: return "person.crop.rectangle"
        case .cameraHidden: return "video.slash"
        }
    }
    /// Effects that apply to an area of the recording.
    var hasRegion: Bool { self == .blur || self == .spotlight || self == .annotation }
    var needsCamera: Bool { self == .cameraFull || self == .cameraHidden || self == .cameraMove }
}

enum AnnotationShape: String, Codable, CaseIterable, Identifiable {
    case arrow, box, ellipse
    var id: String { rawValue }
    var label: String {
        switch self {
        case .arrow: return "Arrow"
        case .box: return "Box"
        case .ellipse: return "Circle"
        }
    }
    var icon: String {
        switch self {
        case .arrow: return "arrow.up.right"
        case .box: return "rectangle"
        case .ellipse: return "circle"
        }
    }
}

/// Which way an arrow points across its area.
enum ArrowDirection: String, Codable, CaseIterable, Identifiable {
    case downRight, downLeft, upRight, upLeft, right, left, down, up
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .downRight: return "arrow.down.right"
        case .downLeft: return "arrow.down.left"
        case .upRight: return "arrow.up.right"
        case .upLeft: return "arrow.up.left"
        case .right: return "arrow.right"
        case .left: return "arrow.left"
        case .down: return "arrow.down"
        case .up: return "arrow.up"
        }
    }
    /// Tail and tip in the unit square (top-left origin).
    var points: (CGPoint, CGPoint) {
        switch self {
        case .downRight: return (CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1))
        case .downLeft: return (CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1))
        case .upRight: return (CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 0))
        case .upLeft: return (CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 0))
        case .right: return (CGPoint(x: 0, y: 0.5), CGPoint(x: 1, y: 0.5))
        case .left: return (CGPoint(x: 1, y: 0.5), CGPoint(x: 0, y: 0.5))
        case .down: return (CGPoint(x: 0.5, y: 0), CGPoint(x: 0.5, y: 1))
        case .up: return (CGPoint(x: 0.5, y: 1), CGPoint(x: 0.5, y: 0))
        }
    }
}

enum TextPlacement: String, Codable, CaseIterable, Identifiable {
    case top, center, bottom, custom
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

// MARK: - Title styling

/// Apple's system typefaces (and widths of SF Pro), so titles look at home on a Mac.
enum TitleFont: String, Codable, CaseIterable, Identifiable {
    case system, rounded, serif, mono, condensed, expanded
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "SF Pro"
        case .rounded: return "Rounded"
        case .serif: return "New York"
        case .mono: return "SF Mono"
        case .condensed: return "Condensed"
        case .expanded: return "Expanded"
        }
    }
}

enum TitleWeight: String, Codable, CaseIterable, Identifiable {
    case regular, medium, semibold, bold, heavy
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// What sits behind the title text.
enum TitleCard: String, Codable, CaseIterable, Identifiable {
    case light, dark, glass, color, none
    var id: String { rawValue }
    var label: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .glass: return "Glass"
        case .color: return "Color"
        case .none: return "None"
        }
    }
}

enum TitleAlign: String, Codable, CaseIterable, Identifiable {
    case left, center, right
    var id: String { rawValue }
    var icon: String { "text.align\(rawValue)" }
}

struct TitleStyle: Codable, Equatable, Hashable {
    var font: TitleFont = .system
    var weight: TitleWeight = .bold
    var card: TitleCard = .light
    /// nil = automatic (dark on the light card, white on the others).
    var textColor: RGBA? = nil
    var cardColor = RGBA(hex: 0x0A84FF)
    var align: TitleAlign = .center

    init() {}

    init(font: TitleFont, weight: TitleWeight, card: TitleCard, textColor: RGBA? = nil, cardColor: RGBA = RGBA(hex: 0x0A84FF)) {
        self.font = font; self.weight = weight; self.card = card; self.textColor = textColor; self.cardColor = cardColor
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        font = (try? c.decodeIfPresent(TitleFont.self, forKey: .font)) ?? .system
        weight = (try? c.decodeIfPresent(TitleWeight.self, forKey: .weight)) ?? .bold
        card = (try? c.decodeIfPresent(TitleCard.self, forKey: .card)) ?? .light
        textColor = (try? c.decodeIfPresent(RGBA.self, forKey: .textColor)) ?? nil
        cardColor = (try? c.decodeIfPresent(RGBA.self, forKey: .cardColor)) ?? RGBA(hex: 0x0A84FF)
        align = (try? c.decodeIfPresent(TitleAlign.self, forKey: .align)) ?? .center
    }

    /// The text colour actually used.
    var resolvedTextColor: RGBA {
        textColor ?? (card == .light ? RGBA(hex: 0x1D1D1F) : RGBA(hex: 0xFFFFFF))
    }

    /// Apple's system colours (dark-mode variants), for text and colour cards.
    static let palette: [RGBA] = [0xFFFFFF, 0x1D1D1F, 0x0A84FF, 0x5E5CE6, 0xBF5AF2, 0xFF375F, 0xFF453A, 0xFF9F0A, 0xFFD60A, 0x30D158, 0x40C8E0]
        .map { RGBA(hex: $0) }

    static func name(of color: RGBA) -> String {
        let names = ["White", "Black", "Blue", "Indigo", "Purple", "Pink", "Red", "Orange", "Yellow", "Green", "Teal"]
        return palette.firstIndex(of: color).map { names[$0] } ?? "Custom color"
    }

    /// One-click looks.
    static let presets: [(name: String, style: TitleStyle)] = [
        ("Classic", TitleStyle()),
        ("Midnight", TitleStyle(font: .system, weight: .semibold, card: .dark)),
        ("Frosted", TitleStyle(font: .system, weight: .bold, card: .glass)),
        ("Keynote", TitleStyle(font: .system, weight: .heavy, card: .none)),
        ("Bubble", TitleStyle(font: .rounded, weight: .bold, card: .color, cardColor: RGBA(hex: 0x0A84FF))),
        ("Editorial", TitleStyle(font: .serif, weight: .semibold, card: .light)),
        ("Terminal", TitleStyle(font: .mono, weight: .medium, card: .dark, textColor: RGBA(hex: 0x30D158))),
        ("Poster", TitleStyle(font: .expanded, weight: .heavy, card: .color, cardColor: RGBA(hex: 0xFF375F))),
    ]
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
    /// Centre of the title on the canvas (normalised, top-left) when placement is custom.
    var textX: Double = 0.5
    var textY: Double = 0.5
    /// A smaller second line under the title.
    var subtitle = ""
    var titleStyle = TitleStyle()
    /// Image overlay: a file in the project's "overlays" folder, its width as a fraction of the canvas
    /// (centred on textX/textY), rounded corners in 1080p pixels, and a drop shadow.
    var imageFile = ""
    var imageWidth: Double = 0.3
    var imageCorner: Double = 14
    var imageShadow = true
    /// Arrows and shapes, drawn on the recording in the effect's area.
    var shape: AnnotationShape = .arrow
    var arrowDirection: ArrowDirection = .downRight
    var strokeColor = RGBA(hex: 0xFF453A)
    var strokeWidth: Double = 6
    /// "Move camera": where the camera bubble goes, and its size, for this part.
    var cameraCorner: CameraCorner = .topRight
    var cameraSize: Double = 0.3
    /// Kept on the timeline but not rendered.
    var disabled = false
    var duration: Double { end - start }
    var region: CGRect { CGRect(x: x, y: y, width: w, height: h) }

    init(kind: EffectKind, start: Double, end: Double) {
        self.kind = kind
        self.start = start
        self.end = end
        if kind == .spotlight { intensity = 0.55 }
        if kind == .annotation { x = 0.35; y = 0.3; w = 0.2; h = 0.18 }
        if kind == .image { textX = 0.78; textY = 0.25 }
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
        disabled = try c.decodeIfPresent(Bool.self, forKey: .disabled) ?? false
        textX = try c.decodeIfPresent(Double.self, forKey: .textX) ?? 0.5
        textY = try c.decodeIfPresent(Double.self, forKey: .textY) ?? 0.5
        subtitle = (try? c.decodeIfPresent(String.self, forKey: .subtitle)) ?? ""
        titleStyle = (try? c.decodeIfPresent(TitleStyle.self, forKey: .titleStyle)) ?? TitleStyle()
        imageFile = (try? c.decodeIfPresent(String.self, forKey: .imageFile)) ?? ""
        imageWidth = (try? c.decodeIfPresent(Double.self, forKey: .imageWidth)) ?? 0.3
        imageCorner = (try? c.decodeIfPresent(Double.self, forKey: .imageCorner)) ?? 14
        imageShadow = (try? c.decodeIfPresent(Bool.self, forKey: .imageShadow)) ?? true
        shape = (try? c.decodeIfPresent(AnnotationShape.self, forKey: .shape)) ?? .arrow
        arrowDirection = (try? c.decodeIfPresent(ArrowDirection.self, forKey: .arrowDirection)) ?? .downRight
        strokeColor = (try? c.decodeIfPresent(RGBA.self, forKey: .strokeColor)) ?? RGBA(hex: 0xFF453A)
        strokeWidth = (try? c.decodeIfPresent(Double.self, forKey: .strokeWidth)) ?? 6
        cameraCorner = (try? c.decodeIfPresent(CameraCorner.self, forKey: .cameraCorner)) ?? .topRight
        cameraSize = (try? c.decodeIfPresent(Double.self, forKey: .cameraSize)) ?? 0.3
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
    /// Two-stop custom gradient; used instead of the preset when set.
    var customGradient: [RGBA]? = nil
    /// Rotates the gradient's colors, in degrees.
    var gradientHue: Double = 0
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

/// Normalised (top-left) part of the recording that stays visible.
struct CropRect: Codable, Equatable {
    var x: Double, y: Double, w: Double, h: Double
    static let full = CropRect(x: 0, y: 0, w: 1, h: 1)
    var isFull: Bool { x <= 0.0005 && y <= 0.0005 && w >= 0.999 && h >= 0.999 }
    var rect: CGRect { CGRect(x: x, y: y, width: w, height: h) }

    /// Full-frame normalised point → cropped normalised point.
    func toCrop(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - x) / max(w, 0.0001), y: (p.y - y) / max(h, 0.0001))
    }
    func toCrop(_ r: CGRect) -> CGRect {
        let o = toCrop(r.origin)
        return CGRect(x: o.x, y: o.y, width: r.width / max(w, 0.0001), height: r.height / max(h, 0.0001))
    }
}

/// How the camera moves into and around zooms.
enum ScreenAnimation: String, Codable, CaseIterable, Identifiable {
    case focused, smooth
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var icon: String { self == .focused ? "scope" : "point.topleft.down.to.point.bottomright.curvepath" }
    var detail: String { self == .focused ? "Snappy and direct" : "Slower, floatier camera" }
}

enum CursorStyleKind: String, Codable, CaseIterable, Identifiable {
    case outline, system, thin, contrast, gradient, dot
    var id: String { rawValue }
    var label: String {
        switch self {
        case .outline: return "Classic"
        case .system: return "As recorded"
        case .thin: return "Thin"
        case .contrast: return "High contrast"
        case .gradient: return "Warm"
        case .dot: return "Touch"
        }
    }
}

enum CursorRotation: String, Codable, CaseIterable, Identifiable {
    case off, tilt, follow
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum ShadowStyle: String, Codable, CaseIterable, Identifiable {
    case classic, directional
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
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
    var shadowStyle: ShadowStyle = .classic
    /// Directional shadow offset, in 1080p pixels, and its angle in degrees (0 = right, 90 = down).
    var shadowDistance: Double = 24
    var shadowAngle: Double = 90
    /// A thin border drawn inside the screen, like a bezel.
    var inset = false
    var insetSize: Double = 6
    var insetColor = RGBA(hex: 0x888888)
    var insetOpacity: Double = 0.35
    /// The visible part of the recording (nil = everything).
    var crop: CropRect? = nil

    var showCursor = true
    var cursorSize: Double = 1.6
    var cursorSmoothing: Double = 0.55
    var highResCursor = true
    var hideIdleCursor = false
    var cursorMotionBlur = true
    var clickEffect: ClickEffect = .ripple
    var cursorStyle: CursorStyleKind = .outline
    /// Keep the arrow even over text fields and links.
    var alwaysPointer = false
    /// Freeze the cursor for the last N seconds of the video.
    var cursorStopAtEnd: Double = 0
    var removeCursorShakes = true
    var cursorShakeThreshold: Double = 0.25
    /// Ignore cursor-shape changes shorter than ~0.12 s (no flicker over UI elements).
    var optimizeCursorChanges = true
    /// Ease the cursor back to where it started at the end, so loops join up.
    var loopCursor = false
    /// Fixed cursor tilt in degrees.
    var cursorAngle: Double = 0
    var cursorRotation: CursorRotation = .off
    var cursorTiltAmount: Double = 0.3

    var zoomTransition: Double = 0.9
    var defaultZoomScale: Double = 2.0
    var screenAnimation: ScreenAnimation = .smooth
    /// Cinematic blur on the whole screen while zooming and panning (0 = off).
    var motionBlur: Double = 0.6
    /// Begin zooming in before each zoom starts, so it's fully zoomed on time.
    var startZoomEarly = false
    /// Keep zooms on the timeline but don't render them.
    var zoomsDisabled = false

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
    /// Moments marked while recording (source time).
    var flags: [Double] = []
    /// What this recording is for (typed before or after recording).
    var notes: String = ""

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
        // Projects from older versions lack newer style options; ProjectIO.load fills them in from defaults.
        style = (try? c.decode(Style.self, forKey: .style)) ?? Style()
        effects = try c.decodeIfPresent([EffectSegment].self, forKey: .effects) ?? []
        captions = try c.decodeIfPresent([CaptionCue].self, forKey: .captions) ?? []
        flags = try c.decodeIfPresent([Double].self, forKey: .flags) ?? []
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
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
