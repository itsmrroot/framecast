import Foundation
import CoreMedia

/// One clock shared by every recorder (screen, audio, camera, cursor) so all files line up at t = 0,
/// with pauses removed from the timeline.
final class RecordingClock: @unchecked Sendable {
    enum State { case idle, recording, paused, stopped }

    private let lock = NSLock()
    private var _state: State = .idle
    private var start: CMTime = .zero
    private var pausedTotal: CMTime = .zero
    private var pauseBegan: CMTime = .zero
    private var endTime: CMTime = .zero

    static var hostNow: CMTime { CMClockGetTime(CMClockGetHostTimeClock()) }

    var state: State { lock.withLock { _state } }

    func begin() {
        lock.withLock {
            start = Self.hostNow
            pausedTotal = .zero
            _state = .recording
        }
    }

    func pause() {
        lock.withLock {
            guard _state == .recording else { return }
            pauseBegan = Self.hostNow
            _state = .paused
        }
    }

    func resume() {
        lock.withLock {
            guard _state == .paused else { return }
            pausedTotal = CMTimeAdd(pausedTotal, CMTimeSubtract(Self.hostNow, pauseBegan))
            _state = .recording
        }
    }

    /// Stops the clock and returns the final recording duration.
    @discardableResult
    func stop() -> CMTime {
        lock.withLock {
            let now = _state == .paused ? pauseBegan : Self.hostNow
            if _state == .recording || _state == .paused {
                endTime = CMTimeSubtract(CMTimeSubtract(now, start), pausedTotal)
            }
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
            case .paused: return CMTimeSubtract(CMTimeSubtract(pauseBegan, start), pausedTotal).seconds
            case .recording: return CMTimeSubtract(CMTimeSubtract(Self.hostNow, start), pausedTotal).seconds
            }
        }
    }

    /// The amount to subtract from a host-clock timestamp to get recording time,
    /// or nil if samples at that time should be dropped.
    func offset(forHostTime pts: CMTime) -> CMTime? {
        lock.withLock {
            guard _state == .recording, pts >= start else { return nil }
            let off = CMTimeAdd(start, pausedTotal)
            return CMTimeSubtract(pts, off) >= .zero ? off : nil
        }
    }

    /// Recording time for a host time, or nil when not recording.
    func recordingTime(hostTime: CMTime) -> Double? {
        offset(forHostTime: hostTime).map { CMTimeSubtract(hostTime, $0).seconds }
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
