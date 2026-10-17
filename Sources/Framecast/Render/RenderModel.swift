import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreMedia
import AppKit

struct FrameLayout {
    let size: CGSize
    let screenRect: CGRect
    /// 1 unit = 1px at 1080p; keeps styling resolution-independent.
    let unit: CGFloat
}

/// Immutable snapshot of everything needed to render a frame. A new one is built whenever the edit changes.
final class RenderModel: @unchecked Sendable {
    let style: Style
    let sourceSize: CGSize
    let pointSize: CGSize
    let editMap: EditMap
    let camera: CameraPath
    let cursor: CursorPath?
    let clicks: [ClickEvent]
    let shapes: [CursorShapeChange]
    let shapeInfo: [String: CursorShapeInfo]
    let cursorImages: [String: CIImage]
    let aspect: CGFloat
    let screenTrackID: CMPersistentTrackID
    let webcamTrackID: CMPersistentTrackID?
    /// Visible part of the recording; everything else in the model is relative to it.
    let crop: CropRect
    let effects: [EffectSegment]
    /// Image overlay files, loaded by name.
    let overlayImages: [String: CIImage]
    let captions: [CaptionCue]
    /// Keystroke badges to show: each label is visible from `start` until `end`.
    let keyItems: [(start: Double, end: Double, label: String)]

    private let lock = NSLock()
    private var backgroundCache: (CGSize, CIImage)?

    init(style: Style, info: RecordingInfo, editMap: EditMap, zooms: [ZoomSegment], cursorPath: CursorPath?,
         cursorTrack: CursorTrack, cursorImages: [String: CIImage],
         screenTrackID: CMPersistentTrackID, webcamTrackID: CMPersistentTrackID?,
         effects: [EffectSegment] = [], captions: [CaptionCue] = [], keys: [KeyEvent] = [],
         overlayImages: [String: CIImage] = [:]) {
        self.overlayImages = overlayImages
        self.style = style
        let crop = (style.crop?.isFull ?? true) ? CropRect.full : style.crop!
        self.crop = crop
        sourceSize = CGSize(width: Double(info.pixelWidth) * crop.w, height: Double(info.pixelHeight) * crop.h)
        pointSize = CGSize(width: info.pointWidth * crop.w, height: info.pointHeight * crop.h)
        self.editMap = editMap
        self.cursor = cursorPath
        clicks = cursorTrack.cropped(crop).clicks.sorted { $0.t < $1.t }
        var shapes = cursorTrack.shapes.sorted { $0.t < $1.t }
        if style.optimizeCursorChanges && shapes.count > 2 {
            // A shape shown for less than ~0.12 s is flicker (passing over a link or text field).
            shapes = shapes.enumerated().filter { i, s in
                i == 0 || i == shapes.count - 1 || shapes[i + 1].t - s.t >= 0.12
            }.map(\.element)
        }
        self.shapes = shapes
        shapeInfo = cursorTrack.shapeInfo
        self.cursorImages = cursorImages
        self.screenTrackID = screenTrackID
        self.webcamTrackID = webcamTrackID
        aspect = style.aspect.value(source: sourceSize, padding: style.padding)
        self.effects = effects.filter { !$0.disabled }.sorted { $0.start < $1.start }
        self.captions = style.showCaptions ? captions.sorted { $0.start < $1.start } : []
        keyItems = RenderModel.buildKeyItems(keys, mode: style.keystrokes)

        // Layout at a reference size to know how much of the screen the frame shows.
        let ref = CGSize(width: 1000 * aspect, height: 1000)
        let sr = RenderModel.layout(style: style, sourceSize: sourceSize, size: ref).screenRect
        let half = CGSize(width: ref.width / 2 / max(sr.width, 1), height: ref.height / 2 / max(sr.height, 1))
        // Fixed zoom focus points are picked on the full frame.
        let viewZooms = style.zoomsDisabled ? [] : zooms.map { z -> ZoomSegment in
            var z = z
            let p = crop.toCrop(CGPoint(x: z.focusX, y: z.focusY))
            z.focusX = clamp(Double(p.x), 0, 1)
            z.focusY = clamp(Double(p.y), 0, 1)
            return z
        }
        camera = CameraPath(zooms: viewZooms, cursor: cursorPath, duration: info.duration + 1,
                            transition: style.zoomTransition, viewHalfExtent: half,
                            animation: style.screenAnimation, startEarly: style.startZoomEarly)
    }

