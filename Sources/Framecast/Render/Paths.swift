import Foundation
import CoreGraphics

/// Smoothed cursor path, precomputed at a fixed rate so any time can be sampled cheaply.
final class CursorPath {
    let rate = 120.0
    private let xs: [Float]
    private let ys: [Float]
    private let alpha: [Float]
    let hasData: Bool

    struct State {
        var position: CGPoint   // normalised, top-left origin
        var velocity: CGVector  // normalised units / second
        var opacity: Double
    }

    /// - Parameters:
    ///   - shakeThreshold: drop tiny jitter (0…1), nil to keep every movement.
    ///   - freezeFrom: hold the cursor still from this source time on.
    ///   - loop: ease back to the position at `home` between `from` and `until` (source times).
    init(track: CursorTrack, duration: Double, smoothing: Double, hideWhenIdle: Bool,
         shakeThreshold: Double? = nil, freezeFrom: Double? = nil, loop: (home: Double, from: Double, until: Double)? = nil) {
        var samples = track.samples
        if let threshold = shakeThreshold, threshold > 0, samples.count > 2 {
            // Keep a sample only once it has moved far enough from the last kept one; trackpad noise and
            // small back-and-forth shakes never get that far, deliberate movement does.
            let eps = threshold * 0.006
            var kept = [samples[0]]
            for s in samples.dropFirst() {
                let last = kept[kept.count - 1]
                if hypot(s.x - last.x, s.y - last.y) >= eps { kept.append(s) }
            }
            if let lastRaw = samples.last, kept.last?.t != lastRaw.t,
               let k = kept.last, hypot(lastRaw.x - k.x, lastRaw.y - k.y) >= eps / 3 {
                kept.append(lastRaw)
            }
            samples = kept
        }
        hasData = !samples.isEmpty
        let n = max(2, Int(duration * rate) + 2)
        var xs = [Float](repeating: 0.5, count: n)
        var ys = [Float](repeating: 0.5, count: n)
        var alpha = [Float](repeating: 1, count: n)
        guard hasData else {
            self.xs = xs; self.ys = ys; self.alpha = alpha
            return
        }

        let clickTimes = track.clicks.map(\.t)
        let omega = lerp(34, 7, clamp(smoothing, 0, 1))
        let dt = 1.0 / rate
        var j = 0
        var px = samples[0].x, py = samples[0].y
        var vx = 0.0, vy = 0.0
        var lastMove = samples[0].t
        var ci = 0

        for i in 0..<n {
            let t = Double(i) * dt
            while j + 1 < samples.count && samples[j + 1].t <= t {
                j += 1
                lastMove = samples[j].t
            }
            while ci < clickTimes.count && clickTimes[ci] <= t {
                lastMove = max(lastMove, clickTimes[ci])
                ci += 1
            }
            // raw position, linearly interpolated between samples
            var rx = samples[j].x, ry = samples[j].y
            if j + 1 < samples.count, samples[j].t <= t {
                let a = samples[j], b = samples[j + 1]
                // Only interpolate when the gap is short (otherwise the cursor was stationary).
                if b.t - a.t < 0.1 {
                    let f = (t - a.t) / max(b.t - a.t, 1e-6)
                    rx = a.x + (b.x - a.x) * f
                    ry = a.y + (b.y - a.y) * f
                }
            }
            if smoothing < 0.02 {
                px = rx; py = ry
            } else {
                let ax = omega * omega * (rx - px) - 2 * omega * vx
                let ay = omega * omega * (ry - py) - 2 * omega * vy
                vx += ax * dt; vy += ay * dt
                px += vx * dt; py += vy * dt
            }
            xs[i] = Float(px)
            ys[i] = Float(py)
            if hideWhenIdle {
                let idle = t - lastMove
                alpha[i] = Float(idle < 2.0 ? 1 : max(0, 1 - (idle - 2.0) / 0.35))
            }
        }
        if let loop, loop.until > loop.from {
            let home = clamp(Int(loop.home * rate), 0, n - 1)
            let hx = xs[home], hy = ys[home]
            for i in clamp(Int(loop.from * rate), 0, n - 1)..<n {
                let w = Float(smootherstep((Double(i) / rate - loop.from) / (loop.until - loop.from)))
                xs[i] += (hx - xs[i]) * w
                ys[i] += (hy - ys[i]) * w
            }
        }
        if let freezeFrom {
            let f = clamp(Int(freezeFrom * rate), 0, n - 1)
            for i in f..<n { xs[i] = xs[f]; ys[i] = ys[f] }
        }
        self.xs = xs
        self.ys = ys
        self.alpha = alpha
    }

    func state(at t: Double) -> State {
        let f = max(0, t * rate)
        let i = min(Int(f), xs.count - 2)
        let w = Float(min(1, f - Double(i)))
        let x = xs[i] + (xs[i + 1] - xs[i]) * w
        let y = ys[i] + (ys[i + 1] - ys[i]) * w
        let vx = Double(xs[i + 1] - xs[i]) * rate
        let vy = Double(ys[i + 1] - ys[i]) * rate
        let a = alpha[i] + (alpha[i + 1] - alpha[i]) * w
        return State(position: CGPoint(x: Double(x), y: Double(y)), velocity: CGVector(dx: vx, dy: vy), opacity: Double(a))
    }
}

/// Precomputed "virtual camera": zoom scale and focus point over time (source time).
final class CameraPath {
    let rate = 60.0
    private let scales: [Float]
    private let cx: [Float]
    private let cy: [Float]

