import Foundation
import AVFoundation

/// Records the webcam and/or microphone to separate files aligned to the shared `RecordingClock`.
final class CameraMicCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let clock: RecordingClock
    private let queue = DispatchQueue(label: "framecast.camera-mic", qos: .userInteractive)
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()

    private let cameraURL: URL?
    private let micURL: URL?
    private var camWriter: AVAssetWriter?
    private var camInput: AVAssetWriterInput?
    private var micWriter: AVAssetWriter?
    private var micInput: AVAssetWriterInput?
    private var lastCamTime: CMTime = .invalid
    private var stopped = false

    private(set) var hasCamera = false
    private(set) var hasMic = false

    /// The highest preset up to the chosen resolution (720, 1080 or 2160) that the camera supports.
    static func preset(for resolution: Int, session: AVCaptureSession) -> AVCaptureSession.Preset {
        let wanted: [AVCaptureSession.Preset]
        switch resolution {
        case 2160: wanted = [.hd4K3840x2160, .hd1920x1080, .hd1280x720]
        case 1080: wanted = [.hd1920x1080, .hd1280x720]
        default: wanted = [.hd1280x720]
        }
        return wanted.first { session.canSetSessionPreset($0) } ?? .high
    }

    init(cameraID: String?, micID: String?, folder: URL, clock: RecordingClock, cameraResolution: Int = 1080) throws {
        self.clock = clock
        cameraURL = cameraID != nil ? folder.appendingPathComponent(ProjectFiles.webcam) : nil
        micURL = micID != nil ? folder.appendingPathComponent(ProjectFiles.mic) : nil
        super.init()

        session.beginConfiguration()
        if let cameraID, let device = DeviceCatalog.camera(id: cameraID) {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) { session.addInput(input) }
            session.sessionPreset = CameraMicCapture.preset(for: cameraResolution, session: session)
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(videoOutput) { session.addOutput(videoOutput); hasCamera = true }
        }
        if let micID, let device = DeviceCatalog.microphone(id: micID) {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) { session.addInput(input) }
            audioOutput.audioSettings = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsNonInterleaved: false,
                AVLinearPCMIsBigEndianKey: false,
            ]
            audioOutput.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(audioOutput) { session.addOutput(audioOutput); hasMic = true }
        }
        session.commitConfiguration()
    }

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
                let group = DispatchGroup()
                for (writer, input) in [(camWriter, camInput), (micWriter, micInput)] {
                    guard let writer, let input, writer.status == .writing else { continue }
                    input.markAsFinished()
                    writer.endSession(atSourceTime: duration)
                    group.enter()
                    writer.finishWriting { group.leave() }
                }
                group.notify(queue: .global()) { cont.resume() }
            }
        }
        session.stopRunning()
    }

    func cancel() {
        queue.sync {
            stopped = true
            camWriter?.cancelWriting()
            micWriter?.cancelWriting()
        }
        session.stopRunning()
    }

    // MARK: Delegate

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !stopped else { return }
        let pts = sampleBuffer.presentationTimeStamp
        let hostPTS = CMSyncConvertTime(pts, from: session.synchronizationClock ?? CMClockGetHostTimeClock(), to: CMClockGetHostTimeClock())
        guard let offset = clock.offset(forHostTime: hostPTS) else { return }
        // shift so that new pts = hostPTS - offset
        let shift = CMTimeAdd(offset, CMTimeSubtract(pts, hostPTS))

        if output === videoOutput {
            writeCamera(sampleBuffer, shift: shift)
        } else if output === audioOutput {
            writeMic(sampleBuffer, shift: shift)
        }
    }

    private func writeCamera(_ sb: CMSampleBuffer, shift: CMTime) {
        guard let url = cameraURL else { return }
        if camWriter == nil {
            guard let format = sb.formatDescription else { return }
            let dims = CMVideoFormatDescriptionGetDimensions(format)
            guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else { return }
            writer.movieFragmentInterval = CMTime(value: 1, timescale: 1)
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(dims.width),
                AVVideoHeightKey: Int(dims.height),
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 8_000_000,
                    AVVideoAllowFrameReorderingKey: false,
                ],
            ])
            input.expectsMediaDataInRealTime = true
            writer.add(input)
            guard writer.startWriting() else { return }
            writer.startSession(atSourceTime: .zero)
            camWriter = writer
            camInput = input
        }
        guard let input = camInput, input.isReadyForMoreMediaData else { return }
        let t = CMTimeSubtract(sb.presentationTimeStamp, shift)
        guard !lastCamTime.isValid || t > lastCamTime, let b = SampleRetimer.stamped(sb, at: t) else { return }
        if input.append(b) { lastCamTime = t }
    }

    private func writeMic(_ sb: CMSampleBuffer, shift: CMTime) {
        guard let url = micURL else { return }
        if micWriter == nil {
            guard let writer = try? AVAssetWriter(outputURL: url, fileType: .m4a) else { return }
            writer.movieFragmentInterval = CMTime(value: 1, timescale: 1)
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 128_000,
            ], sourceFormatHint: sb.formatDescription)
            input.expectsMediaDataInRealTime = true
            writer.add(input)
            guard writer.startWriting() else { return }
            writer.startSession(atSourceTime: .zero)
            micWriter = writer
            micInput = input
        }
        guard let input = micInput, input.isReadyForMoreMediaData,
              let b = SampleRetimer.shifted(sb, by: shift) else { return }
        input.append(b)
    }
}

/// Lists cameras and microphones.
enum DeviceCatalog {
    struct Device: Identifiable, Hashable { let id: String; let name: String }

    static func cameras() -> [Device] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera, .deskViewCamera],
                                         mediaType: .video, position: .unspecified)
            .devices.map { Device(id: $0.uniqueID, name: $0.localizedName) }
    }

    /// iPhones and iPads connected by cable (needs `DeviceCapture.enableDiscovery()`).
    static func iosDevices() -> [Device] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.external], mediaType: .muxed, position: .unspecified)
            .devices.map { Device(id: $0.uniqueID, name: $0.localizedName) }
    }

    static func iosDevice(id: String) -> AVCaptureDevice? {
        AVCaptureDevice(uniqueID: id)
    }

    static func microphones() -> [Device] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified)
            .devices.map { Device(id: $0.uniqueID, name: $0.localizedName) }
    }

    static func camera(id: String) -> AVCaptureDevice? {
        AVCaptureDevice(uniqueID: id) ?? AVCaptureDevice.default(for: .video)
    }

    static func microphone(id: String) -> AVCaptureDevice? {
        AVCaptureDevice(uniqueID: id) ?? AVCaptureDevice.default(for: .audio)
    }
}