    static func layout(style: Style, sourceSize: CGSize, size: CGSize) -> FrameLayout {
        let minDim = min(size.width, size.height)
        let pad = CGFloat(style.padding) * minDim
        let avail = CGRect(x: pad, y: pad, width: max(1, size.width - 2 * pad), height: max(1, size.height - 2 * pad))
        let aspect = sourceSize.height > 0 ? sourceSize.width / sourceSize.height : 16.0 / 9.0
        return FrameLayout(size: size, screenRect: avail.aspectFit(aspect: aspect), unit: minDim / 1080)
    }

    func layout(for size: CGSize) -> FrameLayout {
        RenderModel.layout(style: style, sourceSize: sourceSize, size: size)
    }

    /// Output size whose shorter side is `shortSide` pixels.
    func outputSize(shortSide: Int) -> CGSize {
        if aspect >= 1 {
            return CGSize(width: evenInt(Double(shortSide) * aspect), height: evenInt(Double(shortSide)))
        } else {
            return CGSize(width: evenInt(Double(shortSide)), height: evenInt(Double(shortSide) / aspect))
        }
    }

    /// Output size whose longer side is `longSide` pixels.
    func outputSize(longSide: Int) -> CGSize {
        if aspect >= 1 {
            return CGSize(width: evenInt(Double(longSide)), height: evenInt(Double(longSide) / aspect))
        } else {
            return CGSize(width: evenInt(Double(longSide) * aspect), height: evenInt(Double(longSide)))
        }
    }

