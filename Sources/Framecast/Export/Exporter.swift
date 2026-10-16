import Foundation
import AVFoundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import AppKit
import VideoToolbox

enum ExportFormat: String, CaseIterable, Identifiable {
    case mp4, gif
    var id: String { rawValue }
    var label: String { self == .mp4 ? "MP4 Video" : "Animated GIF" }
    var fileExtension: String { rawValue }
}

enum ExportResolution: Int, CaseIterable, Identifiable {
    case p720 = 720, p1080 = 1080, p1440 = 1440, p2160 = 2160
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .p720: return "720p"
        case .p1080: return "1080p"
        case .p1440: return "1440p"
        case .p2160: return "4K"
        }
    }
}

enum ExportCodec: String, CaseIterable, Identifiable {
    case h264, hevc
    var id: String { rawValue }
    var label: String { self == .h264 ? "H.264 (most compatible)" : "HEVC (smaller files)" }
}

/// Compression presets, named after where the video is going.
enum ExportQuality: String, CaseIterable, Identifiable {
    case best, high, standard, low
    var id: String { rawValue }
    var label: String {
        switch self {
        case .best: return "Studio"
        case .high: return "Social Media"
        case .standard: return "Web"
        case .low: return "Web (Low)"
        }
    }
    var detail: String {
        switch self {
        case .best: return "Highest quality for editing elsewhere or archiving. Large files."
        case .high: return "Great for sharing on social media. Compression is barely noticeable."
        case .standard: return "Smaller files for websites and docs. Some compression is visible up close."
        case .low: return "Smallest files for quick previews and slow connections."
        }
    }
    var bitsPerPixel: Double {
        switch self {
        case .best: return 0.2
        case .high: return 0.12
        case .standard: return 0.07
        case .low: return 0.035
        }
    }
}

struct ExportSettings {
    var format: ExportFormat = .mp4
    var resolution: ExportResolution = .p1080
    var fps: Int = 60
    var codec: ExportCodec = .h264
    var quality: ExportQuality = .high
    var gifFPS: Int = 20
    var gifWidth: Int = 960
    var disableHardwareAcceleration = false
}

struct ExportJob {
    let built: BuiltComposition
    let model: RenderModel
}

final class Exporter: @unchecked Sendable {
    enum ExportError: LocalizedError {
        case failed(String)
        case cancelled
        var errorDescription: String? {
            switch self {
            case .failed(let s): return s
            case .cancelled: return "Export cancelled."
            }
        }
    }

    private var reader: AVAssetReader?
    private var writer: AVAssetWriter?
    private let lock = NSLock()
    private var cancelled = false
    /// Finishes every writer input still open. A cancelled or failed writer never asks for data again,
    /// so waiting inputs must be finished from outside their callbacks or the export never completes.
    private var finishOpenInputs: (() -> Void)?

    func cancel() {
        lock.withLock { cancelled = true }
        reader?.cancelReading()
        lock.withLock { finishOpenInputs }?()
        writer?.cancelWriting()
    }

    private var isCancelled: Bool { lock.withLock { cancelled } }

    func export(job: ExportJob, settings: ExportSettings, to url: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        try? FileManager.default.removeItem(at: url)
        switch settings.format {
        case .mp4: try await exportMP4(job: job, settings: settings, to: url, progress: progress)
        case .gif: try await exportGIF(job: job, settings: settings, to: url, progress: progress)
        }
    }

    // MARK: MP4

