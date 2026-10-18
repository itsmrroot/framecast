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
    // Tracks only weakly reference their asset, so the assets must stay alive while their tracks are used.
    let micAsset: AVURLAsset?
    var musicAsset: AVURLAsset? = nil
    var music: AVAssetTrack? = nil
    var musicDuration: Double = 0
    let webcamAsset: AVURLAsset?
    let screenVideo: AVAssetTrack
    let systemAudio: AVAssetTrack?
    let mic: AVAssetTrack?
    let webcam: AVAssetTrack?
    let screenDuration: Double
    let micDuration: Double
    let webcamDuration: Double

    static func load(folder: URL, info: RecordingInfo, enhancedMic: Bool = false, musicFile: String = "") async throws -> ProjectAssets {
        var assets = try await loadRecording(folder: folder, info: info, enhancedMic: enhancedMic)
        if !musicFile.isEmpty {
            let url = folder.appendingPathComponent("music", isDirectory: true).appendingPathComponent(musicFile)
            if FileManager.default.fileExists(atPath: url.path) {
                let a = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
                assets.music = try? await a.loadTracks(withMediaType: .audio).first
                assets.musicDuration = (try? await a.load(.duration).seconds) ?? 0
                assets.musicAsset = a
            }
        }
        return assets
    }

    private static func loadRecording(folder: URL, info: RecordingInfo, enhancedMic: Bool) async throws -> ProjectAssets {
        let screenAsset = AVURLAsset(url: folder.appendingPathComponent(ProjectFiles.screen),
                                     options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        guard let video = try await screenAsset.loadTracks(withMediaType: .video).first else {
            throw NSError(domain: "Framecast", code: 2, userInfo: [NSLocalizedDescriptionKey: "The recording has no video."])
        }
        let screenDuration = try await screenAsset.load(.duration).seconds
        let systemAudio = try await screenAsset.loadTracks(withMediaType: .audio).first

        var mic: AVAssetTrack?
        var micAsset: AVURLAsset?
        var micDuration = 0.0
        let micURL = (enhancedMic ? VoiceEnhancer.existing(in: folder) : nil) ?? folder.appendingPathComponent(ProjectFiles.mic)
        if FileManager.default.fileExists(atPath: micURL.path) {
            let a = AVURLAsset(url: micURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
            mic = try? await a.loadTracks(withMediaType: .audio).first
            micDuration = (try? await a.load(.duration).seconds) ?? 0
            micAsset = a
        }

        var webcam: AVAssetTrack?
        var webcamAsset: AVURLAsset?
        var webcamDuration = 0.0
        let camURL = folder.appendingPathComponent(ProjectFiles.webcam)
        if FileManager.default.fileExists(atPath: camURL.path) {
            let a = AVURLAsset(url: camURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
            webcam = try? await a.loadTracks(withMediaType: .video).first
            webcamDuration = (try? await a.load(.duration).seconds) ?? 0
            webcamAsset = a
        }
        return ProjectAssets(screenAsset: screenAsset, micAsset: micAsset, webcamAsset: webcamAsset, screenVideo: video, systemAudio: systemAudio, mic: mic,
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
    static let musicID: CMPersistentTrackID = 5

    /// `duck`: stretches of edited time with speech, where background music is turned down.
    static func build(assets: ProjectAssets, editMap: EditMap, style: Style, duck: [(Double, Double)] = []) -> BuiltComposition {
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
                // A freeze frame holds the picture; its sound would be a stretched blip, so it stays silent.
                if seg.freeze && (track === sysTrack || track === micTrack) { continue }
                guard let inserted = insert(track, from: source, limit: limit, srcStart: seg.srcStart, srcEnd: seg.srcEnd, at: cursor) else { continue }
                if abs(seg.speed - 1) > 0.001, let track {
                    let scaled = CMTimeMultiplyByFloat64(inserted, multiplier: 1 / seg.speed)
                    track.scaleTimeRange(CMTimeRange(start: cursor, duration: inserted), toDuration: scaled)
                }
            }
            _ = srcDur
            cursor = CMTimeAdd(cursor, targetDur)
        }

        // Background music runs on the edited timeline (not per clip), looping to fill the video.
        if let music = assets.music, assets.musicDuration > 0.5,
           let musicTrack = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: musicID) {
            var at = CMTime.zero
            while at < cursor {
                let len = min(assets.musicDuration, (cursor - at).seconds)
                guard len > 0.05 else { break }
                try? musicTrack.insertTimeRange(CMTimeRange(start: .zero, duration: CMTime(sec: len)), of: music, at: at)
                at = CMTimeAdd(at, CMTime(sec: len))
            }
        }

        let mix = audioMix(for: comp, style: style, duck: duck)

        return BuiltComposition(composition: comp, audioMix: mix, screenTrackID: screenID,
                                webcamTrackID: camTrack != nil ? webcamID : nil,
                                duration: comp.duration)
    }

    /// Music volume over time: fades in over 1 s, out over the last 2 s, and dips to a third while someone speaks.
    static func musicParameters(track: AVAssetTrack, duration: Double, style: Style, duck: [(Double, Double)]) -> AVMutableAudioMixInputParameters {
        let p = AVMutableAudioMixInputParameters(track: track)
        let full = Float(style.musicVolume), low = full * 0.3
        let ramp = 0.35
        // Volume keyframes (time, level), then ramps between them. Speech ranges are merged when close.
        var dips: [(Double, Double)] = []
        for (a, b) in duck.sorted(by: { $0.0 < $1.0 }) where b > a {
            if let last = dips.last, a - last.1 < ramp * 3 { dips[dips.count - 1].1 = max(last.1, b) } else { dips.append((a, b)) }
        }
        var keys: [(Double, Float)] = [(0, 0), (min(1, duration / 2), full)]
        let fadeAt = max(1.1, duration - 2)
        var endLevel = full
        for (a, b) in dips {
            let s = max(a - ramp, (keys.last?.0 ?? 0) + 0.01)
            guard s + ramp < fadeAt else { break }
            if b + ramp >= fadeAt {
                // Speech runs into the closing fade: stay low and fade out from there.
                keys += [(s, keys.last?.1 ?? full), (s + ramp, low)]
                endLevel = low
                break
            }
            keys += [(s, full), (s + ramp, low), (max(s + ramp, b), low), (b + ramp, full)]
        }
        let fadeStart = max((keys.last?.0 ?? 0) + 0.01, fadeAt)
        keys += [(fadeStart, endLevel), (duration, 0)]
        p.setVolume(0, at: .zero)
        for (k0, k1) in zip(keys, keys.dropFirst()) where k1.0 > k0.0 {
            p.setVolumeRamp(fromStartVolume: k0.1, toEndVolume: k1.1,
                            timeRange: CMTimeRange(start: CMTime(sec: k0.0), end: CMTime(sec: k1.0)))
        }
        return p
    }

    static func audioMix(for comp: AVComposition, style: Style, duck: [(Double, Double)] = []) -> AVMutableAudioMix? {
        var params: [AVMutableAudioMixInputParameters] = []
        for (id, volume) in [(systemAudioID, style.systemVolume), (micID, style.micVolume)] {
            guard let track = comp.track(withTrackID: id) else { continue }
            let p = AVMutableAudioMixInputParameters(track: track)
            p.setVolume(Float(volume), at: .zero)
            p.audioTimePitchAlgorithm = .spectral
            params.append(p)
        }
        if let track = comp.track(withTrackID: musicID) {
            params.append(musicParameters(track: track, duration: comp.duration.seconds, style: style, duck: style.musicDuck ? duck : []))
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
