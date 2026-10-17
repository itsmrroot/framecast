import SwiftUI

/// Edit a blur or spotlight area right on the video: drag inside to move, drag a handle to resize,
/// drag outside to draw a new one. Works at any zoom, because it uses the renderer's own camera math.
struct RegionCanvasOverlay: View {
    @ObservedObject var model: EditorModel
    let effect: EffectSegment
    let size: CGSize
    @State private var drag: (handle: Handle, start: CGRect, origin: CGPoint)?

    enum Handle { case draw, move, n, s, e, w, ne, nw, se, sw }

    var body: some View {
        if let rm = model.renderModel {
            let vt = FrameRenderer.shared.viewTransform(model: rm, sourceTime: model.sourceTime, size: size)
            let r = vt.viewRect(fullFrame: effect.region, crop: rm.crop, canvasHeight: size.height)
            let tint = TimelineView.effectColor(effect.kind)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(tint.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])).foregroundStyle(.white))
                    .frame(width: max(2, r.width), height: max(2, r.height))
                    .offset(x: r.minX, y: r.minY)
                ForEach(Array(handles(r).enumerated()), id: \.offset) { _, p in
                    Circle().fill(.white).frame(width: 11, height: 11)
                        .overlay(Circle().strokeBorder(Color.black.opacity(0.25)))
                        .shadow(color: .black.opacity(0.4), radius: 2)
                        .position(p)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 1)
                .onChanged { v in
                    if drag == nil { drag = (hit(v.startLocation, r), r, v.startLocation) }
                    guard let d = drag else { return }
                    let nr = adjust(d, to: v.location, translation: v.translation)
                    guard nr.width > 6, nr.height > 6 else { return }
                    let a = vt.fullFramePoint(view: CGPoint(x: nr.minX, y: nr.minY), crop: rm.crop, canvasHeight: size.height)
                    let b = vt.fullFramePoint(view: CGPoint(x: nr.maxX, y: nr.maxY), crop: rm.crop, canvasHeight: size.height)
                    let x0 = clamp(Double(min(a.x, b.x)), 0, 1), y0 = clamp(Double(min(a.y, b.y)), 0, 1)
                    let x1 = clamp(Double(max(a.x, b.x)), 0, 1), y1 = clamp(Double(max(a.y, b.y)), 0, 1)
                    model.updateEffect(effect.id, coalesce: "region-\(effect.id)") {
                        $0.x = x0; $0.y = y0; $0.w = max(0.005, x1 - x0); $0.h = max(0.005, y1 - y0)
                    }
                }
                .onEnded { _ in drag = nil })
            .help("Drag to move the area, drag a handle to resize, or drag outside to draw a new one")
        }
    }

    private func handles(_ r: CGRect) -> [CGPoint] {
        [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
         CGPoint(x: r.maxX, y: r.midY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.midX, y: r.maxY),
         CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.minX, y: r.midY)]
    }

    private func hit(_ p: CGPoint, _ r: CGRect) -> Handle {
        let t: CGFloat = 10
        let l = abs(p.x - r.minX) < t, rt = abs(p.x - r.maxX) < t, tp = abs(p.y - r.minY) < t, b = abs(p.y - r.maxY) < t
        let inX = p.x > r.minX - t && p.x < r.maxX + t, inY = p.y > r.minY - t && p.y < r.maxY + t
        if l && tp { return .nw }; if rt && tp { return .ne }; if l && b { return .sw }; if rt && b { return .se }
        if l && inY { return .w }; if rt && inY { return .e }; if tp && inX { return .n }; if b && inX { return .s }
        return r.contains(p) ? .move : .draw
    }

    private func adjust(_ d: (handle: Handle, start: CGRect, origin: CGPoint), to p: CGPoint, translation t: CGSize) -> CGRect {
        let r0 = d.start
        switch d.handle {
        case .draw:
            return CGRect(x: min(d.origin.x, p.x), y: min(d.origin.y, p.y), width: abs(p.x - d.origin.x), height: abs(p.y - d.origin.y))
        case .move:
            return r0.offsetBy(dx: t.width, dy: t.height)
        default:
            var minX = r0.minX, maxX = r0.maxX, minY = r0.minY, maxY = r0.maxY
            if [.w, .nw, .sw].contains(d.handle) { minX = min(r0.minX + t.width, maxX - 8) }
            if [.e, .ne, .se].contains(d.handle) { maxX = max(r0.maxX + t.width, minX + 8) }
            if [.n, .nw, .ne].contains(d.handle) { minY = min(r0.minY + t.height, maxY - 8) }
            if [.s, .sw, .se].contains(d.handle) { maxY = max(r0.maxY + t.height, minY + 8) }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
    }
}

/// Drag a title anywhere on the canvas (switches it to a custom position). While dragging, the title is drawn
/// here, under the pointer, and the renderer leaves it out, so it follows without lag.
struct TitleCanvasOverlay: View {
    @ObservedObject var model: EditorModel
    let effect: EffectSegment
    let size: CGSize
    @State private var startCenter: CGPoint?
    @State private var dragCenter: CGPoint?

