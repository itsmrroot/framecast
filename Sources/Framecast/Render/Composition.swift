import Foundation
import AVFoundation
import CoreImage

// MARK: - Custom compositor (shared by preview playback and export)

final class FrameInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid
    let model: RenderModel

    init(timeRange: CMTimeRange, model: RenderModel) {
        self.timeRange = timeRange
        self.model = model
        var ids: [NSValue] = [NSNumber(value: model.screenTrackID)]
        if let cam = model.webcamTrackID { ids.append(NSNumber(value: cam)) }
        requiredSourceTrackIDs = ids
        super.init()
    }
}

final class FrameCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    private let queue = DispatchQueue(label: "framecast.compositor", qos: .userInteractive)

    private static let pixelAttrs: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferMetalCompatibilityKey as String: true,
        kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
    ]

    var sourcePixelBufferAttributes: [String: any Sendable]? {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
         kCVPixelBufferMetalCompatibilityKey as String: true]
    }

    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
         kCVPixelBufferMetalCompatibilityKey as String: true]
    }

    var supportsWideColorSourceFrames: Bool { true }

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        queue.async {
            autoreleasepool {
                guard let instruction = request.videoCompositionInstruction as? FrameInstruction,
                      let output = request.renderContext.newPixelBuffer() else {
                    request.finish(with: NSError(domain: "Framecast", code: 1))
                    return
                }
                let model = instruction.model
                let screen = request.sourceFrame(byTrackID: model.screenTrackID)
                let camera = model.webcamTrackID.flatMap { request.sourceFrame(byTrackID: $0) }
                FrameRenderer.shared.render(model: model, compTime: request.compositionTime.seconds,
                                            screen: screen, camera: camera, into: output)
                request.finish(withComposedVideoFrame: output)
            }
        }
    }

    func cancelAllPendingVideoCompositionRequests() {}
}

// MARK: - Source media

struct ProjectAssets {
    let screenAsset: AVURLAsset
    let screenVideo: AVAssetTrack
    let systemAudio: AVAssetTrack?
    let mic: AVAssetTrack?
    let webcam: AVAssetTrack?
    let screenDuration: Double
    let micDuration: Double
    let webcamDuration: Double