    /// Background + drop shadow, cached per output size.
    func background(size: CGSize, ciContext: CIContext) -> CIImage {
        lock.lock()
        defer { lock.unlock() }
        if let (s, img) = backgroundCache, s == size { return img }

        let L = layout(for: size)
        let w = Int(size.width), h = Int(size.height)
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        var result = CIImage(color: CIColor.black).cropped(to: rect)
        if let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                               space: CGColorSpace(name: CGColorSpace.sRGB)!,
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            if let bg = Backgrounds.render(style.background, size: size, ciContext: ciContext) {
                ctx.draw(bg, in: rect)
            }
            if style.shadow > 0.01 {
                let r = CGFloat(style.cornerRadius) * L.unit
                let blur = CGFloat(style.shadowBlur) * L.unit
                let offset: CGSize
                if style.shadowStyle == .directional {
                    // Angle 0 = right, 90 = down (Core Graphics y points up).
                    let a = style.shadowAngle * .pi / 180
                    let d = CGFloat(style.shadowDistance) * L.unit
                    offset = CGSize(width: cos(a) * d, height: -sin(a) * d)
                } else {
                    offset = CGSize(width: 0, height: -blur * 0.35)
                }
                ctx.setShadow(offset: offset, blur: blur, color: CGColor(gray: 0, alpha: CGFloat(min(1, style.shadow))))
                ctx.setFillColor(CGColor(gray: 0, alpha: 1))
                ctx.addPath(CGPath(roundedRect: L.screenRect.insetBy(dx: 1, dy: 1),
                                   cornerWidth: min(r, L.screenRect.width / 2), cornerHeight: min(r, L.screenRect.height / 2), transform: nil))
                ctx.fillPath()
            }
            if let img = ctx.makeImage() { result = CIImage(cgImage: img) }
        }
        backgroundCache = (size, result)
        return result
    }

    /// Cursor art at time t: image, plus hotspot/size in points.
    func cursorArt(at t: Double) -> (CIImage, CursorShapeInfo) {
        var current: CursorShapeChange?
        var lo = 0, hi = shapes.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if shapes[mid].t <= t { current = shapes[mid]; lo = mid + 1 } else { hi = mid - 1 }
        }
        if current == nil { current = shapes.first }
        let vector = CursorArt.art(style.cursorStyle == .system ? .outline : style.cursorStyle)
        if style.alwaysPointer { return vector }
        if let c = current, let info = shapeInfo[c.id] {
            if style.cursorStyle != .system && info.isArrow { return vector }
            if let img = cursorImages[c.id] { return (img, info) }
        }
        return vector
    }

    // MARK: Effects, captions, keystrokes

    /// How visible an effect is at time t (0...1), with short fades at both ends.
    static func envelope(_ e: EffectSegment, at t: Double) -> Double {
        guard t >= e.start, t <= e.end else { return 0 }
        let fade = max(0.01, min(0.3, e.duration / 4))
        return smootherstep((t - e.start) / fade) * smootherstep((e.end - t) / fade)
    }

    func activeEffects(at t: Double) -> [(EffectSegment, Double)] {
        var out: [(EffectSegment, Double)] = []
        for e in effects {
            if e.start > t { break }
            let a = RenderModel.envelope(e, at: t)
            if a > 0.001 { out.append((e, a)) }
        }
        return out
    }

    /// Strongest envelope among active effects of a kind.
    /// The "Move camera" effect in force at `t`, with how far the move has gone.
    func cameraMove(at t: Double) -> (EffectSegment, Double)? {
        var best: (EffectSegment, Double)?
        for e in effects where e.kind == .cameraMove {
            if e.start > t { break }
            let a = RenderModel.envelope(e, at: t)
            if a > (best?.1 ?? 0.001) { best = (e, a) }
        }
        return best
    }

    func amount(of kind: EffectKind, at t: Double) -> Double {
        var best = 0.0
        for e in effects where e.kind == kind {
            if e.start > t { break }
            best = max(best, RenderModel.envelope(e, at: t))
        }
        return best
    }

    func caption(at t: Double) -> CaptionCue? {
        var lo = 0, hi = captions.count - 1, idx = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if captions[mid].start <= t { idx = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        guard idx >= 0, t < captions[idx].end else { return nil }
        return captions[idx]
    }

    /// The keystroke label at time t and its opacity.
    func keystroke(at t: Double) -> (String, Double)? {
        var lo = 0, hi = keyItems.count - 1, idx = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if keyItems[mid].start <= t { idx = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        guard idx >= 0 else { return nil }
        let item = keyItems[idx]
        guard t < item.end else { return nil }
        return (item.label, min(1, (item.end - t) / 0.25))
    }

    private static func buildKeyItems(_ keys: [KeyEvent], mode: KeystrokeMode) -> [(start: Double, end: Double, label: String)] {
        guard mode != .off else { return [] }
        let hold = 1.4
        var items: [(start: Double, end: Double, label: String)] = []
        var typing = ""
        var lastTyped = -10.0
        for k in keys.sorted(by: { $0.t < $1.t }) {
            var label: String
            if k.isShortcut && !(mode == .all && k.label == "⌫" && !typing.isEmpty && k.t - lastTyped < 1.2) {
                label = k.label
                typing = ""
            } else if mode == .all {
                if k.t - lastTyped > 1.2 { typing = "" }
                if k.label == "⌫" { typing = String(typing.dropLast()) } else { typing += k.label }
                if typing.count > 28 { typing = "…" + typing.suffix(27) }
                lastTyped = k.t
                label = typing.isEmpty ? "⌫" : typing
            } else {
                continue
            }
            if !items.isEmpty, items[items.count - 1].end > k.t { items[items.count - 1].end = k.t }
            items.append((k.t, k.t + hold, label))
        }
        return items
    }

    func pressScale(at t: Double) -> CGFloat {
        // binary search the last click before t
        var lo = 0, hi = clicks.count - 1, idx = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if clicks[mid].t <= t { idx = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        guard idx >= 0 else { return 1 }
        let d = (t - clicks[idx].t) / 0.28
        guard d >= 0 && d <= 1 else { return 1 }
        return CGFloat(1 - 0.18 * sin(.pi * d))
    }
}

extension CursorTrack {
    /// The track with positions relative to a crop of the recording.
    func cropped(_ crop: CropRect) -> CursorTrack {
        guard !crop.isFull else { return self }
        var t = self
        t.samples = samples.map { s in
            let p = crop.toCrop(CGPoint(x: s.x, y: s.y))
            return CursorSample(t: s.t, x: Double(p.x), y: Double(p.y))
        }
        t.clicks = clicks.map { c in
            let p = crop.toCrop(CGPoint(x: c.x, y: c.y))
            return ClickEvent(t: c.t, x: Double(p.x), y: Double(p.y), button: c.button)
        }
        return t
    }
}

/// High-resolution vector cursors drawn by the renderer.
enum CursorArt {
    private static let lock = NSLock()
    private static var styled: [CursorStyleKind: (CIImage, CursorShapeInfo)] = [:]

    /// The cursor image and geometry for a style (cached).
    static func art(_ style: CursorStyleKind) -> (CIImage, CursorShapeInfo) {
        lock.lock()
        defer { lock.unlock() }
        if let hit = styled[style] { return hit }
        let made: (CIImage, CursorShapeInfo)
        switch style {
        case .outline, .system: made = (arrowImage, arrowInfo)
        case .dot:
            let info = CursorShapeInfo(id: "vector-dot", hotX: 12, hotY: 12, width: 24, height: 24, isArrow: true)
            made = (draw(info) { ctx in
                ctx.setShadow(offset: CGSize(width: 0, height: 1), blur: 3, color: CGColor(gray: 0, alpha: 0.35))
                ctx.setFillColor(CGColor(gray: 0.15, alpha: 0.55))
                ctx.fillEllipse(in: CGRect(x: 3, y: 3, width: 18, height: 18))
                ctx.setShadow(offset: .zero, blur: 0, color: nil)
                ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.95))
                ctx.setLineWidth(2)
                ctx.strokeEllipse(in: CGRect(x: 3, y: 3, width: 18, height: 18))
            }, info)
        case .thin, .contrast, .gradient:
            let info = arrowInfo
            made = (draw(info) { ctx in
                let path = arrowPath()
                ctx.setLineJoin(.round)
                ctx.saveGState()
                ctx.setShadow(offset: CGSize(width: 0, height: 1.2), blur: 2.6, color: CGColor(gray: 0, alpha: 0.4))
                ctx.addPath(path)
                switch style {
                case .thin:
                    ctx.setStrokeColor(CGColor(gray: 1, alpha: 1)); ctx.setLineWidth(1.6); ctx.strokePath()
                case .contrast:
                    ctx.setStrokeColor(CGColor(gray: 0, alpha: 1)); ctx.setLineWidth(4.2); ctx.strokePath()
                default:
                    ctx.setStrokeColor(CGColor(gray: 0.08, alpha: 1)); ctx.setLineWidth(2.6); ctx.strokePath()
                }
                ctx.restoreGState()
                ctx.addPath(path)
                ctx.clip()
                switch style {
                case .thin: ctx.setFillColor(CGColor(gray: 0.05, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
                case .contrast: ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
                default:
                    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [
                        CGColor(srgbRed: 1, green: 0.62, blue: 0.2, alpha: 1), CGColor(srgbRed: 0.95, green: 0.25, blue: 0.5, alpha: 1),
                    ] as CFArray, locations: [0, 1])!
                    ctx.drawLinearGradient(g, start: CGPoint(x: 4, y: 3), end: CGPoint(x: 16, y: 26), options: [])
                }
            }, info)
        }
        styled[style] = made
        return made
    }

    private static func arrowPath() -> CGPath {
        let pts: [CGPoint] = [
            CGPoint(x: 4, y: 3), CGPoint(x: 4, y: 23.6), CGPoint(x: 8.9, y: 18.9),
            CGPoint(x: 12.1, y: 26.5), CGPoint(x: 15.7, y: 25.0), CGPoint(x: 12.6, y: 17.6),
            CGPoint(x: 19.3, y: 17.6),
        ]
        let path = CGMutablePath()
        path.addLines(between: pts)
        path.closeSubpath()
        return path
    }

    /// Draws at 8× in point space with a top-left origin.
    private static func draw(_ info: CursorShapeInfo, _ body: (CGContext) -> Void) -> CIImage {
        let scale: CGFloat = 8
        let w = Int(info.width * scale), h = Int(info.height * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return .empty() }
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        body(ctx)
        guard let img = ctx.makeImage() else { return .empty() }
        return CIImage(cgImage: img)
    }

    static let arrowInfo = CursorShapeInfo(id: "vector-arrow", hotX: 4, hotY: 3, width: 24, height: 32, isArrow: true)

    static let arrowImage: CIImage = {
        let scale: CGFloat = 8
        let w = Int(arrowInfo.width * scale), h = Int(arrowInfo.height * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return CIImage.empty() }
        // Flip to top-left origin, in points.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)

        let pts: [CGPoint] = [
            CGPoint(x: 4, y: 3), CGPoint(x: 4, y: 23.6), CGPoint(x: 8.9, y: 18.9),
            CGPoint(x: 12.1, y: 26.5), CGPoint(x: 15.7, y: 25.0), CGPoint(x: 12.6, y: 17.6),
            CGPoint(x: 19.3, y: 17.6),
        ]
        let path = CGMutablePath()
        path.addLines(between: pts)
        path.closeSubpath()

        ctx.setLineJoin(.round)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 1.2), blur: 2.6, color: CGColor(gray: 0, alpha: 0.45))
        ctx.addPath(path)
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
        ctx.setLineWidth(3.2)
        ctx.strokePath()
        ctx.restoreGState()

        ctx.addPath(path)
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
        ctx.setLineWidth(3.2)
        ctx.strokePath()
        ctx.addPath(path)
        ctx.setFillColor(CGColor(gray: 0.02, alpha: 1))
        ctx.fillPath()

        guard let img = ctx.makeImage() else { return CIImage.empty() }
        return CIImage(cgImage: img)
    }()

    static func loadImages(folder: URL, track: CursorTrack) -> [String: CIImage] {
        var out: [String: CIImage] = [:]
        for id in track.shapeInfo.keys {
            let url = folder.appendingPathComponent(ProjectFiles.cursors).appendingPathComponent("\(id).png")
            if let img = CIImage(contentsOf: url) { out[id] = img }
        }
        return out
    }
}
