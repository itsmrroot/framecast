import Foundation
import ScreenCaptureKit
import AVFoundation

/// Captures the screen (and optionally system audio) with ScreenCaptureKit and writes it to a .mov.
/// The cursor is hidden from the video; it is recorded separately by `CursorRecorder`.
final class ScreenCaptureSession: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let clock: RecordingClock
    private let queue = DispatchQueue(label: "framecast.screen-capture", qos: .userInteractive)
    private var stream: SCStream?
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let audioInput: AVAssetWriterInput?

    private var sessionStarted = false
    private var lastFrame: CMSampleBuffer?
    private var lastFrameTime: CMTime = .invalid
    private var audioOrder = AudioOrderGuard()
    private var reportedFailure = false
    private(set) var framesWritten = 0

    var onError: ((Error) -> Void)?

    init(url: URL, width: Int, height: Int, fps: Int, captureAudio: Bool, clock: RecordingClock) throws {
        self.clock = clock
        try? FileManager.default.removeItem(at: url)
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        // Written in fragments, so the file stays playable if Framecast quits mid-recording.
        writer.movieFragmentInterval = CMTime(value: 1, timescale: 1)

        let pixels = Double(width * height)
        let bitrate = Int(min(max(pixels * Double(fps) * 0.12, 8_000_000), 80_000_000))
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoExpectedSourceFrameRateKey: fps,
                AVVideoMaxKeyFrameIntervalKey: fps * 2,
                AVVideoAllowFrameReorderingKey: false,
            ],
        ]
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        writer.add(videoInput)

        if captureAudio {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192_000,
            ]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = true
            writer.add(input)
            audioInput = input
        } else {
            audioInput = nil
        }
        super.init()
    }

    /// Starts the stream ("warm"), frames are buffered but not written until `beginRecording`.
    func start(filter: SCContentFilter, configuration: SCStreamConfiguration) async throws {
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        if audioInput != nil {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        }
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        try await stream.startCapture()
        self.stream = stream
    }

    /// Call right after resuming. ScreenCaptureKit only sends frames when the screen changes, so write the
    /// latest frame now; otherwise the video would show the pre-pause screen until something moved.
    func refreshAfterResume(at time: CMTime) {
        queue.async { [self] in
            guard sessionStarted, let last = lastFrame, !lastFrameTime.isValid || time > lastFrameTime,
                  let b = SampleRetimer.stamped(last, at: time) else { return }
            appendVideo(b, time: time)
        }
    }

    /// Call right after `clock.begin()`. Writes the most recent frame at t = 0 so the video never starts blank.
    func beginRecording() {
        queue.async { [self] in
            guard !sessionStarted else { return }
            writer.startSession(atSourceTime: .zero)
            sessionStarted = true
            if let prev = lastFrame, let b = SampleRetimer.stamped(prev, at: .zero) {
                appendVideo(b, time: .zero)
            }
        }
    }

    func finish(duration: CMTime) async {
        if let stream {
            try? await stream.stopCapture()
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                guard sessionStarted, writer.status == .writing else {
                    writer.cancelWriting()
                    cont.resume()
                    return
                }
                // Hold the final frame until the end so the video is exactly `duration` long.
                let endFrameTime = CMTimeSubtract(duration, CMTime(value: 1, timescale: 600))
                if let last = lastFrame, !lastFrameTime.isValid || endFrameTime > lastFrameTime,
                   let b = SampleRetimer.stamped(last, at: endFrameTime) {
                    appendVideo(b, time: endFrameTime)
                }
                videoInput.markAsFinished()
                audioInput?.markAsFinished()
                writer.endSession(atSourceTime: duration)
                writer.finishWriting { cont.resume() }
            }
        }
    }

    func cancel() async {
        if let stream { try? await stream.stopCapture() }
        queue.sync { writer.cancelWriting() }
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }
        switch type {
        case .screen: handleVideo(sampleBuffer)
        case .audio: handleAudio(sampleBuffer)
        default: break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("Framecast: stream stopped with error \(error)")
        onError?(error)
    }

    private func handleVideo(_ sb: CMSampleBuffer) {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete,
              sb.imageBuffer != nil else { return }

        let pts = sb.presentationTimeStamp
        guard sessionStarted, let offset = clock.offset(forHostTime: pts) else {
            lastFrame = sb
            return
        }
        let t = CMTimeSubtract(pts, offset)
        if lastFrameTime.isValid && t <= lastFrameTime { lastFrame = sb; return }
        if let b = SampleRetimer.stamped(sb, at: t) {
            appendVideo(b, time: t)
        }
        lastFrame = sb
    }

    private func appendVideo(_ sb: CMSampleBuffer, time: CMTime) {
        guard videoInput.isReadyForMoreMediaData else { return }
        if videoInput.append(sb) {
            lastFrameTime = time
            framesWritten += 1
        } else {
            reportWriterFailure()
        }
    }

    private func handleAudio(_ sb: CMSampleBuffer) {
        guard sessionStarted, let input = audioInput,
              let offset = clock.offset(forHostTime: sb.presentationTimeStamp),
              let b = SampleRetimer.shifted(sb, by: offset),
              input.isReadyForMoreMediaData, audioOrder.accept(b) else { return }
        if !input.append(b) { reportWriterFailure() }
    }

    /// A failed writer drops everything after it; stop the recording so what was written is kept.
    private func reportWriterFailure() {
        guard writer.status == .failed, !reportedFailure else { return }
        reportedFailure = true
        let error = writer.error ?? CocoaError(.fileWriteUnknown)
        NSLog("Framecast: screen writer failed: \(error)")
        onError?(error)
    }
}
