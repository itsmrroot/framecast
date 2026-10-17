import SwiftUI
import AppKit

struct TimelineView: View {
    @ObservedObject var model: EditorModel
    @State private var zoomLevel: CGFloat = 1
    @State private var drag: DragState?
    @State private var newZoom: (Double, Double)?
    /// Pointer position over the clip lane (for the blade line) and the zoom lane (for the add-zoom ghost).
    @State private var clipHoverX: CGFloat?
    @State private var zoomHoverX: CGFloat?
    /// Pointer position anywhere over the timeline (hover pin and split line).
    @State private var hoverX: CGFloat?
    /// Scrolled down: the zoom lane shrinks to a thin strip, as in Screen Studio.
    @State private var compact = false
    @State private var hovering = false
    @State private var scrollTop = true
    @State private var scrollMonitor: Any?

    private var bladeActive: Bool { model.bladeMode || NSEvent.modifierFlags.contains(.option) }

    struct DragState {
        enum Kind { case clipLeft, clipRight, zoomMove, zoomLeft, zoomRight, effectMove, effectLeft, effectRight }
        var id: UUID
        var kind: Kind
        var start: Double
        var end: Double
    }

    private let rulerH: CGFloat = 24
    private let clipH: CGFloat = 60
    private var zoomH: CGFloat { compact ? 14 : 40 }
    private let effectRowH: CGFloat = 34
    private let gap: CGFloat = 8
    private let inset: CGFloat = 18

