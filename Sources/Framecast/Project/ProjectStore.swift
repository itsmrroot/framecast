import Foundation
import AppKit
import AVFoundation
import UniformTypeIdentifiers

enum ProjectIO {
    static func load(folder: URL) throws -> ProjectDocument {
        let data = try Data(contentsOf: folder.appendingPathComponent(ProjectFiles.document))
        var doc = try JSONDecoder.framecast.decode(ProjectDocument.self, from: data)
        // Re-decode style leniently so older projects pick up new defaults.
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let style = obj["style"] {
            doc.style = decodeWithDefaults(Style.self, from: style, defaults: Style())
        }
        return doc
    }

    static func save(_ doc: ProjectDocument, folder: URL) {
        do {
            let data = try JSONEncoder.framecast.encode(doc)
            try data.write(to: folder.appendingPathComponent(ProjectFiles.document), options: .atomic)
        } catch {
            NSLog("Framecast: failed to save project: \(error)")
        }
    }

    static func loadCursor(folder: URL) -> CursorTrack {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(ProjectFiles.cursor)),
              let track = try? JSONDecoder().decode(CursorTrack.self, from: data) else { return CursorTrack() }
        return track
    }

    static func loadKeys(folder: URL) -> [KeyEvent] {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(ProjectFiles.keys)),
              let keys = try? JSONDecoder().decode([KeyEvent].self, from: data) else { return [] }
        return keys
    }

    static func saveKeys(_ keys: [KeyEvent], folder: URL) {
        if let data = try? JSONEncoder().encode(keys) {
            try? data.write(to: folder.appendingPathComponent(ProjectFiles.keys), options: .atomic)
        }
    }

    static func saveCursor(_ track: CursorTrack, folder: URL) {
        if let data = try? JSONEncoder().encode(track) {
            try? data.write(to: folder.appendingPathComponent(ProjectFiles.cursor), options: .atomic)
        }
    }
}

extension JSONDecoder {
    static var framecast: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

extension JSONEncoder {
    static var framecast: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}

struct ProjectSummary: Identifiable, Equatable {
    var id: URL { folder }
    let folder: URL
    let name: String
    let createdAt: Date
    let duration: Double
    let thumbnail: NSImage?
    let modified: Date

    static func == (a: ProjectSummary, b: ProjectSummary) -> Bool {
        a.folder == b.folder && a.name == b.name && a.modified == b.modified
    }
}

@MainActor
final class ProjectLibrary: ObservableObject {
    static let shared = ProjectLibrary()

    @Published private(set) var projects: [ProjectSummary] = []

    /// Where projects are saved (Settings → Recording).
    var root: URL {
        URL(fileURLWithPath: (AppSettings.shared.projectsFolder as NSString).expandingTildeInPath, isDirectory: true)
    }

    /// Where the quick export widget puts its files.
    var exportsFolder: URL { root.appendingPathComponent("Exports", isDirectory: true) }

    private init() {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        reload()
    }

    /// A free file name in the Exports folder.
    func uniqueExportURL(name: String, ext: String) -> URL {
        let dir = exportsFolder
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let base = name.replacingOccurrences(of: "/", with: "-")
        var url = dir.appendingPathComponent("\(base).\(ext)")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("\(base) \(n).\(ext)")
            n += 1
        }
        return url
    }

