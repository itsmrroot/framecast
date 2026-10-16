import Foundation

/// Maps between source-recording time and edited ("composition") time, given the kept clips.
struct EditMap {
    struct Segment {
        var srcStart: Double
        var srcEnd: Double
        var speed: Double
        var compStart: Double
        var compDuration: Double { (srcEnd - srcStart) / speed }
        var compEnd: Double { compStart + compDuration }
    }

    let segments: [Segment]
    let duration: Double

    init(clips: [Clip]) {
        var t = 0.0
        var segs: [Segment] = []
        for c in clips.sorted(by: { $0.start < $1.start }) where c.end - c.start > 0.01 {
            let s = Segment(srcStart: c.start, srcEnd: c.end, speed: max(0.1, c.speed), compStart: t)
            segs.append(s)
            t += s.compDuration
        }
        segments = segs
        duration = t
    }

    func sourceTime(comp: Double) -> Double {
        guard let last = segments.last else { return comp }
        for s in segments where comp < s.compEnd {
            return s.srcStart + max(0, comp - s.compStart) * s.speed
        }
        return last.srcEnd
    }

    /// Source times inside a cut snap to the start of the next kept clip.
    func compTime(source: Double) -> Double {
        for s in segments {
            if source < s.srcStart { return s.compStart }
            if source <= s.srcEnd { return s.compStart + (source - s.srcStart) / s.speed }
        }
        return duration
    }

    func isKept(source: Double) -> Bool {
        segments.contains { source >= $0.srcStart && source <= $0.srcEnd }
    }
}

enum ZoomGenerator {
    /// Builds zoom segments around clusters of clicks, like Screen Studio's automatic zoom.
    static func generate(from clicks: [ClickEvent], duration: Double, scale: Double) -> [ZoomSegment] {
        let times = clicks.filter { $0.button == 0 }.map(\.t).sorted()
        guard !times.isEmpty else { return [] }

        var groups: [(Double, Double)] = []
        for t in times {
            if let last = groups.last, t - last.1 < 3.0 {
                groups[groups.count - 1].1 = t
            } else {
                groups.append((t, t))
            }
        }

        var segs: [ZoomSegment] = []
        for (first, last) in groups {
            var start = max(0, first - 0.6)
            var end = min(duration, last + 2.6)
            if end - start < 2.0 { end = min(duration, start + 2.0) }
            if let prev = segs.last, start - prev.end < 1.2 {
                segs[segs.count - 1].end = end
                continue
            }
            if end - start < 1.0 { start = max(0, end - 1.0) }
            segs.append(ZoomSegment(start: start, end: end, scale: scale, mode: .followCursor, isAuto: true))
        }
        return segs
    }
}
