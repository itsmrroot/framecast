import Foundation
import CoreMedia

/// One clock shared by every recorder (screen, audio, camera, cursor) so all files line up at t = 0,
/// with pauses removed from the timeline.
final class RecordingClock: @unchecked Sendable {
    enum State { case idle, recording, paused, stopped }

    private let lock = NSLock()
    private var _state: State = .idle
    private var start: CMTime = .zero
    /// Pauses in host time; the last one is open (no end) while paused.
    private var pauses: [(begin: CMTime, end: CMTime?)] = []
    private var stopHost: CMTime?
    private var endTime: CMTime = .zero

    static var hostNow: CMTime { CMClockGetTime(CMClockGetHostTimeClock()) }

    var state: State { lock.withLock { _state } }

    func begin() {
        lock.withLock {
            start = Self.hostNow
            pauses = []
            stopHost = nil
            _state = .recording
        }
    }

    func pause() {
        lock.withLock {
            guard _state == .recording else { return }
            pauses.append((Self.hostNow, nil))
            _state = .paused
        }
    }

    func resume() {
        lock.withLock {
            guard _state == .paused, let last = pauses.last, last.end == nil else { return }
            pauses[pauses.count - 1].end = Self.hostNow
            _state = .recording
        }
    }

    /// Total paused time before host time `t` (only pauses that ended by then).
    private func pausedBefore(_ t: CMTime) -> CMTime {
        pauses.reduce(CMTime.zero) { sum, p in
            guard let e = p.end, e <= t else { return sum }
            return CMTimeAdd(sum, CMTimeSubtract(e, p.begin))
        }
    }

    /// Stops the clock and returns the final recording duration.
    @discardableResult
    func stop() -> CMTime {
        lock.withLock {
            guard _state == .recording || _state == .paused else { return endTime }
            var now = Self.hostNow
            if _state == .paused, let open = pauses.last, open.end == nil {
                now = open.begin
                pauses.removeLast()
            }
            stopHost = now
            endTime = CMTimeSubtract(CMTimeSubtract(now, start), pausedBefore(now))
            _state = .stopped
            return endTime
        }
    }

    /// Recording time elapsed (excluding pauses).
    var elapsed: Double {
        lock.withLock {
            switch _state {
            case .idle: return 0
            case .stopped: return endTime.seconds
            case .paused:
                let at = pauses.last?.begin ?? Self.hostNow
                return CMTimeSubtract(CMTimeSubtract(at, start), pausedBefore(at)).seconds
            case .recording:
                let now = Self.hostNow
                return CMTimeSubtract(CMTimeSubtract(now, start), pausedBefore(now)).seconds
            }
        }
    }

    /// The amount to subtract from a host-clock timestamp to get recording time, or nil if the sample
    /// should be dropped (before the start, inside a pause, or after the stop). Decided by the sample's own
    /// timestamp, so samples delivered late around a pause still land in the right place.
    func offset(forHostTime pts: CMTime) -> CMTime? {
        lock.withLock {
            guard _state != .idle, pts >= start else { return nil }
            if let stopHost, pts > stopHost { return nil }
            for p in pauses where pts >= p.begin && (p.end == nil || pts < p.end!) { return nil }
            return CMTimeAdd(start, pausedBefore(pts))
        }
    }

    /// Recording time for a host time, or nil when not recording.
    func recordingTime(hostTime: CMTime) -> Double? {
        offset(forHostTime: hostTime).map { CMTimeSubtract(hostTime, $0).seconds }
    }
}

/// Remembers where the last audio buffer ended, so late or overlapping buffers are dropped
/// (an out-of-order append fails the whole writer). Not thread-safe: use from one queue.
struct AudioOrderGuard {
    private var lastEnd: CMTime = .invalid

    mutating func accept(_ sb: CMSampleBuffer) -> Bool {
        let pts = sb.presentationTimeStamp
        if lastEnd.isValid && CMTimeCompare(pts, CMTimeSubtract(lastEnd, CMTime(value: 1, timescale: 1000))) < 0 { return false }
        let dur = sb.duration
        lastEnd = dur.isValid ? CMTimeAdd(pts, dur) : pts
        return true
    }
}

enum SampleRetimer {
    /// Returns a copy of the sample buffer with every timestamp shifted back by `shift`.
    static func shifted(_ sb: CMSampleBuffer, by shift: CMTime) -> CMSampleBuffer? {
        var count: CMItemCount = 0
        CMSampleBufferGetSampleTimingInfoArray(sb, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count)
        guard count > 0 else { return nil }
        var infos = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: count)
        CMSampleBufferGetSampleTimingInfoArray(sb, entryCount: count, arrayToFill: &infos, entriesNeededOut: &count)
        for i in infos.indices {
            infos[i].presentationTimeStamp = CMTimeSubtract(infos[i].presentationTimeStamp, shift)
            if infos[i].decodeTimeStamp.isValid {
                infos[i].decodeTimeStamp = CMTimeSubtract(infos[i].decodeTimeStamp, shift)
            }
        }
        var out: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault, sampleBuffer: sb,
                                              sampleTimingEntryCount: count, sampleTimingArray: &infos,
                                              sampleBufferOut: &out)
        return out
    }

    /// Returns a copy of a single video frame stamped at exactly `time`.
    static func stamped(_ sb: CMSampleBuffer, at time: CMTime) -> CMSampleBuffer? {
        var info = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: time, decodeTimeStamp: .invalid)
        var out: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault, sampleBuffer: sb,
                                              sampleTimingEntryCount: 1, sampleTimingArray: &info,
                                              sampleBufferOut: &out)
        return out
    }
}
