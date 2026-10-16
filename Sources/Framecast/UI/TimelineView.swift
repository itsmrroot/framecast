import SwiftUI
import AppKit

struct TimelineView: View {
    @ObservedObject var model: EditorModel
    @State private var zoomLevel: CGFloat = 1
    @State private var drag: DragState?

    struct DragState {
        enum Kind { case clipLeft, clipRight, zoomMove, zoomLeft, zoomRight, effectMove, effectLeft, effectRight }
        var id: UUID
        var kind: Kind
        var start: Double
        var end: Double
    }

    private let rulerH: CGFloat = 24
    private let clipH: CGFloat = 60
    private let zoomH: CGFloat = 32
    private let effectRowH: CGFloat = 24
    private let gap: CGFloat = 8
    private let inset: CGFloat = 18

    var body: some View {
        let rows = effectRows()
        let rowCount = max(1, (rows.values.max() ?? -1) + 1)
        let effectsH = CGFloat(rowCount) * (effectRowH + 3) + 3
        let zoomY = rulerH + 6 + clipH + gap
        let effectsY = zoomY + zoomH + gap
        let totalH = effectsY + effectsH + 8
        return VStack(spacing: 0) {
            header
            GeometryReader { geo in
                let contentW = max(200, (geo.size.width - inset * 2) * zoomLevel)
                let pps = contentW / CGFloat(model.sourceDuration)
                ScrollView([.horizontal, .vertical], showsIndicators: zoomLevel > 1.01 || totalH > geo.size.height) {
                    ZStack(alignment: .topLeading) {
                        ruler(width: contentW, pps: pps)
                        clipTrack(width: contentW, pps: pps)
                            .offset(y: rulerH + 6)
                        zoomTrack(width: contentW, pps: pps)
                            .offset(y: zoomY)
                        effectTrack(width: contentW, pps: pps, rows: rows, height: effectsH)
                            .offset(y: effectsY)
                        playhead(pps: pps, height: totalH - 4)
                    }
                    .frame(width: contentW, height: totalH, alignment: .topLeading)
                    .padding(.horizontal, inset)
                    .padding(.top, 4)
                }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            IconButton(icon: "scissors", label: "Split", help: "Split clip at playhead (S)") { model.splitAtPlayhead() }
            IconButton(icon: "plus.magnifyingglass", label: "Zoom", help: "Add zoom at playhead (Z)") {
                model.addZoom(at: model.sourceTime)
            }
            Menu {
                ForEach(EffectKind.allCases) { kind in
                    Button {
                        model.addEffect(kind)
                    } label: {
                        Label(kind.label, systemImage: kind.icon)
                    }
                    .disabled(kind.needsCamera && !model.doc.info.hasWebcam)
                }
            } label: {
                Label("Effect", systemImage: "plus.square.on.square")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Add a blur, spotlight, title or layout change at the playhead")
            smartSpeedMenu
            IconButton(icon: "trash", help: "Delete selection (⌫)", disabled: model.selection == .none) { model.deleteSelection() }
            Spacer()
            Text(hint)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textFaint)
            Spacer()
            Image(systemName: "minus.magnifyingglass").font(.system(size: 11)).foregroundStyle(Theme.textDim)
            Slider(value: $zoomLevel, in: 1...12).controlSize(.mini).frame(width: 110).tint(Theme.accent)
            Image(systemName: "plus.magnifyingglass").font(.system(size: 11)).foregroundStyle(Theme.textDim)
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
    }

    private var hint: String {
        switch model.selection {
        case .zoom: return "Drag to move · drag edges to resize · ⌫ to delete"
        case .clip: return "Drag edges to trim · change speed in the inspector · ⌫ to cut"
        case .effect: return "Drag to move · drag edges to resize · ⌫ to delete"
        case .none: return "Click the zoom lane to add a zoom · S to split · Space to play"
        }
    }

    private var smartSpeedMenu: some View {
        let hasActivity = !model.cursorTrack.isEmpty || !model.keys.isEmpty
        let hasTyping = !model.keys.isEmpty
        return Menu {
            Section("Idle moments (no mouse or keyboard activity)") {
                Button("Speed Up Idle Moments 4×") { model.applySmartSpeed(.idle, speed: 4) }.disabled(!hasActivity)
                Button("Speed Up Idle Moments 8×") { model.applySmartSpeed(.idle, speed: 8) }.disabled(!hasActivity)
                Button("Cut Idle Moments") { model.applySmartSpeed(.idle, speed: nil) }.disabled(!hasActivity)
            }
            Section("Typing") {
                Button("Speed Up Typing 2×") { model.applySmartSpeed(.typing, speed: 2) }.disabled(!hasTyping)
                Button("Speed Up Typing 4×") { model.applySmartSpeed(.typing, speed: 4) }.disabled(!hasTyping)
            }
            Divider()
            Button("Reset All Speeds to 1×") { model.resetSpeeds() }
        } label: {
            Label("Smart Speed", systemImage: "hare")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(hasTyping ? "Automatically speed up typing and idle moments" : "Speed up idle moments. Turn on “Record keystrokes” to detect typing too.")
    }

    // MARK: Ruler

    private func tickStep(_ pps: CGFloat) -> Double {
        let steps: [Double] = [0.25, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600]
        return steps.first { CGFloat($0) * pps >= 70 } ?? 600
    }

    private func ruler(width: CGFloat, pps: CGFloat) -> some View {
        let step = tickStep(pps)
        let duration = model.sourceDuration
        return Canvas { ctx, size in
            var t = 0.0
            while t <= duration + 0.0001 {
                let x = CGFloat(t) * pps
                ctx.fill(Path(CGRect(x: x, y: size.height - 8, width: 1, height: 8)), with: .color(Theme.textFaint))
                ctx.draw(Text(formatTime(t, fraction: step < 1)).font(.system(size: 10).monospacedDigit()).foregroundColor(Theme.textDim),
                         at: CGPoint(x: x + 4, y: size.height - 14), anchor: .leading)
                for k in 1..<5 {
                    let mx = CGFloat(t + step * Double(k) / 5) * pps
                    if mx > size.width { break }
                    ctx.fill(Path(CGRect(x: mx, y: size.height - 4, width: 1, height: 4)), with: .color(Theme.textFaint.opacity(0.6)))
                }
                t += step
            }
        }
        .frame(width: width, height: rulerH)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { v in
            model.player.pause()
            model.seek(source: Double(max(0, v.location.x) / pps))
        })
    }

    // MARK: Clips

    private func clipRange(_ c: Clip) -> (Double, Double) {
        if let d = drag, d.id == c.id { return (d.start, d.end) }
        return (c.start, c.end)
    }

    private func clipTrack(width: CGFloat, pps: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.025))
                .frame(width: width, height: clipH)
                .gesture(SpatialTapGesture().onEnded { v in
                    model.selection = .none
                    model.seek(source: Double(v.location.x / pps))
                })

            filmstrip(width: width, pps: pps)
                .frame(width: width, height: clipH)
                .mask(alignment: .topLeading) {
                    ZStack(alignment: .topLeading) {
                        ForEach(model.doc.clips) { c in
                            let (s, e) = clipRange(c)
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .frame(width: max(2, CGFloat(e - s) * pps), height: clipH)
                                .offset(x: CGFloat(s) * pps)
                        }
                    }
                    .frame(width: width, height: clipH, alignment: .topLeading)
                }
                .allowsHitTesting(false)

            ForEach(model.doc.clips) { c in
                clipBlock(c, pps: pps)
            }
        }
        .frame(width: width, height: clipH, alignment: .topLeading)
    }

    private func clipBlock(_ c: Clip, pps: CGFloat) -> some View {
        let (s, e) = clipRange(c)
        let selected = model.selection == .clip(c.id)
        let w = max(2, CGFloat(e - s) * pps)
        return RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Theme.clip.opacity(selected ? 0.16 : 0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.clip.opacity(selected ? 1 : 0.45), lineWidth: selected ? 2 : 1)
            )
            .overlay(alignment: .topLeading) {
                if w > 70 {
                    HStack(spacing: 4) {
                        if abs(c.speed - 1) > 0.01 {
                            Text("\(c.speed, specifier: "%g")×")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Capsule().fill(Theme.clip))
                                .foregroundStyle(.black)
                        }
                        Text(formatTime((e - s) / c.speed, fraction: true))
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                    }
                    .padding(6)
                }
            }
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { v in
                model.selection = .clip(c.id)
                model.seek(source: s + Double(v.location.x / pps))
            })
            .overlay(alignment: .leading) { edgeHandle(color: Theme.clip, visible: selected) { dx, ended in
                let b = model.clipBounds(c.id)
                let ns = clamp(c.start + Double(dx / pps), b.lowerBound, c.end - 0.3)
                if ended { drag = nil; model.setClip(c.id, start: ns) } else { drag = DragState(id: c.id, kind: .clipLeft, start: ns, end: c.end) }
            } }
            .overlay(alignment: .trailing) { edgeHandle(color: Theme.clip, visible: selected) { dx, ended in
                let b = model.clipBounds(c.id)
                let ne = clamp(c.end + Double(dx / pps), c.start + 0.3, b.upperBound)
                if ended { drag = nil; model.setClip(c.id, end: ne) } else { drag = DragState(id: c.id, kind: .clipRight, start: c.start, end: ne) }
            } }
            .frame(width: w, height: clipH)
            .offset(x: CGFloat(s) * pps)
    }

    private func filmstrip(width: CGFloat, pps: CGFloat) -> some View {
        let frames = model.filmstrip
        return Canvas { ctx, size in
            guard let first = frames.first else { return }
            let aspect = CGFloat(first.width) / CGFloat(max(first.height, 1))
            let tileW = max(20, size.height * aspect)
            var x: CGFloat = 0
            while x < size.width {
                let t = Double((x + tileW / 2) / pps)
                let idx = clamp(Int(t / model.sourceDuration * Double(frames.count)), 0, frames.count - 1)
                ctx.draw(Image(decorative: frames[idx], scale: 1), in: CGRect(x: x, y: 0, width: tileW, height: size.height))
                x += tileW
            }
        }
        .opacity(0.55)
    }

    // MARK: Zooms

    private func zoomRange(_ z: ZoomSegment) -> (Double, Double) {
        if let d = drag, d.id == z.id { return (d.start, d.end) }
        return (z.start, z.end)
    }

    private func zoomTrack(width: CGFloat, pps: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(Theme.zoom.opacity(0.25))
                )
                .overlay(alignment: .leading) {
                    if model.doc.zooms.isEmpty {
                        Label("Click here to add a zoom", systemImage: "plus.magnifyingglass")
                            .font(.system(size: 11)).foregroundStyle(Theme.textFaint).padding(.leading, 10)
                    }
                }
                .frame(width: width, height: zoomH)
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { v in
                    model.addZoom(at: Double(v.location.x / pps))
                })

            ForEach(model.doc.zooms) { z in
                zoomBlock(z, pps: pps)
            }
        }
        .frame(width: width, height: zoomH, alignment: .topLeading)
    }

    private func zoomBlock(_ z: ZoomSegment, pps: CGFloat) -> some View {
        let (s, e) = zoomRange(z)
        let selected = model.selection == .zoom(z.id)
        let w = max(4, CGFloat(e - s) * pps)
        return RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(LinearGradient(colors: [Theme.zoom.opacity(selected ? 0.95 : 0.7), Theme.zoom.opacity(selected ? 0.75 : 0.5)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(selected ? 0.9 : 0.15), lineWidth: selected ? 1.5 : 1)
            )
            .overlay(alignment: .leading) {
                if w > 54 {
                    HStack(spacing: 4) {
                        Image(systemName: z.mode == .fixed ? "scope" : "cursorarrow.motionlines")
                            .font(.system(size: 10, weight: .semibold))
                        Text("\(z.scale, specifier: "%.1f")×").font(.system(size: 11, weight: .bold))
                        if w > 110 {
                            Text(z.isAuto ? "Auto" : "Manual").font(.system(size: 10)).opacity(0.75)
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.leading, 10)
                    .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                model.selection = .zoom(z.id)
            }
            .gesture(DragGesture(minimumDistance: 3).onChanged { v in
                model.selection = .zoom(z.id)
                let b = model.zoomBounds(z.id)
                let ns = clamp(z.start + Double(v.translation.width / pps), b.lowerBound, b.upperBound - z.duration)
                drag = DragState(id: z.id, kind: .zoomMove, start: ns, end: ns + z.duration)
            }.onEnded { _ in
                if let d = drag, d.id == z.id {
                    model.updateZoom(z.id) { $0.start = d.start; $0.end = d.end }
                }
                drag = nil
            })
            .overlay(alignment: .leading) { edgeHandle(color: .white, visible: selected) { dx, ended in
                let b = model.zoomBounds(z.id)
                let ns = clamp(z.start + Double(dx / pps), b.lowerBound, z.end - 0.4)
                if ended { drag = nil; model.updateZoom(z.id) { $0.start = ns } } else { drag = DragState(id: z.id, kind: .zoomLeft, start: ns, end: z.end) }
            } }
            .overlay(alignment: .trailing) { edgeHandle(color: .white, visible: selected) { dx, ended in
                let b = model.zoomBounds(z.id)
                let ne = clamp(z.end + Double(dx / pps), z.start + 0.4, b.upperBound)
                if ended { drag = nil; model.updateZoom(z.id) { $0.end = ne } } else { drag = DragState(id: z.id, kind: .zoomRight, start: z.start, end: ne) }
            } }
            .frame(width: w, height: zoomH)
            .offset(x: CGFloat(s) * pps)
    }

    // MARK: Effects

    /// Greedy row assignment so overlapping effects stack instead of covering each other.
    private func effectRows() -> [UUID: Int] {
        var rowEnds: [Double] = []
        var rows: [UUID: Int] = [:]
        for e in model.doc.effects.sorted(by: { $0.start < $1.start }) {
            let (s, en) = effectRange(e)
            if let r = rowEnds.firstIndex(where: { $0 <= s + 0.001 }) {
                rows[e.id] = r
                rowEnds[r] = en
            } else {
                rows[e.id] = rowEnds.count
                rowEnds.append(en)
            }
        }
        return rows
    }

    private func effectRange(_ e: EffectSegment) -> (Double, Double) {
        if let d = drag, d.id == e.id { return (d.start, d.end) }
        return (e.start, e.end)
    }

    static func effectColor(_ kind: EffectKind) -> Color {
        switch kind {
        case .blur: return Color(red: 0.25, green: 0.72, blue: 0.85)
        case .spotlight: return Color(red: 0.95, green: 0.78, blue: 0.25)
        case .text: return Color(red: 0.95, green: 0.42, blue: 0.62)
        case .hideCursor: return Color(red: 0.6, green: 0.6, blue: 0.66)
        case .cameraFull, .cameraHidden: return Color(red: 0.35, green: 0.8, blue: 0.5)
        }
    }

    private func effectTrack(width: CGFloat, pps: CGFloat, rows: [UUID: Int], height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(Color.white.opacity(0.12))
                )
                .overlay(alignment: .leading) {
                    if model.doc.effects.isEmpty {
                        Label("Effects: blur, spotlight, titles, hide cursor or camera. Add one with + Effect", systemImage: "sparkles")
                            .font(.system(size: 11)).foregroundStyle(Theme.textFaint).padding(.leading, 10)
                    }
                }
                .frame(width: width, height: height)
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { v in
                    model.selection = .none
                    model.seek(source: Double(v.location.x / pps))
                })

            ForEach(model.doc.effects) { e in
                effectBlock(e, pps: pps, row: rows[e.id] ?? 0)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }

    private func effectBlock(_ e: EffectSegment, pps: CGFloat, row: Int) -> some View {
        let (s, en) = effectRange(e)
        let selected = model.selection == .effect(e.id)
        let w = max(4, CGFloat(en - s) * pps)
        let color = TimelineView.effectColor(e.kind)
        let title = e.kind == .text ? e.text : e.kind.label
        return RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(color.opacity(selected ? 0.9 : 0.6))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.white.opacity(selected ? 0.9 : 0.15), lineWidth: selected ? 1.5 : 1)
            )
            .overlay(alignment: .leading) {
                if w > 30 {
                    HStack(spacing: 4) {
                        Image(systemName: e.kind.icon).font(.system(size: 10, weight: .semibold))
                        if w > 70 { Text(title).font(.system(size: 10.5, weight: .semibold)) }
                    }
                    .foregroundStyle(.black.opacity(0.8))
                    .padding(.leading, 8)
                    .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { model.selection = .effect(e.id) }
            .gesture(DragGesture(minimumDistance: 3).onChanged { v in
                model.selection = .effect(e.id)
                let ns = clamp(e.start + Double(v.translation.width / pps), 0, model.sourceDuration - e.duration)
                drag = DragState(id: e.id, kind: .effectMove, start: ns, end: ns + e.duration)
            }.onEnded { _ in
                if let d = drag, d.id == e.id {
                    model.updateEffect(e.id) { $0.start = d.start; $0.end = d.end }
                }
                drag = nil
            })
            .overlay(alignment: .leading) { edgeHandle(color: .white, visible: selected) { dx, ended in
                let ns = clamp(e.start + Double(dx / pps), 0, e.end - 0.3)
                if ended { drag = nil; model.updateEffect(e.id) { $0.start = ns } } else { drag = DragState(id: e.id, kind: .effectLeft, start: ns, end: e.end) }
            } }
            .overlay(alignment: .trailing) { edgeHandle(color: .white, visible: selected) { dx, ended in
                let ne = clamp(e.end + Double(dx / pps), e.start + 0.3, model.sourceDuration)
                if ended { drag = nil; model.updateEffect(e.id) { $0.end = ne } } else { drag = DragState(id: e.id, kind: .effectRight, start: e.start, end: ne) }
            } }
            .frame(width: w, height: effectRowH)
            .offset(x: CGFloat(s) * pps, y: 3 + CGFloat(row) * (effectRowH + 3))
    }

    // MARK: Shared

    private func edgeHandle(color: Color, visible: Bool, onDrag: @escaping (CGFloat, Bool) -> Void) -> some View {
        EdgeHandle(color: color, visible: visible, onDrag: onDrag)
    }

    private func playhead(pps: CGFloat, height: CGFloat) -> some View {
        let x = CGFloat(model.sourceTime) * pps
        return ZStack(alignment: .top) {
            Rectangle().fill(Color.white).frame(width: 2, height: height)
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .offset(y: -4)
        }
        .frame(width: 14, height: height)
        .offset(x: x - 7)
        .shadow(color: .black.opacity(0.6), radius: 3)
        .allowsHitTesting(false)
    }
}

private struct EdgeHandle: View {
    let color: Color
    let visible: Bool
    let onDrag: (CGFloat, Bool) -> Void
    @State private var hover = false

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(color.opacity(visible || hover ? 0.95 : 0))
            .frame(width: 6)
            .padding(.vertical, 8)
            .frame(width: 12)
            .contentShape(Rectangle())
            .onHover { inside in
                hover = inside
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { v in onDrag(v.translation.width, false) }
                .onEnded { v in onDrag(v.translation.width, true) })
    }
}