    var body: some View {
        let rows = effectRows()
        let rowCount = max(1, (rows.values.max() ?? -1) + 1)
        let effectsH = CGFloat(rowCount) * (effectRowH + 3) + 3
        let zoomY = rulerH + 6 + clipH + gap + (compact ? 14 : 0)
        let effectsY = zoomY + zoomH + gap
        let totalH = effectsY + effectsH + 8
        // The panel keeps its full height when the lanes compact, so the preview doesn't jump.
        let fullH = rulerH + 6 + clipH + gap + 40 + gap + effectsH + 8
        let spring = Animation.spring(response: 0.38, dampingFraction: 0.82)
        return VStack(spacing: 0) {
            header
            GeometryReader { geo in
                let contentW = max(200, (geo.size.width - inset * 2) * zoomLevel)
                // Edited time: cuts close up and speed changes shrink clips, so it matches the transport and export.
                let pps = contentW / CGFloat(max(map.duration, 0.01))
                ScrollView([.horizontal, .vertical], showsIndicators: zoomLevel > 1.01 || totalH > geo.size.height) {
                    ZStack(alignment: .topLeading) {
                        ruler(width: contentW, pps: pps)
                        clipTrack(width: contentW, pps: pps)
                            .offset(y: rulerH + 6)
                        zoomTrack(width: contentW, pps: pps)
                            .offset(y: zoomY)
                        effectTrack(width: contentW, pps: pps, rows: rows, height: effectsH)
                            .offset(y: effectsY)
                        if compact {
                            laneLabel("Zooms").offset(y: zoomY - 15)
                                .transition(.opacity)
                        }
                        if let x = hoverX, !bladeActive, drag == nil {
                            HoverPin(height: totalH - 4).offset(x: x - 7).allowsHitTesting(false)
                        }
                        playhead(pps: pps, height: totalH - 4)
                        if model.bladeMode {
                            // Split tool: a click anywhere cuts straight down through every lane.
                            Color.clear
                                .frame(width: contentW, height: totalH)
                                .contentShape(Rectangle())
                                .gesture(SpatialTapGesture().onEnded { v in model.cut(at: src(v.location.x, pps)) })
                        }
                        if bladeActive, let x = hoverX {
                            BladeLine(height: totalH - 4).offset(x: x - 13).allowsHitTesting(false)
                                .transition(.opacity)
                        }
                    }
                    .frame(width: contentW, height: totalH, alignment: .topLeading)
                    .onContinuousHover { phase in
                        if case .active(let p) = phase { hoverX = min(max(0, p.x), contentW) } else { hoverX = nil }
                    }
                    .padding(.horizontal, inset)
                    .padding(.top, 4)
                    .animation(spring, value: compact)
                    .animation(.easeOut(duration: 0.15), value: model.bladeMode)
                }
                .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y <= 1 } action: { _, top in scrollTop = top }
            }
        }
        // Grows with stacked effect lanes (up to a limit, then scrolls).
        .frame(height: min(max(38 + fullH + 8, 236), 380))
        .onHover { hovering = $0 }
        .onAppear(perform: installScrollMonitor)
        .onDisappear {
            if let m = scrollMonitor { NSEvent.removeMonitor(m) }
            scrollMonitor = nil
        }
    }

    /// Scrolling down over the timeline compacts the zoom lane; scrolling back up at the top restores it.
    private func installScrollMonitor() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { e in
            guard hovering, abs(e.scrollingDeltaY) > max(2, abs(e.scrollingDeltaX) * 1.5) else { return e }
            let down = e.scrollingDeltaY < 0
            if down && !compact {
                compact = true
            } else if !down && compact && scrollTop {
                compact = false
            }
            return e
        }
    }

    private func laneLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 10.5, weight: .medium)).foregroundStyle(Theme.textDim)
            .allowsHitTesting(false)
    }

    // MARK: Time mapping

    private var map: EditMap { model.editMap }

    /// x position of a source time on the edited-time timeline.
    private func cx(_ source: Double, _ pps: CGFloat) -> CGFloat { CGFloat(map.compTime(source: source)) * pps }

    /// Source time at an x position.
    private func src(_ x: CGFloat, _ pps: CGFloat) -> Double { map.sourceTime(comp: Double(max(0, x) / pps)) }

    /// A clip's span in edited time, following an edge drag in progress.
    private func clipSpan(_ c: Clip) -> (Double, Double) {
        let base = map.compTime(source: c.start)
        let (s, e) = clipRange(c)
        return (base + (s - c.start) / c.speed, base + (e - c.start) / c.speed)
    }

    /// Edited-time span of a zoom or effect; nearly zero when it lies entirely inside a cut.
    private func span(_ s: Double, _ e: Double) -> (Double, Double) {
        (map.compTime(source: s), map.compTime(source: e))
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            IconButton(icon: "scissors", label: "Split", help: "Split tool: click anywhere on the timeline to cut (S). C cuts at the playhead.",
                       tint: model.bladeMode ? Theme.accent : Theme.text, active: model.bladeMode) { model.bladeMode.toggle() }
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
            if !model.doc.flags.isEmpty {
                Menu {
                    ForEach(Array(model.doc.flags.sorted().enumerated()), id: \.offset) { i, f in
                        Button("Flag \(i + 1) at \(formatTime(f, fraction: true))") { model.seek(source: f) }
                    }
                } label: {
                    Label("\(model.doc.flags.count)", systemImage: "flag.fill")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Jump to a flag you marked while recording")
            }
            Image(systemName: "minus.magnifyingglass").font(.system(size: 11)).foregroundStyle(Theme.textDim)
            Slider(value: $zoomLevel, in: 1...12).controlSize(.mini).frame(width: 110).tint(Theme.accent)
                .help("Timeline zoom: about \(Int(model.duration / Double(zoomLevel))) seconds visible")
            Image(systemName: "plus.magnifyingglass").font(.system(size: 11)).foregroundStyle(Theme.textDim)
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
    }

    private var hint: String {
        if model.bladeMode { return "Click anywhere on the timeline to split · S or Esc to stop" }
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
        return steps.first { CGFloat($0) * pps >= 90 } ?? 600
    }

    private func ruler(width: CGFloat, pps: CGFloat) -> some View {
        let step = tickStep(pps)
        let duration = map.duration
        let map = map
        return Canvas { ctx, size in
            // Labels with a dot under each, and a dot halfway between (Screen Studio's ruler).
            var t = 0.0
            while t <= duration + 0.0001 {
                let x = CGFloat(t) * pps
                if t > 0 {
                    ctx.draw(Text(formatTime(t, fraction: step < 1)).font(.system(size: 10.5, weight: .medium).monospacedDigit())
                                .foregroundColor(Theme.textDim),
                             at: CGPoint(x: x, y: size.height - 13), anchor: .center)
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 1.5, y: size.height - 4, width: 3, height: 3)), with: .color(Theme.textFaint))
                }
                let mid = CGFloat(t + step / 2) * pps
                if mid < size.width {
                    ctx.fill(Path(ellipseIn: CGRect(x: mid - 1.5, y: size.height - 4, width: 3, height: 3)), with: .color(Theme.textFaint))
                }
                t += step
            }
            // Scissors badges at every cut or split, where one clip meets the next.
            for seg in map.segments.dropFirst() {
                let x = CGFloat(seg.compStart) * pps
                let pin = CGRect(x: x - 9, y: 0, width: 18, height: 18)
                ctx.fill(PinShape().path(in: pin.insetBy(dx: 0, dy: -2).offsetBy(dx: 0, dy: 2)), with: .color(Theme.clipPin))
                ctx.draw(Image(systemName: "scissors").resizable(), in: CGRect(x: x - 5, y: 4, width: 10, height: 9))
            }
            for f in model.doc.flags where map.isKept(source: f) {
                let x = CGFloat(map.compTime(source: f)) * pps
                var flag = Path()
                flag.move(to: CGPoint(x: x, y: 2)); flag.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(flag, with: .color(Theme.accent), lineWidth: 1.5)
                var pennant = Path()
                pennant.move(to: CGPoint(x: x, y: 2)); pennant.addLine(to: CGPoint(x: x + 9, y: 5.5)); pennant.addLine(to: CGPoint(x: x, y: 9))
                ctx.fill(pennant, with: .color(Theme.accent))
            }
        }
        .frame(width: width, height: rulerH)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { v in
            model.player.pause()
            model.seek(comp: min(map.duration, Double(max(0, v.location.x) / pps)))
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
                .fill(Theme.fill.opacity(0.025))
                .frame(width: width, height: clipH)
                .gesture(SpatialTapGesture().onEnded { v in
                    model.selection = .none
                    model.seek(source: src(v.location.x, pps))
                })

            filmstrip(width: width, pps: pps)
                .opacity(0.25)
                .frame(width: width, height: clipH)
                .mask(alignment: .topLeading) {
                    ZStack(alignment: .topLeading) {
                        ForEach(model.doc.clips) { c in
                            let (s, e) = clipSpan(c)
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

            if !model.waveform.isEmpty {
                waveform(width: width, pps: pps)
                    .frame(width: width, height: clipH)
                    .allowsHitTesting(false)
            }

            secondLines(width: width, pps: pps)
                .frame(width: width, height: clipH)
                .allowsHitTesting(false)
        }
        .frame(width: width, height: clipH, alignment: .topLeading)
        .onContinuousHover { phase in
            if case .active(let p) = phase { clipHoverX = p.x } else { clipHoverX = nil }
        }
    }

    private func clipBlock(_ c: Clip, pps: CGFloat) -> some View {
        let (s, e) = clipRange(c)
        let (cs, ce) = clipSpan(c)
        let selected = model.selection == .clip(c.id)
        let w = max(2, CGFloat(ce - cs) * pps)
        return RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(selected ? Theme.clipGradientSelected : Theme.clipGradient)
            .overlay(
                // A gold rim, brighter along the bottom, like light coming from below.
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? AnyShapeStyle(Color.white.opacity(0.9))
                                           : AnyShapeStyle(LinearGradient(colors: [Theme.clipRim.opacity(0.55), Theme.clipRim],
                                                                          startPoint: .top, endPoint: .bottom)),
                                  lineWidth: selected ? 2 : 1)
            )
            .shadow(color: Theme.clip.opacity(selected ? 0.4 : 0.12), radius: selected ? 8 : 3, y: 1)
            .overlay {
                if w > 60 {
                    VStack(spacing: 2) {
                        Text("Clip").font(.system(size: 11, weight: .medium)).opacity(0.32)
                        HStack(spacing: 4) {
                            Text(String(format: "%.1fs", (e - s) / c.speed)).font(.system(size: 12, weight: .semibold).monospacedDigit())
                            if w > 110 {
                                Image(systemName: "gauge.with.dots.needle.33percent").font(.system(size: 10.5, weight: .semibold))
                                Text("\(c.speed, specifier: "%g")×").font(.system(size: 12, weight: .semibold))
                            }
                        }
                        .fixedSize()
                    }
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                    .lineLimit(1)
                }
            }
            .opacity(isOtherClipSelected(c) ? 0.5 : 1)
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { v in
                let t = min(e, s + Double(v.location.x / pps) * c.speed)
                if bladeActive {
                    model.cut(at: t)
                } else {
                    model.selection = .clip(c.id)
                    model.seek(source: t)
                }
            })
            .overlay(alignment: .leading) { edgeHandle(color: Theme.clip, visible: selected) { dx, ended in
                let b = model.clipBounds(c.id)
                let ns = clamp(c.start + Double(dx / pps) * c.speed, b.lowerBound, c.end - 0.3)
                if ended { drag = nil; model.setClip(c.id, start: ns) } else { drag = DragState(id: c.id, kind: .clipLeft, start: ns, end: c.end) }
            } }
            .overlay(alignment: .trailing) { edgeHandle(color: Theme.clip, visible: selected) { dx, ended in
                let b = model.clipBounds(c.id)
                let ne = clamp(c.end + Double(dx / pps) * c.speed, c.start + 0.3, b.upperBound)
                if ended { drag = nil; model.setClip(c.id, end: ne) } else { drag = DragState(id: c.id, kind: .clipRight, start: c.start, end: ne) }
            } }
            .frame(width: w, height: clipH)
            .offset(x: CGFloat(cs) * pps)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(format: "Clip, %.1f seconds at %g×", (e - s) / c.speed, c.speed))
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func isOtherClipSelected(_ c: Clip) -> Bool {
        if case .clip(let id) = model.selection { return id != c.id }
        return false
    }

    /// Mirrored loudness bars along the bottom of the clip lane, only where footage is kept.
    private func waveform(width: CGFloat, pps: CGFloat) -> some View {
        let peaks = model.waveform
        let map = map
        let total = model.sourceDuration
        return Canvas { ctx, size in
            let n = peaks.count
            guard n > 1 else { return }
            let mid = size.height - 16
            let step: CGFloat = 3
            var x: CGFloat = 0
            var path = Path()
            while x < size.width {
                let t = map.sourceTime(comp: Double(x / pps))
                let i = min(n - 1, max(0, Int(t / total * Double(n))))
                if peaks[i] > 0.06 { // keep quiet stretches clean
                    let h = CGFloat(peaks[i]) * 14
                    path.addRoundedRect(in: CGRect(x: x, y: mid - h, width: 1.6, height: h * 2), cornerSize: CGSize(width: 0.8, height: 0.8))
                }
                x += step
            }
            ctx.fill(path, with: .color(Color.white.opacity(0.3)))
        }
    }

    private func filmstrip(width: CGFloat, pps: CGFloat) -> some View {
        let frames = model.filmstrip
        let map = map
        return Canvas { ctx, size in
            guard let first = frames.first else { return }
            let aspect = CGFloat(first.width) / CGFloat(max(first.height, 1))
            let tileW = max(20, size.height * aspect)
            var x: CGFloat = 0
            while x < size.width {
                let t = map.sourceTime(comp: Double((x + tileW / 2) / pps))
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
                .fill(Theme.fill.opacity(0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(Theme.zoom.opacity(0.25))
                )
                .overlay {
                    if model.doc.zooms.isEmpty && newZoom == nil {
                        Text("Click or drag to add zoom on cursor")
                            .font(.system(size: 12)).foregroundStyle(Theme.textDim)
                    }
                }
                .overlay(alignment: .leading) {
                    if let (a, b) = newZoom {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Theme.zoom.opacity(0.45))
                            .frame(width: max(4, abs(cx(b, pps) - cx(a, pps))), height: zoomH)
                            .offset(x: min(cx(a, pps), cx(b, pps)))
                    }
                }
                .overlay(alignment: .leading) {
                    if newZoom == nil, let x = zoomHoverX, let (a, b) = ghostZoom(at: src(x, pps)) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Theme.zoom.opacity(0.28))
                            .overlay(Image(systemName: "plus").font(.system(size: 12, weight: .bold)).foregroundStyle(.white))
                            .frame(width: max(4, cx(b, pps) - cx(a, pps)), height: zoomH)
                            .offset(x: cx(a, pps))
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: width, height: zoomH)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    if case .active(let p) = phase { zoomHoverX = p.x } else { zoomHoverX = nil }
                }
                .gesture(DragGesture(minimumDistance: 4)
                    .onChanged { v in
                        newZoom = (src(v.startLocation.x, pps), src(v.location.x, pps))
                    }
                    .onEnded { _ in
                        if let (a, b) = newZoom { model.addZoom(from: a, to: b) }
                        newZoom = nil
                    }
                    .exclusively(before: SpatialTapGesture().onEnded { v in
                        model.addZoom(at: src(v.location.x, pps))
                    }))

            ForEach(model.doc.zooms) { z in
                let (a, b) = zoomRange(z)
                if map.compTime(source: b) - map.compTime(source: a) > 0.02 { // hidden while entirely inside a cut
                    zoomBlock(z, pps: pps)
                }
            }
        }
        .frame(width: width, height: zoomH, alignment: .topLeading)
    }

    /// The zoom a click would add here: 3 s, or up to the next zoom.
    private func ghostZoom(at t: Double) -> (Double, Double)? {
        let sorted = model.doc.zooms.sorted { $0.start < $1.start }
        if sorted.contains(where: { t >= $0.start && t <= $0.end }) { return nil }
        let next = sorted.first { $0.start > t }?.start ?? model.sourceDuration
        let end = min(t + 3, next - 0.05, model.sourceDuration)
        return end - t >= 0.6 ? (t, end) : nil
    }

    private func zoomBlock(_ z: ZoomSegment, pps: CGFloat) -> some View {
        let (s, e) = zoomRange(z)
        let (cs, ce) = span(s, e)
        let selected = model.selection == .zoom(z.id)
        let w = max(4, CGFloat(ce - cs) * pps)
        let radius: CGFloat = compact ? 7 : 10
        return RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(selected ? Theme.zoomGradientSelected : Theme.zoomGradient)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(selected ? Theme.zoomRim : Theme.zoomRim.opacity(0.28), lineWidth: selected ? 2 : 1)
            )
            // Selected: a second, outer ring, as Screen Studio draws it.
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: radius + 3, style: .continuous)
                        .strokeBorder(Theme.zoomRim.opacity(0.55), lineWidth: 1)
                        .padding(-3)
                }
            }
            .shadow(color: Theme.zoom.opacity(selected ? 0.55 : 0.15), radius: selected ? 10 : 3, y: 1)
            .opacity(model.doc.style.zoomsDisabled ? 0.4 : 1)
            .overlay {
                if w > 54 && !compact {
                    VStack(spacing: 1) {
                        if w > 90 {
                            Text(z.instant ? "Instant zoom" : (z.isAuto ? "Auto zoom" : "Zoom"))
                                .font(.system(size: 10, weight: .medium)).opacity(0.5)
                        }
                        HStack(spacing: 4) {
                            Image(systemName: "plus.magnifyingglass").font(.system(size: 9.5, weight: .semibold))
                            Text("\(z.scale, specifier: "%.1f")×").font(.system(size: 11, weight: .bold))
                            if w > 110 {
                                Text("·").opacity(0.6)
                                Image(systemName: z.mode == .fixed ? "scope" : "cursorarrow.motionlines").font(.system(size: 9.5))
                                Text(z.mode == .fixed ? "Manual" : "Auto").font(.system(size: 10.5, weight: .semibold))
                            }
                        }
                    }
                    .foregroundStyle(.white.opacity(selected ? 1 : 0.62))
                    .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                model.selection = .zoom(z.id)
            }
            .gesture(DragGesture(minimumDistance: 3).onChanged { v in
                model.selection = .zoom(z.id)
                let (ns, ne) = moved(z.start, z.end, by: v.translation.width, pps: pps, within: model.zoomBounds(z.id))
                drag = DragState(id: z.id, kind: .zoomMove, start: ns, end: ne)
            }.onEnded { _ in
                if let d = drag, d.id == z.id {
                    model.updateZoom(z.id) { $0.start = d.start; $0.end = d.end }
                }
                drag = nil
            })
            .overlay(alignment: .leading) { edgeHandle(color: .white, visible: selected) { dx, ended in
                let b = model.zoomBounds(z.id)
                let ns = clamp(map.sourceTime(comp: map.compTime(source: z.start) + Double(dx / pps)), b.lowerBound, z.end - 0.4)
                if ended { drag = nil; model.updateZoom(z.id) { $0.start = ns } } else { drag = DragState(id: z.id, kind: .zoomLeft, start: ns, end: z.end) }
            } }
            .overlay(alignment: .trailing) { edgeHandle(color: .white, visible: selected) { dx, ended in
                let b = model.zoomBounds(z.id)
                let ne = clamp(map.sourceTime(comp: map.compTime(source: z.end) + Double(dx / pps)), z.start + 0.4, b.upperBound)
                if ended { drag = nil; model.updateZoom(z.id) { $0.end = ne } } else { drag = DragState(id: z.id, kind: .zoomRight, start: z.start, end: ne) }
            } }
            .frame(width: w, height: zoomH)
            .offset(x: CGFloat(cs) * pps)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(format: "Zoom %.1f×", z.scale))
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    /// Moves a source range by a drag in edited time, keeping its edited length and staying within `bounds` (source).
    private func moved(_ start: Double, _ end: Double, by dx: CGFloat, pps: CGFloat, within bounds: ClosedRange<Double>) -> (Double, Double) {
        let cs = map.compTime(source: start), len = map.compTime(source: end) - cs
        let lo = map.compTime(source: bounds.lowerBound), hi = map.compTime(source: bounds.upperBound)
        let ncs = clamp(cs + Double(dx / pps), lo, max(lo, hi - len))
        return (max(bounds.lowerBound, map.sourceTime(comp: ncs)), min(bounds.upperBound, map.sourceTime(comp: ncs + len)))
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

    /// Dark text on the light yellow spotlight, white on the rest.
    static func effectLabelColor(_ kind: EffectKind) -> Color {
        kind == .spotlight ? Color.black.opacity(0.8) : .white
    }

    private func effectTrack(width: CGFloat, pps: CGFloat, rows: [UUID: Int], height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.fill.opacity(0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(Theme.fill.opacity(0.12))
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
                    model.seek(source: src(v.location.x, pps))
                })

            ForEach(model.doc.effects) { e in
                let (a, b) = effectRange(e)
                if map.compTime(source: b) - map.compTime(source: a) > 0.02 {
                    effectBlock(e, pps: pps, row: rows[e.id] ?? 0)
                }
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }

    private func effectBlock(_ e: EffectSegment, pps: CGFloat, row: Int) -> some View {
        let (s, en) = effectRange(e)
        let (cs, ce) = span(s, en)
        let selected = model.selection == .effect(e.id)
        let w = max(4, CGFloat(ce - cs) * pps)
        let color = TimelineView.effectColor(e.kind)
        let title = e.kind == .text ? e.text : e.kind.label
        return effectFace(e, selected: selected, w: w, color: color, title: title)
            .contentShape(Rectangle())
            .onTapGesture {
                model.selection = .effect(e.id)
                // Show the effect: move the playhead into it if it's elsewhere.
                if model.sourceTime < e.start || model.sourceTime > e.end {
                    model.player.pause()
                    model.seek(source: e.start + min(0.3, e.duration / 2))
                }
            }
            .gesture(DragGesture(minimumDistance: 3).onChanged { v in
                model.selection = .effect(e.id)
                let (ns, ne) = moved(e.start, e.end, by: v.translation.width, pps: pps, within: 0...model.sourceDuration)
                drag = DragState(id: e.id, kind: .effectMove, start: ns, end: ne)
            }.onEnded { _ in
                if let d = drag, d.id == e.id {
                    model.updateEffect(e.id) { $0.start = d.start; $0.end = d.end }
                }
                drag = nil
            })
            .overlay(alignment: .leading) { edgeHandle(color: .white, visible: selected) { dx, ended in
                let ns = clamp(map.sourceTime(comp: map.compTime(source: e.start) + Double(dx / pps)), 0, e.end - 0.3)
                if ended { drag = nil; model.updateEffect(e.id) { $0.start = ns } } else { drag = DragState(id: e.id, kind: .effectLeft, start: ns, end: e.end) }
            } }
            .overlay(alignment: .trailing) { edgeHandle(color: .white, visible: selected) { dx, ended in
                let ne = clamp(map.sourceTime(comp: map.compTime(source: e.end) + Double(dx / pps)), e.start + 0.3, model.sourceDuration)
                if ended { drag = nil; model.updateEffect(e.id) { $0.end = ne } } else { drag = DragState(id: e.id, kind: .effectRight, start: e.start, end: ne) }
            } }
            .frame(width: w, height: effectRowH)
            .offset(x: CGFloat(cs) * pps, y: 3 + CGFloat(row) * (effectRowH + 3))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(e.kind.label) effect\(e.kind == .text && !e.text.isEmpty ? ": \(e.text)" : "")")
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func effectFace(_ e: EffectSegment, selected: Bool, w: CGFloat, color: Color, title: String) -> some View {
        return RoundedRectangle(cornerRadius: 9, style: .continuous)
            // Deep, opaque fills lit from below with a lighter rim (labels stay readable in light mode too).
            .fill(LinearGradient(colors: [color.mix(with: .black, by: selected ? 0.32 : 0.45), color.mix(with: .black, by: selected ? 0.18 : 0.32)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(selected ? Color.white.opacity(0.9) : color.opacity(0.75), lineWidth: selected ? 2 : 1)
            )
            .shadow(color: color.opacity(selected ? 0.45 : 0.12), radius: selected ? 8 : 3, y: 1)
            .opacity(e.disabled ? 0.4 : 1)
            .overlay {
                if w > 30 {
                    VStack(spacing: 1) {
                        if w > 90 && title != e.kind.label { Text(e.kind.label).font(.system(size: 10, weight: .medium)).opacity(0.38) }
                        HStack(spacing: 4) {
                            Image(systemName: e.disabled ? "eye.slash" : e.kind.icon).font(.system(size: 10, weight: .semibold))
                            if w > 70 { Text(title).font(.system(size: 11.5, weight: .semibold)) }
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .lineLimit(1)
                }
            }
    }

    // MARK: Shared

    private func edgeHandle(color: Color, visible: Bool, onDrag: @escaping (CGFloat, Bool) -> Void) -> some View {
        EdgeHandle(color: color, visible: visible, onDrag: onDrag)
    }

    private func playhead(pps: CGFloat, height: CGFloat) -> some View {
        let x = CGFloat(model.compTime) * pps
        return ZStack(alignment: .top) {
            Rectangle().fill(Theme.playhead).frame(width: 1.5, height: height)
            Circle().fill(Theme.playhead).frame(width: 13, height: 13)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.25)))
                .offset(y: -3)
        }
        .frame(width: 14, height: height)
        .offset(x: x - 7)
        .shadow(color: Theme.playhead.opacity(0.6), radius: 4)
        .allowsHitTesting(false)
    }

    /// Faint lines through the clips at each labelled second.
    private func secondLines(width: CGFloat, pps: CGFloat) -> some View {
        let step = tickStep(pps)
        let duration = map.duration
        return Canvas { ctx, size in
            var t = step
            while t < duration {
                let x = CGFloat(t) * pps
                ctx.fill(Path(CGRect(x: x, y: 6, width: 1, height: size.height - 12)), with: .color(Color.white.opacity(0.1)))
                t += step
            }
        }
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
            .onHover { hover = $0 }
            .pointerStyle(.frameResize(position: .trailing, directions: [.inward, .outward]))
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { v in onDrag(v.translation.width, false) }
                .onEnded { v in onDrag(v.translation.width, true) })
    }
}

/// A map-pin shape: a circle with a point at the bottom.
struct PinShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let d = r.width
        let c = CGPoint(x: r.midX, y: r.minY + d / 2)
        p.addArc(center: c, radius: d / 2, startAngle: .degrees(140), endAngle: .degrees(40), clockwise: false)
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// Where the pointer is on the timeline: a dim pin and line.
private struct HoverPin: View {
    let height: CGFloat
    var body: some View {
        ZStack(alignment: .top) {
            Rectangle().fill(Theme.fill.opacity(0.18)).frame(width: 1, height: height)
            PinShape().fill(Theme.hoverPin).frame(width: 12, height: 15).offset(y: -3)
        }
        .frame(width: 14, height: height)
    }
}

/// The split tool's cut line: red, through every lane, with a scissors pin in the ruler.
private struct BladeLine: View {
    let height: CGFloat
    var body: some View {
        ZStack(alignment: .top) {
            Rectangle().fill(Theme.blade).frame(width: 1.5, height: height)
            PinShape().fill(Theme.clipPin).frame(width: 24, height: 30)
                .overlay(Image(systemName: "scissors").font(.system(size: 10, weight: .bold)).foregroundStyle(.black.opacity(0.8)).offset(y: -3))
                .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                .offset(y: -6)
        }
        .frame(width: 26, height: height)
    }
}