    struct State {
        var scale: Double
        var focus: CGPoint // normalised, top-left origin
    }

    /// - Parameter viewHalfExtent: half the canvas size divided by the screen size, at zoom 1
    ///   (i.e. how much of the screen, in normalised units, half the frame shows).
    init(zooms: [ZoomSegment], cursor: CursorPath?, duration: Double, transition: Double, viewHalfExtent: CGSize,
         animation: ScreenAnimation = .smooth, startEarly: Bool = false) {
        let n = max(2, Int(duration * rate) + 2)
        var scales = [Float](repeating: 1, count: n)
        var cx = [Float](repeating: 0.5, count: n)
        var cy = [Float](repeating: 0.5, count: n)
        let sorted = zooms.sorted { $0.start < $1.start }
        let dt = 1.0 / rate
        // Focused: a stiffer, quicker camera. Smooth: a little floatier, but never slow.
        let omega = animation == .focused ? 12.0 : 8.5
        let transition = animation == .focused ? transition * 0.7 : transition

        var c = CGPoint(x: 0.5, y: 0.5)
        var v = CGVector.zero
        // While a zoom ramps in, the focus glides with the scale (one motion) from where it was.
        var rampFor: UUID?
        var rampFrom = CGPoint(x: 0.5, y: 0.5)

        func cursorAt(_ t: Double) -> CGPoint {
            guard let cursor, cursor.hasData else { return CGPoint(x: 0.5, y: 0.5) }
            return cursor.state(at: t).position
        }

        for i in 0..<n {
            let t = Double(i) * dt
            var best = 1.0
            var active: ZoomSegment?
            var rampEnd = 0.0
            var activeIn = 1.0
            for z in sorted {
                let T = z.instant ? 0 : max(0.05, min(transition, z.duration / 2))
                // "Start animation early": the zoom-in finishes as the block starts instead of after it.
                let inStart = startEarly ? z.start - T : z.start
                guard t >= inStart && t <= z.end else { continue }
                // Spring-shaped: quick to get going, gentle to land, both in and out.
                let pIn = T > 0 ? springEase((t - inStart) / T) : 1
                let pOut = T > 0 ? 1 - springEase((t - (z.end - T)) / T) : 1
                // Interpolate in log space so the zoom feels linear.
                let s = exp(log(max(1, z.scale)) * min(pIn, t > z.end - T ? pOut : 1))
                if s >= best {
                    best = s
                    active = z
                    rampEnd = inStart + T
                    activeIn = pIn
                }
            }

            var desired: CGPoint
            if let z = active, z.mode == .fixed {
                desired = CGPoint(x: z.focusX, y: z.focusY)
            } else if active != nil, t < rampEnd {
                // While zooming in, aim at where the cursor will be once the zoom settles.
                desired = cursorAt(rampEnd)
            } else {
                // A little lookahead so following pans move with the cursor instead of trailing it.
                desired = cursorAt(t + 0.08)
            }

            if best <= 1.001 || (active?.instant == true && t < (active?.start ?? 0) + 2 * dt) {
                // At rest (or cutting straight into an instant zoom) the camera sits on its target.
                c = desired
                v = .zero
                rampFor = nil
            } else if let z = active, t < rampEnd {
                // Zooming in: focus and scale move as one, on the same curve, so nothing drifts afterwards.
                if rampFor != z.id { rampFor = z.id; rampFrom = c }
                c = CGPoint(x: rampFrom.x + (desired.x - rampFrom.x) * activeIn, y: rampFrom.y + (desired.y - rampFrom.y) * activeIn)
                v = .zero
            } else {
                var target = desired
                if let z = active, z.mode == .followCursor {
                    // Soft dead zone: the camera only pans once the cursor nears the edge of the visible area.
                    let hx = viewHalfExtent.width / best * 0.38
                    let hy = viewHalfExtent.height / best * 0.38
                    target.x = desired.x - clamp(desired.x - c.x, -hx, hx)
                    target.y = desired.y - clamp(desired.y - c.y, -hy, hy)
                }
                let ax = omega * omega * (target.x - c.x) - 2 * omega * v.dx
                let ay = omega * omega * (target.y - c.y) - 2 * omega * v.dy
                v.dx += ax * dt; v.dy += ay * dt
                // Stop the spring's last sub-pixel creep, which shows as shimmering text.
                if abs(v.dx) < 1e-4 && abs(target.x - c.x) < 1e-4 { v.dx = 0 }
                if abs(v.dy) < 1e-4 && abs(target.y - c.y) < 1e-4 { v.dy = 0 }
                c.x += v.dx * dt; c.y += v.dy * dt
            }
            scales[i] = Float(best)
            cx[i] = Float(c.x)
            cy[i] = Float(c.y)
        }
        self.scales = scales
        self.cx = cx
        self.cy = cy
    }

    func state(at t: Double) -> State {
        let f = max(0, t * rate)
        let i = min(Int(f), scales.count - 2)
        let w = Float(min(1, f - Double(i)))
        let s = scales[i] + (scales[i + 1] - scales[i]) * w
        let x = cx[i] + (cx[i + 1] - cx[i]) * w
        let y = cy[i] + (cy[i + 1] - cy[i]) * w
        return State(scale: Double(s), focus: CGPoint(x: Double(x), y: Double(y)))
    }
}
