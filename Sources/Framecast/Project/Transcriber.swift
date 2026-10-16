import Foundation
import AVFoundation
import Speech

/// Turns a recording's narration into timed captions using Apple's speech recognizer
/// (on-device when the language supports it, so audio never leaves the Mac).
enum Transcriber {
    enum Failure: LocalizedError {
        case notAuthorized, unavailable(String), noAudio, failed(String)
        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "Framecast needs Speech Recognition permission. Allow it in System Settings → Privacy & Security → Speech Recognition."
            case .unavailable(let lang): return "Speech recognition isn't available for \(lang) right now."
            case .noAudio: return "This recording has no microphone or system audio to transcribe."
            case .failed(let s): return s
            }
        }
    }

    static var supportedLocales: [Locale] {
        SFSpeechRecognizer.supportedLocales()
            .sorted { name(for: $0) < name(for: $1) }
    }

    static func name(for locale: Locale) -> String {
        Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    }

    static func requestAuthorization() async -> Bool {
        let status = await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        return status == .authorized
    }

    /// Transcribes the project's audio (microphone if recorded, otherwise system audio) in chunks.
    static func transcribe(folder: URL, info: RecordingInfo, locale: Locale,
                           progress: @escaping @Sendable (Double) -> Void) async throws -> [CaptionCue] {
        guard await requestAuthorization() else { throw Failure.notAuthorized }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw Failure.unavailable(name(for: locale))
        }

        let micURL = folder.appendingPathComponent(ProjectFiles.mic)
        let sourceURL: URL
        if info.hasMic, FileManager.default.fileExists(atPath: micURL.path) {
            sourceURL = micURL
        } else if info.hasSystemAudio {
            sourceURL = folder.appendingPathComponent(ProjectFiles.screen)
        } else {
            throw Failure.noAudio
        }
        let asset = AVURLAsset(url: sourceURL)
        guard try await !asset.loadTracks(withMediaType: .audio).isEmpty else { throw Failure.noAudio }
        let duration = try await asset.load(.duration).seconds

        // Recognition works best on short files, so transcribe ~50 s chunks with a little overlap.
        let chunk = 50.0, overlap = 1.0
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("framecast-asr-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        var words: [(t: Double, d: Double, s: String)] = []
        var start = 0.0
        var index = 0
        while start < duration - 0.3 {
            try Task.checkCancellation()
            let end = min(duration, start + chunk)
            let url = tmp.appendingPathComponent("chunk\(index).m4a")
            try await exportAudio(asset: asset, from: start, to: end, to: url)
            let segments = try await recognize(url: url, recognizer: recognizer)
            // Neighbouring chunks overlap by `overlap` seconds; split the overlap in the middle so a word at
            // the edge of one chunk (often cut off) comes from the next chunk, where it's whole.
            let keepFrom = index == 0 ? 0 : overlap / 2
            let keepUntil = end >= duration ? Double.infinity : (end - start) - overlap / 2
            for seg in segments where seg.timestamp >= keepFrom && seg.timestamp < keepUntil {
                words.append((start + seg.timestamp, seg.duration, seg.substring))
            }
            progress(min(0.99, end / duration))
            index += 1
            start = end - overlap
            if end >= duration { break }
        }
        progress(1)
        return group(words)
    }

    private static func exportAudio(asset: AVAsset, from: Double, to: Double, to url: URL) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw Failure.failed("Couldn't prepare the audio for transcription.")
        }
        session.timeRange = CMTimeRange(start: CMTime(sec: from), end: CMTime(sec: to))
        try await session.export(to: url, as: .m4a)
    }

    private static func recognize(url: URL, recognizer: SFSpeechRecognizer) async throws -> [SFTranscriptionSegment] {
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        return try await withCheckedThrowingContinuation { cont in
            var finished = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !finished else { return }
                if let result, result.isFinal {
                    finished = true
                    cont.resume(returning: result.bestTranscription.segments)
                } else if let error {
                    finished = true
                    // "No speech detected" is not a failure: the chunk is just silent.
                    let ns = error as NSError
                    if ns.domain == "kAFAssistantErrorDomain" && (ns.code == 1110 || ns.code == 203) {
                        cont.resume(returning: [])
                    } else {
                        cont.resume(throwing: Failure.failed(error.localizedDescription))
                    }
                }
            }
        }
    }

    /// Groups words into readable caption lines: up to ~42 characters or 4.5 s, breaking at pauses and sentence ends.
    static func group(_ words: [(t: Double, d: Double, s: String)]) -> [CaptionCue] {
        var cues: [CaptionCue] = []
        var text = ""
        var cueStart = 0.0, cueEnd = 0.0
        func flush() {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { cues.append(CaptionCue(start: cueStart, end: cueEnd, text: trimmed)) }
            text = ""
        }
        for w in words.sorted(by: { $0.t < $1.t }) {
            let wEnd = w.t + max(0.15, w.d)
            if !text.isEmpty && (w.t - cueEnd > 0.8 || text.count + w.s.count + 1 > 42 || wEnd - cueStart > 4.5) {
                flush()
            }
            if text.isEmpty { cueStart = w.t }
            text += (text.isEmpty ? "" : " ") + w.s
            cueEnd = wEnd
            if let last = w.s.last, ".?!".contains(last), text.count > 12 { flush() }
        }
        flush()
        // Hold each line a little longer when there's room before the next one.
        for i in cues.indices {
            let next = i + 1 < cues.count ? cues[i + 1].start : cues[i].end + 1
            cues[i].end = max(cues[i].start + 0.1, min(next - 0.05, cues[i].end + 0.6))
        }
        return cues
    }
}