    func changeFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = root
        panel.message = "Choose where Framecast saves new projects"
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        AppSettings.shared.projectsFolder = url.path
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        reload()
    }

    func reload() {
        let fm = FileManager.default
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        let items = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        var result: [ProjectSummary] = []
        let interrupted = items.filter {
            $0.pathExtension == "framecast"
                && !recoveryAttempted.contains($0.standardizedFileURL.path)
                && !importing.contains($0.standardizedFileURL.path)
                && !fm.fileExists(atPath: $0.appendingPathComponent(ProjectFiles.document).path)
                && fm.fileExists(atPath: $0.appendingPathComponent(ProjectFiles.screen).path)
                && RecordingCoordinator.shared.currentFolder?.standardizedFileURL.path != $0.standardizedFileURL.path
                // Another copy of Framecast may still be recording into it.
                && Date().timeIntervalSince((try? $0.appendingPathComponent(ProjectFiles.screen)
                    .resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) > 60
        }
        if !interrupted.isEmpty, !recovering {
            recovering = true
            // Each folder is tried once per launch; an unreadable one must not trigger endless reloads.
            for f in interrupted { recoveryAttempted.insert(f.standardizedFileURL.path) }
            Task {
                var recovered = false
                for folder in interrupted where await ProjectLibrary.recover(folder: folder) { recovered = true }
                recovering = false
                if recovered { reload() }
            }
        }
        for folder in items where folder.pathExtension == "framecast" {
            guard let doc = try? ProjectIO.load(folder: folder) else { continue }
            let thumbURL = folder.appendingPathComponent(ProjectFiles.thumbnail)
            let docURL = folder.appendingPathComponent(ProjectFiles.document)
            let modified = (try? docURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? doc.createdAt
            let duration = EditMap(clips: doc.clips).duration
            result.append(ProjectSummary(folder: folder, name: doc.name, createdAt: doc.createdAt,
                                         duration: duration, thumbnail: NSImage(contentsOf: thumbURL), modified: modified))
        }
        projects = result.sorted { $0.createdAt > $1.createdAt }
    }

    private var recovering = false
    private var recoveryAttempted: Set<String> = []
    /// Folders being filled by an import (no project.json yet), which recovery must leave alone.
    private var importing: Set<String> = []

    /// Turns a recording that was interrupted (Framecast quit while recording) back into a project,
    /// using whatever was written. Recordings are written in fragments, so they're playable up to the last second.
    @discardableResult
    static func recover(folder: URL) async -> Bool {
        let screenURL = folder.appendingPathComponent(ProjectFiles.screen)
        let asset = AVURLAsset(url: screenURL)
        guard let duration = try? await asset.load(.duration).seconds, duration > 0.5,
              let track = try? await asset.loadTracks(withMediaType: .video).first,
              let size = try? await track.load(.naturalSize) else { return false }
        func playable(_ name: String, _ type: AVMediaType) async -> Bool {
            let a = AVURLAsset(url: folder.appendingPathComponent(name))
            guard let d = try? await a.load(.duration).seconds, d > 0.1 else { return false }
            return !((try? await a.loadTracks(withMediaType: type)) ?? []).isEmpty
        }
        let hasWebcam = await playable(ProjectFiles.webcam, .video)
        let hasMic = await playable(ProjectFiles.mic, .audio)
        let hasAudio = !((try? await asset.loadTracks(withMediaType: .audio)) ?? []).isEmpty
        let track2 = ProjectIO.loadCursor(folder: folder)
        let info = RecordingInfo(duration: duration, pointWidth: size.width / 2, pointHeight: size.height / 2,
                                 pixelWidth: Int(size.width), pixelHeight: Int(size.height),
                                 hasWebcam: hasWebcam, hasMic: hasMic, hasSystemAudio: hasAudio,
                                 sourceName: "Recovered recording", hasCursorData: !track2.isEmpty)
        var style = await PresetStore.shared.defaultStyle
        if track2.isEmpty { style.showCursor = false }
        let created = (try? folder.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
        let doc = ProjectDocument(name: "Recovered \(ProjectLibrary.defaultName())", createdAt: created, info: info,
                                  clips: [Clip(start: 0, end: duration)], zooms: [], style: style)
        ProjectIO.save(doc, folder: folder)
        await Thumbnailer.writeRawThumbnail(videoURL: screenURL, to: folder.appendingPathComponent(ProjectFiles.thumbnail))
        return true
    }

    func newProjectFolder() -> URL {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let url = root.appendingPathComponent("Recording \(f.string(from: Date())).framecast", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: url.appendingPathComponent(ProjectFiles.cursors), withIntermediateDirectories: true)
        return url
    }

    static func defaultName() -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return "Recording \(f.string(from: Date()))"
    }

    func delete(_ project: ProjectSummary) {
        WindowManager.shared.closeEditor(folder: project.folder)
        try? FileManager.default.trashItem(at: project.folder, resultingItemURL: nil)
        reload()
    }

    func rename(_ project: ProjectSummary, to name: String) {
        // An open editor would write its old name back on the next save.
        WindowManager.shared.editor(for: project.folder)?.adoptName(name)
        guard var doc = try? ProjectIO.load(folder: project.folder) else { return }
        doc.name = name
        ProjectIO.save(doc, folder: project.folder)
        reload()
    }

    /// Imports an existing video file as a project (no cursor data).
    func importVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a video to edit in Framecast"
        guard panel.runModal() == .OK, let src = panel.url else { return }
        Task { await self.importVideo(from: src) }
    }

    func importVideo(from src: URL) async {
        let folder = newProjectFolder()
        importing.insert(folder.standardizedFileURL.path)
        defer { importing.remove(folder.standardizedFileURL.path) }
        let dst = folder.appendingPathComponent(ProjectFiles.screen)
        do {
            try FileManager.default.copyItem(at: src, to: dst)
            let asset = AVURLAsset(url: dst)
            let duration = try await asset.load(.duration).seconds
            guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw CocoaError(.fileReadCorruptFile) }
            let natural = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let size = natural.applying(transform)
            let w = abs(size.width), h = abs(size.height)
            let hasAudio = !(try await asset.loadTracks(withMediaType: .audio)).isEmpty
            let info = RecordingInfo(duration: duration, pointWidth: w, pointHeight: h, pixelWidth: Int(w), pixelHeight: Int(h),
                                     hasWebcam: false, hasMic: false, hasSystemAudio: hasAudio,
                                     sourceName: src.lastPathComponent, hasCursorData: false)
            var style = PresetStore.shared.defaultStyle
            style.showCursor = false
            let doc = ProjectDocument(name: src.deletingPathExtension().lastPathComponent, createdAt: Date(), info: info,
                                      clips: [Clip(start: 0, end: duration)], zooms: [], style: style)
            ProjectIO.save(doc, folder: folder)
            await Thumbnailer.writeRawThumbnail(videoURL: dst, to: folder.appendingPathComponent(ProjectFiles.thumbnail))
            reload()
            WindowManager.shared.openEditor(folder: folder)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            let alert = NSAlert(error: error)
            alert.messageText = "Could not import video"
            alert.runModal()
        }
    }
}

enum Thumbnailer {
    static func writeRawThumbnail(videoURL: URL, to url: URL) async {
        let asset = AVURLAsset(url: videoURL)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 640, height: 640)
        let duration = (try? await asset.load(.duration).seconds) ?? 0
        let t = CMTime(sec: min(0.5, duration / 2))
        guard let image = try? await gen.image(at: t).image else { return }
        writeJPEG(image, to: url)
    }

    static func writeJPEG(_ image: CGImage, to url: URL) {
        let rep = NSBitmapImageRep(cgImage: image)
        if let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
