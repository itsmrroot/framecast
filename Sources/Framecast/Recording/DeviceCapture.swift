import Foundation
import AVFoundation
import CoreMediaIO

/// Records the screen (and sound) of an iPhone or iPad connected by cable into screen.mov,
/// aligned to the shared `RecordingClock` like every other stream.
final class DeviceCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let clock: RecordingClock
    private let url: URL
    private let queue = DispatchQueue(label: "framecast.device", qos: .userInteractive)
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let size: CGSize

    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var lastFrame: CMSampleBuffer?
    private var lastTime: CMTime = .invalid
    private var stopped = false
    private(set) var hasAudio = false

    /// Lets macOS expose connected iOS devices as capture devices. Call once at launch.
    static func enableDiscovery() {
        var prop = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var allow: UInt32 = 1
        CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &prop, 0, nil, UInt32(MemoryLayout<UInt32>.size), &allow)
    }

    /// The device's screen size in pixels, as reported before any frame arrives.
    static func pixelSize(of device: AVCaptureDevice) -> CGSize {
        let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        return CGSize(width: Int(dims.width), height: Int(dims.height))
    }

    init(device: AVCaptureDevice, url: URL, clock: RecordingClock) throws {
        self.clock = clock
        self.url = url
        let px = DeviceCapture.pixelSize(of: device)
        size = CGSize(width: evenInt(px.width), height: evenInt(px.height))
        super.init()
        session.beginConfiguration()
        let input = try AVCaptureDeviceInput(device: device)
        if session.canAddInput(input) { session.addInput(input) }
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
        audioOutput.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        audioOutput.setSampleBufferDelegate(self, queue: queue)
        if device.hasMediaType(.muxed) || device.hasMediaType(.audio), session.canAddOutput(audioOutput) {
            session.addOutput(audioOutput)
            hasAudio = true
        }
        session.commitConfiguration()
    }

    var pixelSize: CGSize { size }

    func startRunning() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async { [session] in
                session.startRunning()
                cont.resume()
            }
        }
    }

    func finish(duration: CMTime) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                stopped = true
                guard let writer, let videoInput, writer.status == .writing else {
                    writer?.cancelWriting()
                    cont.resume()
                    return
                }
                // Hold the last frame until the end so the file is exactly `duration` long.
                let end = CMTimeSubtract(duration, CMTime(value: 1, timescale: 600))
                if let last = lastFrame, !lastTime.isValid || end > lastTime, videoInput.isReadyForMoreMediaData,
                   let b = SampleRetimer.stamped(last, at: end) {
                    videoInput.append(b)
                }
                videoInput.markAsFinished()
                audioInput?.markAsFinished()
                writer.endSession(atSourceTime: duration)
                writer.finishWriting { cont.resume() }
            }
        }
        session.stopRunning()
    }

    func cancel() {
        queue.sync {
            stopped = true
            writer?.cancelWriting()
        }
        session.stopRunning()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sb: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !stopped else { return }
        let pts = sb.presentationTimeStamp
        let hostPTS = CMSyncConvertTime(pts, from: session.synchronizationClock ?? CMClockGetHostTimeClock(), to: CMClockGetHostTimeClock())
        guard let offset = clock.offset(forHostTime: hostPTS) else {
            if output === videoOutput { lastFrame = sb } // shown at t = 0 once recording begins
            return
        }
        let t = CMTimeSubtract(pts, CMTimeAdd(offset, CMTimeSubtract(pts, hostPTS)))
        if output === videoOutput {
            guard startWriterIfNeeded() else { return }
            if !lastTime.isValid, let first = lastFrame, let b = SampleRetimer.stamped(first, at: .zero) {
                videoInput?.append(b)
                lastTime = .zero
            }
            guard let input = videoInput, input.isReadyForMoreMediaData, !lastTime.isValid || t > lastTime,
                  let b = SampleRetimer.stamped(sb, at: t) else { return }
            if input.append(b) {
                lastTime = t
                lastFrame = sb
            }
        } else if output === audioOutput, let input = audioInput, input.isReadyForMoreMediaData, writer != nil, t >= .zero,
                  let b = SampleRetimer.shifted(sb, by: CMTimeSubtract(pts, t)) {
            input.append(b)
        }
    }

    private func startWriterIfNeeded() -> Bool {
        if writer != nil { return writer?.status == .writing }
        guard let w = try? AVAssetWriter(outputURL: url, fileType: .mov) else { return false }
        let v = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspect,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: Int(size.width * size.height * 6),
                AVVideoAllowFrameReorderingKey: false,
            ],
        ])
        v.expectsMediaDataInRealTime = true
        w.add(v)
        if hasAudio {
            let a = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 160_000,
            ])
            a.expectsMediaDataInRealTime = true
            w.add(a)
            audioInput = a
        }
        guard w.startWriting() else { return false }
        w.startSession(atSourceTime: .zero)
        writer = w
        videoInput = v
        return true
    }
}