    var body: some View {
        let base = Self.cardFrame(effect, size: size)
        let frame = dragCenter.map { c in
            CGRect(x: c.x - base.width / 2, y: c.y - base.height / 2, width: base.width, height: base.height)
        } ?? base
        ZStack(alignment: .topLeading) {
            if dragCenter != nil, let img = Self.liveImage(effect, size: size) {
                Group {
                    if effect.titleStyle.card == .glass {
                        Image(decorative: img, scale: 2)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: min(frame.height / 2, 26 * min(size.width, size.height) / 1080 * CGFloat(effect.textSize)), style: .continuous))
                    } else {
                        Image(decorative: img, scale: 2)
                    }
                }
                .frame(width: frame.width, height: frame.height)
                .shadow(color: .black.opacity(effect.titleStyle.card == .none ? 0 : 0.3), radius: 14, y: 6)
                .offset(x: frame.minX, y: frame.minY)
                .allowsHitTesting(false)
            }
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .foregroundStyle(.white)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(dragCenter == nil ? 0.06 : 0)))
                .frame(width: frame.width + 12, height: frame.height + 12)
                .offset(x: frame.minX - 6, y: frame.minY - 6)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 1)
                    .onChanged { v in
                        if startCenter == nil {
                            startCenter = CGPoint(x: frame.midX, y: frame.midY)
                            model.hiddenEffect = effect.id
                        }
                        guard let c = startCenter else { return }
                        // Keep the card on the canvas, as the renderer does.
                        let x = clamp(c.x + v.translation.width, base.width / 2, max(base.width / 2, size.width - base.width / 2))
                        let y = clamp(c.y + v.translation.height, base.height / 2, max(base.height / 2, size.height - base.height / 2))
                        dragCenter = CGPoint(x: x, y: y)
                    }
                    .onEnded { _ in
                        if let c = dragCenter {
                            let nx = clamp(Double(c.x / size.width), 0, 1), ny = clamp(Double(c.y / size.height), 0, 1)
                            model.updateEffect(effect.id, coalesce: "titlepos-\(effect.id)") {
                                $0.placement = .custom; $0.textX = nx; $0.textY = ny
                            }
                        }
                        startCenter = nil
                        dragCenter = nil
                        model.hiddenEffect = nil
                    })
            Label("Drag to move", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.system(size: 10.5, weight: .semibold))
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Capsule().fill(Color.black.opacity(0.6)))
                .foregroundStyle(.white)
                .offset(x: frame.minX - 6, y: max(0, frame.minY - 30))
                .allowsHitTesting(false)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .onDisappear { if model.hiddenEffect == effect.id { model.hiddenEffect = nil } }
    }

    private static func fontSize(_ e: EffectSegment, size: CGSize) -> CGFloat {
        58 * min(size.width, size.height) / 1080 * CGFloat(e.textSize)
    }

    /// The title at 2× the view size, for a sharp live preview.
    private static func liveImage(_ e: EffectSegment, size: CGSize) -> CGImage? {
        FrameRenderer.shared.text.title(e.text.isEmpty ? " " : e.text, subtitle: e.subtitle, style: e.titleStyle,
                                        fontSize: fontSize(e, size: size) * 2, maxWidth: size.width * 0.82 * 2).cgImage
    }

    /// Where the title card sits on the canvas (top-left view coordinates), matching the renderer.
    static func cardFrame(_ effect: EffectSegment, size: CGSize) -> CGRect {
        let img = FrameRenderer.shared.text.title(effect.text.isEmpty ? " " : effect.text, subtitle: effect.subtitle,
                                                  style: effect.titleStyle, fontSize: fontSize(effect, size: size),
                                                  maxWidth: size.width * 0.82).image
        let w = img.extent.width, h = img.extent.height
        let margin = min(size.width, size.height) * 0.08
        var y: CGFloat
        var x: CGFloat
        switch effect.titleStyle.align {
        case .left: x = margin
        case .center: x = (size.width - w) / 2
        case .right: x = size.width - margin - w
        }
        switch effect.placement {
        case .top: y = margin
        case .center: y = (size.height - h) / 2
        case .bottom: y = size.height - margin - h
        case .custom:
            x = min(max(0, CGFloat(effect.textX) * size.width - w / 2), size.width - w)
            y = min(max(0, CGFloat(effect.textY) * size.height - h / 2), size.height - h)
        }
        return CGRect(x: x, y: y, width: w, height: h)
    }
}

enum PreviewHitTest {
    /// The effect under a click on the preview (top-left view point): titles first, then blur/spotlight areas.
    @MainActor
    static func effect(at p: CGPoint, model: EditorModel, size: CGSize) -> EffectSegment? {
        let t = model.sourceTime
        let active = model.doc.effects.filter { !$0.disabled && t >= $0.start && t <= $0.end }
        if let title = active.last(where: { $0.kind == .text && !$0.text.isEmpty
            && TitleCanvasOverlay.cardFrame($0, size: size).insetBy(dx: -6, dy: -6).contains(p) }) {
            return title
        }
        guard let rm = model.renderModel else { return nil }
        let vt = FrameRenderer.shared.viewTransform(model: rm, sourceTime: t, size: size)
        return active.last { $0.kind.hasRegion && vt.viewRect(fullFrame: $0.region, crop: rm.crop, canvasHeight: size.height).contains(p) }
    }
}
