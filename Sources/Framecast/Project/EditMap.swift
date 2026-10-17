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

/// Finds stretches of a recording worth speeding up or cutting.
enum ActivityAnalyzer {
    /// Quiet stretches with no cursor movement, clicks or key presses, trimmed by a small margin
    /// so the moments before and after stay at normal speed.
    static func idleRanges(cursor: CursorTrack, keys: [KeyEvent], duration: Double,
                           minIdle: Double = 2.5, margin: Double = 0.4) -> [(Double, Double)] {
        var activity: [Double] = []
        var last: CursorSample?
        for s in cursor.samples {
            if let l = last, hypot(s.x - l.x, s.y - l.y) < 0.002 { continue }
            activity.append(s.t)
            last = s
        }
        activity += cursor.clicks.map(\.t)
        activity += keys.map(\.t)
        guard !activity.isEmpty else { return [] }
        activity.sort()

        var ranges: [(Double, Double)] = []
        var prev = 0.0
        for t in activity + [duration] {
            let a = prev == 0 ? 0 : prev + margin
            let b = t >= duration ? duration : t - margin
            if t - prev >= minIdle, b - a >= 1.0 { ranges.append((a, b)) }
            prev = t
        }
        return ranges
    }

    /// Pauses in the audio: at least `minLength` seconds below `threshold`, trimmed by `margin` so words aren't clipped.
    /// With `threshold` nil, it's set between the room's noise floor and the speech level, so ordinary
    /// background noise counts as silence.
    static func silentRanges(waveform: [Float], duration: Double, threshold fixed: Float? = 0.05,
                             minLength: Double = 0.9, margin: Double = 0.2) -> [(Double, Double)] {
        guard waveform.count > 1, duration > 0 else { return [] }
        let threshold: Float
        if let fixed {
            threshold = fixed
        } else {
            let sorted = waveform.sorted()
            let floor = sorted[Int(Double(sorted.count - 1) * 0.1)]
            let speech = sorted[Int(Double(sorted.count - 1) * 0.9)]
            guard speech - floor > 0.08 else { return [] } // no clear difference between talking and not
            threshold = floor + (speech - floor) * 0.3
        }
        let binDur = duration / Double(waveform.count)
        var ranges: [(Double, Double)] = []
        var start: Int?
        for (i, p) in (waveform + [1]).enumerated() {
            if p < threshold {
                if start == nil { start = i }
            } else if let s = start {
                let a = Double(s) * binDur, b = min(duration, Double(i) * binDur)
                let lo = s == 0 ? 0 : a + margin, hi = i >= waveform.count ? duration : b - margin
                if b - a >= minLength, hi - lo >= 0.5 { ranges.append((lo, hi)) }
                start = nil
            }
        }
        return ranges
    }

    /// Bursts of plain typing (no shortcuts), at least `minLength` seconds long.
    static func typingRanges(keys: [KeyEvent], maxGap: Double = 1.2, minLength: Double = 1.5) -> [(Double, Double)] {
        let typed = keys.filter { !$0.isShortcut || $0.label == "⌫" }.map(\.t).sorted()
        var ranges: [(Double, Double)] = []
        var start: Double?
        var prev = 0.0
        for t in typed {
            if let s = start, t - prev > maxGap {
                if prev - s >= minLength { ranges.append((s + 0.2, prev)) }
                start = t
            } else if start == nil {
                start = t
            }
            prev = t
        }
        if let s = start, prev - s >= minLength { ranges.append((s + 0.2, prev)) }
        return ranges
    }
}

enum ClipOps {
    /// Splits clips at the range edges and sets the speed inside the ranges (or removes them when `speed` is nil).
    /// Always keeps at least one clip.
    static func apply(_ ranges: [(Double, Double)], to clips: [Clip], speed: Double?) -> [Clip] {
        // Pieces shorter than this are nearly impossible to select on the timeline, so they're absorbed.
        let minPiece = 0.5
        var merged: [(Double, Double)] = []
        for r in ranges.sorted(by: { $0.0 < $1.0 }) {
            if let last = merged.last, r.0 - last.1 < minPiece {
                merged[merged.count - 1].1 = max(last.1, r.1)
            } else {
                merged.append(r)
            }
        }
        let ranges = merged
        var result: [Clip] = []
        for clip in clips.sorted(by: { $0.start < $1.start }) {
            var pieces: [Clip] = []
            var cursor = clip.start
            for (a, b) in ranges.sorted(by: { $0.0 < $1.0 }) {
                var s = max(a, clip.start), e = min(b, clip.end)
                guard e - s >= minPiece else { continue }
                // Never leave slivers of footage behind: absorb short gaps into the range.
                if s - cursor < minPiece { s = cursor }
                if clip.end - e < minPiece { e = clip.end }
                if s - cursor > 0.001 {
                    var before = clip
                    before.id = pieces.isEmpty ? clip.id : UUID()
                    before.start = cursor
                    before.end = s
                    pieces.append(before)
                }
                if let speed {
                    var inside = clip
                    inside.id = UUID()
                    inside.start = s
                    inside.end = e
                    inside.speed = speed
                    pieces.append(inside)
                }
                cursor = e
            }
            if clip.end - cursor > 0.001 {
                var after = clip
                after.id = pieces.isEmpty ? clip.id : UUID()
                after.start = cursor
                pieces.append(after)
            }
            result += pieces
        }
        return result.isEmpty ? clips : result
    }
}