    static func load(folder: URL, info: RecordingInfo) async throws -> ProjectAssets {
        let screenAsset = AVURLAsset(url: folder.appendingPathComponent(ProjectFiles.screen),
                                     options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        guard let video = try await screenAsset.loadTracks(withMediaType: .video).first else {
            throw NSError(domain: "Framecast", code: 2, userInfo: [NSLocalizedDescriptionKey: "The recording has no video."])
        }
        let screenDuration = try await screenAsset.load(.duration).seconds
        let systemAudio = try await screenAsset.loadTracks(withMediaType: .audio).first

        var mic: AVAssetTrack?
        var micDuration = 0.0
        let micURL = folder.appendingPathComponent(ProjectFiles.mic)
        if FileManager.default.fileExists(atPath: micURL.path) {
            let a = AVURLAsset(url: micURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
            mic = try? await a.loadTracks(withMediaType: .audio).first
            micDuration = (try? await a.load(.duration).seconds) ?? 0
        }

        var webcam: AVAssetTrack?
        var webcamDuration = 0.0
        let camURL = folder.appendingPathComponent(ProjectFiles.webcam)
        if FileManager.default.fileExists(atPath: camURL.path) {
            let a = AVURLAsset(url: camURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
            webcam = try? await a.loadTracks(withMediaType: .video).first
            webcamDuration = (try? await a.load(.duration).seconds) ?? 0
        }
        return ProjectAssets(screenAsset: screenAsset, screenVideo: video, systemAudio: systemAudio, mic: mic,
                             webcam: webcam, screenDuration: screenDuration, micDuration: micDuration,
                             webcamDuration: webcamDuration)
    }
}

// MARK: - Composition

struct BuiltComposition {
    let composition: AVMutableComposition
    let audioMix: AVMutableAudioMix?
    let screenTrackID: CMPersistentTrackID
    let webcamTrackID: CMPersistentTrackID?
    let duration: CMTime
}

enum CompositionBuilder {
    static let screenID: CMPersistentTrackID = 1
    static let webcamID: CMPersistentTrackID = 2
    static let systemAudioID: CMPersistentTrackID = 3
    static let micID: CMPersistentTrackID = 4

    static func build(assets: ProjectAssets, editMap: EditMap, style: Style) -> BuiltComposition {
        let comp = AVMutableComposition()
        let screenTrack = comp.addMutableTrack(withMediaType: .video, preferredTrackID: screenID)
        let camTrack = assets.webcam != nil ? comp.addMutableTrack(withMediaType: .video, preferredTrackID: webcamID) : nil
        let sysTrack = assets.systemAudio != nil ? comp.addMutableTrack(withMediaType: .audio, preferredTrackID: systemAudioID) : nil
        let micTrack = assets.mic != nil ? comp.addMutableTrack(withMediaType: .audio, preferredTrackID: micID) : nil

        func insert(_ track: AVMutableCompositionTrack?, from source: AVAssetTrack?, limit: Double,
                    srcStart: Double, srcEnd: Double, at: CMTime) -> CMTime? {
            guard let track, let source else { return nil }
            let end = min(srcEnd, limit)
            guard end - srcStart > 0.01 else { return nil }
            let range = CMTimeRange(start: CMTime(sec: srcStart), end: CMTime(sec: end))
            do {
                try track.insertTimeRange(range, of: source, at: at)
                return range.duration
            } catch {
                return nil
            }
        }

        var cursor = CMTime.zero
        for seg in editMap.segments {
            let srcDur = CMTime(sec: seg.srcEnd - seg.srcStart)
            let targetDur = CMTime(sec: (seg.srcEnd - seg.srcStart) / seg.speed)
            let entries: [(AVMutableCompositionTrack?, AVAssetTrack?, Double)] = [
                (screenTrack, assets.screenVideo, assets.screenDuration),
                (camTrack, assets.webcam, assets.webcamDuration),
                (sysTrack, assets.systemAudio, assets.screenDuration),
                (micTrack, assets.mic, assets.micDuration),
            ]
            for (track, source, limit) in entries {
                guard let inserted = insert(track, from: source, limit: limit, srcStart: seg.srcStart, srcEnd: seg.srcEnd, at: cursor) else { continue }
                if abs(seg.speed - 1) > 0.001, let track {
                    let scaled = CMTimeMultiplyByFloat64(inserted, multiplier: 1 / seg.speed)
                    track.scaleTimeRange(CMTimeRange(start: cursor, duration: inserted), toDuration: scaled)
                }
            }
            _ = srcDur
            cursor = CMTimeAdd(cursor, targetDur)
        }

        let mix = audioMix(for: comp, style: style)

        return BuiltComposition(composition: comp, audioMix: mix, screenTrackID: screenID,
                                webcamTrackID: camTrack != nil ? webcamID : nil,
                                duration: comp.duration)
    }

    static func audioMix(for comp: AVComposition, style: Style) -> AVMutableAudioMix? {
        var params: [AVMutableAudioMixInputParameters] = []
        for (id, volume) in [(systemAudioID, style.systemVolume), (micID, style.micVolume)] {
            guard let track = comp.track(withTrackID: id) else { continue }
            let p = AVMutableAudioMixInputParameters(track: track)
            p.setVolume(Float(volume), at: .zero)
            p.audioTimePitchAlgorithm = .spectral
            params.append(p)
        }
        guard !params.isEmpty else { return nil }
        let mix = AVMutableAudioMix()
        mix.inputParameters = params
        return mix
    }

    static func videoComposition(model: RenderModel, renderSize: CGSize, fps: Int, duration: CMTime) -> AVMutableVideoComposition {
        let vc = AVMutableVideoComposition()
        vc.customVideoCompositorClass = FrameCompositor.self
        vc.renderSize = renderSize
        vc.frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
        vc.instructions = [FrameInstruction(timeRange: CMTimeRange(start: .zero, duration: duration), model: model)]
        return vc
    }
}
