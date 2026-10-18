import Foundation
import AVFoundation

/// "Enhance voice": cleans up the microphone track once, offline, into a separate file
/// (the original recording is never changed).
/// - a high-pass filter removes rumble (desk knocks, air conditioning, handling noise)
/// - a gentle cut in the low mids removes boxiness, and a lift around 3 kHz adds clarity
/// - a compressor evens out loud and quiet words
/// - the result is normalised so the voice peaks just below full scale
enum VoiceEnhancer {
    static let fileName = "mic-enhanced.m4a"

    enum Failure: LocalizedError {
        case unreadable, failed(String)
        var errorDescription: String? {
            switch self {
            case .unreadable: return "The microphone recording couldn't be read."
            case .failed(let s): return "Enhancing the voice failed: \(s)"
            }
        }
    }

    /// The enhanced file for a project, if it's been made and is newer than the microphone recording.
    static func existing(in folder: URL) -> URL? {
        let out = folder.appendingPathComponent(fileName)
        let mic = folder.appendingPathComponent(ProjectFiles.mic)
        let fm = FileManager.default
        guard let o = try? fm.attributesOfItem(atPath: out.path)[.modificationDate] as? Date,
              let m = try? fm.attributesOfItem(atPath: mic.path)[.modificationDate] as? Date, o >= m else { return nil }
        return out
    }

    /// Processes the project's microphone track. Runs off the main thread.
    static func process(folder: URL) async throws -> URL {
        let input = folder.appendingPathComponent(ProjectFiles.mic)
        let output = folder.appendingPathComponent(fileName)
        return try await Task.detached(priority: .userInitiated) {
            try render(input: input, output: output)
            return output
        }.value
    }

    private static func render(input: URL, output: URL) throws {
        guard let source = try? AVAudioFile(forReading: input) else { throw Failure.unreadable }
        let format = source.processingFormat
        let frames = AVAudioFrameCount(source.length)
        guard frames > 0 else { throw Failure.unreadable }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let eq = AVAudioUnitEQ(numberOfBands: 3)
        let highPass = eq.bands[0]
        highPass.filterType = .highPass
        highPass.frequency = 85
        highPass.bypass = false
        let mud = eq.bands[1]
        mud.filterType = .parametric
        mud.frequency = 300
        mud.bandwidth = 1.2
        mud.gain = -2.5
        mud.bypass = false
        let presence = eq.bands[2]
        presence.filterType = .parametric
        presence.frequency = 3200
        presence.bandwidth = 1.4
        presence.gain = 3
        presence.bypass = false

        let compressor = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
            componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_DynamicsProcessor,
            componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0))
        let au = compressor.audioUnit
        AudioUnitSetParameter(au, kDynamicsProcessorParam_Threshold, kAudioUnitScope_Global, 0, -26, 0)
        AudioUnitSetParameter(au, kDynamicsProcessorParam_HeadRoom, kAudioUnitScope_Global, 0, 8, 0)
        AudioUnitSetParameter(au, kDynamicsProcessorParam_AttackTime, kAudioUnitScope_Global, 0, 0.004, 0)
        AudioUnitSetParameter(au, kDynamicsProcessorParam_ReleaseTime, kAudioUnitScope_Global, 0, 0.12, 0)

        engine.attach(player)
        engine.attach(eq)
        engine.attach(compressor)
        engine.connect(player, to: eq, format: format)
        engine.connect(eq, to: compressor, format: format)
        engine.connect(compressor, to: engine.mainMixerNode, format: format)
        do {
            try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
            try engine.start()
        } catch {
            throw Failure.failed(error.localizedDescription)
        }
        player.scheduleFile(source, at: nil)
        player.play()

        // Render everything into memory first, so the level can be normalised before writing.
        guard let whole = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: frames),
              let chunk = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: engine.manualRenderingMaximumFrameCount)
        else { throw Failure.failed("out of memory") }
        let channels = Int(engine.manualRenderingFormat.channelCount)
        while engine.manualRenderingSampleTime < AVAudioFramePosition(frames) {
            let left = AVAudioFrameCount(AVAudioFramePosition(frames) - engine.manualRenderingSampleTime)
            let n = min(chunk.frameCapacity, left)
            let status = try engine.renderOffline(n, to: chunk)
            guard status == .success, chunk.frameLength > 0 else {
                if status == .error { throw Failure.failed("render error") }
                continue
            }
            for c in 0..<channels {
                guard let dst = whole.floatChannelData?[c], let src = chunk.floatChannelData?[c] else { continue }
                (dst + Int(whole.frameLength)).update(from: src, count: Int(chunk.frameLength))
            }
            whole.frameLength += chunk.frameLength
        }
        player.stop()
        engine.stop()

        // Normalise to about -1 dBFS.
        var peak: Float = 0
        for c in 0..<channels {
            guard let d = whole.floatChannelData?[c] else { continue }
            for i in 0..<Int(whole.frameLength) { peak = max(peak, abs(d[i])) }
        }
        if peak > 0.0001 {
            let gain = min(8, 0.89 / peak)
            for c in 0..<channels {
                guard let d = whole.floatChannelData?[c] else { continue }
                for i in 0..<Int(whole.frameLength) { d[i] *= gain }
            }
        }

        try? FileManager.default.removeItem(at: output)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: 160_000,
        ]
        do {
            let file = try AVAudioFile(forWriting: output, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            try file.write(from: whole)
        } catch {
            throw Failure.failed(error.localizedDescription)
        }
    }
}