    private func exportMP4(job: ExportJob, settings: ExportSettings, to url: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let comp = job.built.composition
        let duration = job.built.duration
        let size = job.model.outputSize(shortSide: settings.resolution.rawValue)
        let videoTracks = comp.tracks(withMediaType: .video)
        let audioTracks = comp.tracks(withMediaType: .audio)

        let reader = try AVAssetReader(asset: comp)
        let vOut = AVAssetReaderVideoCompositionOutput(videoTracks: videoTracks, videoSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        vOut.videoComposition = CompositionBuilder.videoComposition(model: job.model, renderSize: size, fps: settings.fps, duration: duration)
        vOut.alwaysCopiesSampleData = false
        guard reader.canAdd(vOut) else { throw ExportError.failed("Can't read the video.") }
        reader.add(vOut)

        var aOut: AVAssetReaderAudioMixOutput?
        if !audioTracks.isEmpty {
            let out = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsNonInterleaved: false,
                AVLinearPCMIsBigEndianKey: false,
            ])
            out.audioMix = job.built.audioMix
            out.audioTimePitchAlgorithm = .spectral
            if reader.canAdd(out) { reader.add(out); aOut = out }
        }

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        let bitrate = Int(size.width * size.height * Double(settings.fps) * settings.quality.bitsPerPixel)
        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: bitrate,
            AVVideoExpectedSourceFrameRateKey: settings.fps,
            AVVideoMaxKeyFrameIntervalKey: settings.fps * 2,
        ]
        if settings.codec == .h264 {
            compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
        }
        var videoSettings: [String: Any] = [
            AVVideoCodecKey: settings.codec == .h264 ? AVVideoCodecType.h264 : AVVideoCodecType.hevc,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
            AVVideoCompressionPropertiesKey: compression,
        ]
        if settings.disableHardwareAcceleration {
            videoSettings[AVVideoEncoderSpecificationKey] = [
                kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder as String: false,
            ]
        }
        let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        vIn.expectsMediaDataInRealTime = false
        writer.add(vIn)

        var aIn: AVAssetWriterInput?
        if aOut != nil {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192_000,
            ])
            input.expectsMediaDataInRealTime = false
            writer.add(input)
            aIn = input
        }

        self.reader = reader
        self.writer = writer
        guard reader.startReading() else { throw ExportError.failed(reader.error?.localizedDescription ?? "Couldn't start reading.") }
        guard writer.startWriting() else { throw ExportError.failed(writer.error?.localizedDescription ?? "Couldn't start writing.") }
        writer.startSession(atSourceTime: .zero)

        let total = max(duration.seconds, 0.001)
        let group = DispatchGroup()
        let inputs = [vIn] + (aIn.map { [$0] } ?? [])
        let done = InputFinisher(count: inputs.count, group: group)
        for _ in inputs { group.enter() }
        // On a failure or cancel, finish every input so none waits for a callback that never comes.
        let finishAll = { [weak reader] in
            reader?.cancelReading()
            for (i, input) in inputs.enumerated() { done.finish(i, input) }
        }
        lock.withLock { finishOpenInputs = finishAll }

        let vQueue = DispatchQueue(label: "framecast.export.video")
        vIn.requestMediaDataWhenReady(on: vQueue) {
            while vIn.isReadyForMoreMediaData && !done.isFinished(0) {
                if let sb = vOut.copyNextSampleBuffer() {
                    if !vIn.append(sb) {
                        finishAll()
                        return
                    }
                    progress(min(1, sb.presentationTimeStamp.seconds / total))
                } else {
                    done.finish(0, vIn)
                    return
                }
            }
        }

        if let aIn, let aOut {
            let aQueue = DispatchQueue(label: "framecast.export.audio")
            aIn.requestMediaDataWhenReady(on: aQueue) {
                while aIn.isReadyForMoreMediaData && !done.isFinished(1) {
                    if let sb = aOut.copyNextSampleBuffer() {
                        if !aIn.append(sb) {
                            finishAll()
                            return
                        }
                    } else {
                        done.finish(1, aIn)
                        return
                    }
                }
            }
        }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            group.notify(queue: .global()) { cont.resume() }
        }
        lock.withLock { finishOpenInputs = nil }

        if isCancelled {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            throw ExportError.cancelled
        }
        if reader.status == .failed {
            writer.cancelWriting()
            throw ExportError.failed(reader.error?.localizedDescription ?? "Reading failed.")
        }
        if writer.status == .failed {
            let message = writer.error?.localizedDescription ?? "Writing failed."
            try? FileManager.default.removeItem(at: url)
            throw ExportError.failed(message)
        }
        writer.endSession(atSourceTime: duration)
        await writer.finishWriting()
        if writer.status != .completed {
            throw ExportError.failed(writer.error?.localizedDescription ?? "Writing failed.")
        }
        progress(1)
    }

    // MARK: GIF

    private func exportGIF(job: ExportJob, settings: ExportSettings, to url: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let comp = job.built.composition
        let duration = job.built.duration
        var size = job.model.outputSize(longSide: settings.gifWidth)
        if job.model.aspect < 1 { size = job.model.outputSize(longSide: settings.gifWidth) }

        let reader = try AVAssetReader(asset: comp)
        let vOut = AVAssetReaderVideoCompositionOutput(videoTracks: comp.tracks(withMediaType: .video), videoSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        vOut.videoComposition = CompositionBuilder.videoComposition(model: job.model, renderSize: size, fps: settings.gifFPS, duration: duration)
        reader.add(vOut)
        self.reader = reader
        guard reader.startReading() else { throw ExportError.failed(reader.error?.localizedDescription ?? "Couldn't start reading.") }

        let frameCount = Int(duration.seconds * Double(settings.gifFPS)) + 1
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frameCount, nil) else {
            throw ExportError.failed("Couldn't create GIF file.")
        }
        CGImageDestinationSetProperties(dest, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)
        let frameProps = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFUnclampedDelayTime: 1.0 / Double(settings.gifFPS),
                kCGImagePropertyGIFDelayTime: 1.0 / Double(settings.gifFPS),
            ],
        ] as CFDictionary

        let ctx = FrameRenderer.shared.ciContext
        let total = max(duration.seconds, 0.001)
        while let sb = vOut.copyNextSampleBuffer() {
            if isCancelled {
                reader.cancelReading()
                break
            }
            autoreleasepool {
                if let pb = sb.imageBuffer {
                    let ci = CIImage(cvPixelBuffer: pb)
                    if let cg = ctx.createCGImage(ci, from: ci.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) {
                        CGImageDestinationAddImage(dest, cg, frameProps)
                    }
                }
                progress(min(0.99, sb.presentationTimeStamp.seconds / total))
            }
        }
        if isCancelled {
            try? FileManager.default.removeItem(at: url)
            throw ExportError.cancelled
        }
        if reader.status == .failed {
            try? FileManager.default.removeItem(at: url)
            throw ExportError.failed(reader.error?.localizedDescription ?? "Rendering the GIF failed.")
        }
        guard CGImageDestinationFinalize(dest) else { throw ExportError.failed("Couldn't finalize GIF.") }
        progress(1)
    }
}

/// Marks each writer input finished and leaves the group exactly once, whoever gets there first.
private final class InputFinisher: @unchecked Sendable {
    private let lock = NSLock()
    private var finished: [Bool]
    private let group: DispatchGroup

    init(count: Int, group: DispatchGroup) {
        finished = Array(repeating: false, count: count)
        self.group = group
    }

    func isFinished(_ i: Int) -> Bool { lock.withLock { finished[i] } }

    func finish(_ i: Int, _ input: AVAssetWriterInput) {
        let first = lock.withLock { () -> Bool in
            guard !finished[i] else { return false }
            finished[i] = true
            return true
        }
        guard first else { return }
        input.markAsFinished()
        group.leave()
    }
}
