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
    let effects: [EffectSegment]
    let captions: [CaptionCue]
    /// Keystroke badges to show: each label is visible from `start` until `end`.
    let keyItems: [(start: Double, end: Double, label: String)]

    private let lock = NSLock()
    private var backgroundCache: (CGSize, CIImage)?

    init(style: Style, info: RecordingInfo, editMap: EditMap, zooms: [ZoomSegment], cursorPath: CursorPath?,
         cursorTrack: CursorTrack, cursorImages: [String: CIImage],
         screenTrackID: CMPersistentTrackID, webcamTrackID: CMPersistentTrackID?,
         effects: [EffectSegment] = [], captions: [CaptionCue] = [], keys: [KeyEvent] = []) {
        self.style = style
        sourceSize = CGSize(width: info.pixelWidth, height: info.pixelHeight)
        pointSize = CGSize(width: info.pointWidth, height: info.pointHeight)
        self.editMap = editMap
        self.cursor = cursorPath
        clicks = cursorTrack.clicks.sorted { $0.t < $1.t }
        shapes = cursorTrack.shapes.sorted { $0.t < $1.t }
        shapeInfo = cursorTrack.shapeInfo
        self.cursorImages = cursorImages
        self.screenTrackID = screenTrackID
        self.webcamTrackID = webcamTrackID
        aspect = style.aspect.value(source: sourceSize, padding: style.padding)
        self.effects = effects.sorted { $0.start < $1.start }
        self.captions = style.showCaptions ? captions.sorted { $0.start < $1.start } : []
        keyItems = RenderModel.buildKeyItems(keys, mode: style.keystrokes)

        // Layout at a reference size to know how much of the screen the frame shows.
        let ref = CGSize(width: 1000 * aspect, height: 1000)
        let sr = RenderModel.layout(style: style, sourceSize: sourceSize, size: ref).screenRect
        let half = CGSize(width: ref.width / 2 / max(sr.width, 1), height: ref.height / 2 / max(sr.height, 1))
        camera = CameraPath(zooms: zooms, cursor: cursorPath, duration: info.duration + 1,
                            transition: style.zoomTransition, viewHalfExtent: half)
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
                ctx.setShadow(offset: CGSize(width: 0, height: -blur * 0.35), blur: blur,
                              color: CGColor(gray: 0, alpha: CGFloat(min(1, style.shadow))))
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
        if let c = current, let info = shapeInfo[c.id] {
            if style.highResCursor && info.isArrow { return (CursorArt.arrowImage, CursorArt.arrowInfo) }
            if let img = cursorImages[c.id] { return (img, info) }
        }
        return (CursorArt.arrowImage, CursorArt.arrowInfo)
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

/// High-resolution vector macOS-style arrow cursor.
enum CursorArt {
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
