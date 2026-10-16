import Foundation
import AppKit
import CryptoKit
import SwiftUI

/// Checks GitHub for a newer release and installs it.
///
/// The zip for this Mac's chip is downloaded into Framecast's own support folder, checked against the
/// SHA-256 digest GitHub publishes, and unpacked. Once the app has quit, a small script swaps the new
/// bundle in and starts it. If the app's folder isn't writable, the download is opened for the user instead.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    static let repo = "itsmrroot/framecast"
    static let releasesPage = URL(string: "https://github.com/\(repo)/releases/latest")!
    private static let latestAPI = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!

    struct Release: Equatable {
        /// Without the leading "v".
        let version: String
        let page: URL
        let notes: String
        /// The zip for this Mac, if it has been published.
        let asset: Asset?
    }

    struct Asset: Equatable {
        let name: String
        let url: URL
        let size: Int64
        let sha256: String?
    }

    enum Phase: Equatable {
        case idle, checking, upToDate
        case downloading(Double)
        case installing
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    /// The newer release found, if any.
    @Published private(set) var release: Release?
    @Published var autoCheck: Bool {
        didSet { UserDefaults.standard.set(autoCheck, forKey: "update.auto") }
    }

    private var downloadTask: URLSessionDownloadTask?
    private var progressObservation: NSKeyValueObservation?
    private var window: NSWindow?

    private init() {
        UserDefaults.standard.register(defaults: ["update.auto": true])
        autoCheck = UserDefaults.standard.bool(forKey: "update.auto")
    }

    /// The version of this copy. `FRAMECAST_PRETEND_VERSION` pretends to be older, to try updating.
    static var currentVersion: String {
        if let v = ProcessInfo.processInfo.environment["FRAMECAST_PRETEND_VERSION"], !v.isEmpty { return v }
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    /// The release file for this Mac ends in this, e.g. `Framecast-1.2.0-macOS-arm64.zip`.
    static var assetSuffix: String {
        #if arch(arm64)
        return "-macOS-arm64.zip"
        #else
        return "-macOS-x86_64.zip"
        #endif
    }

    /// `1.2.3` or `v1.2.3` as numbers; anything after the numbers is ignored.
    static func parseVersion(_ v: String) -> [Int]? {
        var s = Substring(v.trimmingCharacters(in: .whitespaces))
        if s.hasPrefix("v") { s = s.dropFirst() }
        let parts = s.split(whereSeparator: { ".-+".contains($0) }).prefix(3).map { Int($0) }
        guard parts.count == 3, parts.allSatisfy({ $0 != nil }) else { return nil }
        return parts.map { $0! }
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let a = parseVersion(candidate), let b = parseVersion(current) else { return false }
        if a != b { return b.lexicographicallyPrecedes(a) }
        // Same numbers: a final release (1.2.0) is newer than a pre-release (1.2.0-beta.1).
        return isPrerelease(current) && !isPrerelease(candidate)
    }

    static func isPrerelease(_ v: String) -> Bool {
        v.trimmingCharacters(in: .whitespaces).contains("-")
    }

    /// Leaf certificate of the release signing identity. Once a release build is installed, updates must be
    /// signed with the same certificate, so a tampered download can't install itself.
    nonisolated static let releaseCertificateHash = "dec07d59af7d6f3f3250b1301b49394ff333fd22"

    // MARK: Checking

    /// Quiet check at launch: only shows something if there is an update.
    func checkOnLaunch() {
        // Whatever an earlier update left behind (the new version is running now).
        try? FileManager.default.removeItem(at: Self.updateFolder)
        guard autoCheck else { return }
        Task { await check(manual: false) }
    }

    /// A manual check opens the update window with its result.
    func check(manual: Bool) async {
        if case .downloading = phase { return }
        if phase == .checking || phase == .installing { return }
        phase = .checking
        if manual { showWindow() }
        do {
            release = try await Self.fetchLatest()
            // A quiet check is announced by the badge on the home screen; nothing pops up on its own.
            phase = release == nil ? .upToDate : .idle
        } catch {
            phase = manual ? .failed("Couldn't check for updates: \(error.localizedDescription)") : .idle
        }
    }

    static func fetchLatest() async throws -> Release? {
        var request = URLRequest(url: latestAPI, timeoutInterval: 30)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Framecast/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 404 { return nil } // no releases yet
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        struct GHAsset: Decodable { let name: String; let size: Int64; let browser_download_url: URL; let digest: String? }
        struct GHRelease: Decodable {
            let tag_name: String; let html_url: URL; let body: String?
            let draft: Bool?; let prerelease: Bool?; let assets: [GHAsset]
        }
        let gh = try JSONDecoder().decode(GHRelease.self, from: data)
        var version = gh.tag_name
        if version.hasPrefix("v") { version.removeFirst() }
        guard gh.draft != true, gh.prerelease != true, isNewer(version, than: currentVersion) else { return nil }
        let asset = gh.assets.first { $0.name.hasSuffix(assetSuffix) }.map { a in
            Asset(name: a.name, url: a.browser_download_url, size: a.size,
                  sha256: a.digest.flatMap { $0.hasPrefix("sha256:") ? String($0.dropFirst(7)).lowercased() : nil })
        }
        return Release(version: version, page: gh.html_url, notes: gh.body ?? "", asset: asset)
    }

    // MARK: Installing

    /// Whether "Update Now" can install it here, rather than open the download page.
    var canInstall: Bool {
        let app = Bundle.main.bundleURL
        guard release?.asset != nil, app.pathExtension == "app",
              !app.path.contains("/AppTranslocation/"), !app.path.hasPrefix("/Volumes/") else { return false }
        let fm = FileManager.default
        return fm.isWritableFile(atPath: app.deletingLastPathComponent().path) && fm.isWritableFile(atPath: app.path)
    }

    func updateNow() {
        guard let release, let asset = release.asset else {
            NSWorkspace.shared.open(release?.page ?? Self.releasesPage)
            return
        }
        guard !RecordingCoordinator.shared.isActive else {
            phase = .failed("Finish your recording first, then update.")
            return
        }
        let dir = Self.updateFolder
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        phase = .downloading(0)
        let task = URLSession.shared.downloadTask(with: asset.url) { [weak self] tmp, response, error in
            // The temporary file is deleted when this returns, so move it first.
            var moved: URL?
            if let tmp, error == nil {
                let dest = dir.appendingPathComponent("update.zip")
                if (try? FileManager.default.moveItem(at: tmp, to: dest)) != nil { moved = dest }
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            DispatchQueue.main.async {
                self?.downloadFinished(file: moved, status: status, error: error, release: release, asset: asset)
            }
        }
        progressObservation = task.progress.observe(\.fractionCompleted) { [weak self] p, _ in
            let f = p.fractionCompleted
            DispatchQueue.main.async {
                if case .downloading = self?.phase { self?.phase = .downloading(f) }
            }
        }
        downloadTask = task
        task.resume()
    }

    func cancelDownload() {
        downloadTask?.cancel()
    }

    private func downloadFinished(file: URL?, status: Int, error: Error?, release: Release, asset: Asset) {
        downloadTask = nil
        progressObservation = nil
        if let error = error as? URLError, error.code == .cancelled {
            phase = .idle
            return
        }
        guard let file, status == 200 else {
            phase = .failed("The download failed: \(error?.localizedDescription ?? "HTTP \(status)")")
            return
        }
        phase = .installing
        Task.detached(priority: .userInitiated) {
            do {
                let staged = try Self.prepare(file: file, release: release, asset: asset)
                await MainActor.run { self.install(staged: staged, zip: file) }
            } catch {
                await MainActor.run { self.phase = .failed(error.localizedDescription) }
            }
        }
    }

    private struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ s: String) { errorDescription = s }
    }

    /// Checks the download and unpacks it. Returns the new .app.
    nonisolated private static func prepare(file: URL, release: Release, asset: Asset) throws -> URL {
        let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
        guard (attrs[.size] as? NSNumber)?.int64Value == asset.size else { throw Failure("The download is incomplete.") }
        guard let want = asset.sha256 else { throw Failure("The release has no checksum, so it can't be verified.") }
        guard try sha256(of: file) == want else { throw Failure("The download is damaged (checksum mismatch).") }
        let out = file.deletingLastPathComponent().appendingPathComponent("unpacked", isDirectory: true)
        try? FileManager.default.removeItem(at: out)
        try run("/usr/bin/ditto", ["-x", "-k", file.path, out.path])
        guard let app = try FileManager.default.contentsOfDirectory(at: out, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" }),
              let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
              info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier else {
            throw Failure("The download doesn't contain Framecast.")
        }
        guard (info["CFBundleShortVersionString"] as? String) == release.version else {
            throw Failure("The download has an unexpected version.")
        }
        try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path])
        try run("/usr/bin/codesign", ["--verify", "--deep", app.path])
        if runningReleaseBuild {
            let requirement = "identifier \"\(Bundle.main.bundleIdentifier ?? "com.framecast.app")\" and certificate leaf = H\"\(releaseCertificateHash)\""
            do {
                try run("/usr/bin/codesign", ["--verify", "--deep", "-R=\(requirement)", app.path])
            } catch {
                throw Failure("The download isn't signed by Framecast's release certificate.")
            }
        }
        return app
    }

    nonisolated private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    @discardableResult
    nonisolated private static func run(_ tool: String, _ args: [String]) throws -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw Failure("\(URL(fileURLWithPath: tool).lastPathComponent) failed while installing the update.") }
        return p.terminationStatus
    }

    /// Swaps the new bundle in once the app has quit, then starts it.
    private func install(staged: URL, zip: URL) {
        guard !RecordingCoordinator.shared.isActive else {
            phase = .failed("A recording started while the update downloaded. Finish it, then choose Update Now again.")
            return
        }
        let app = Bundle.main.bundleURL
        let parent = app.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            // No rights to replace the app: let the user drag the new one over.
            NSWorkspace.shared.activateFileViewerSelecting([staged])
            phase = .failed("Framecast can't replace itself in \(parent.path). Drag the new version (shown in Finder) into that folder.")
            return
        }
        func q(_ u: URL) -> String { "'" + u.path.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let next = app.deletingPathExtension().appendingPathExtension("app.new")
        let old = app.deletingPathExtension().appendingPathExtension("app.old")
        let rescue = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0].appendingPathComponent("Framecast.app")
        // Swap by renaming, so the current app is only deleted once the new one is in place, and is put back
        // if anything fails. On failure the new version is copied to Downloads (the update folder is cleaned later).
        let script = """
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.3; done
        rm -rf \(q(next)) \(q(old))
        if ditto \(q(staged)) \(q(next)) && mv \(q(app)) \(q(old)); then
          if mv \(q(next)) \(q(app)); then
            rm -rf \(q(old))
            open \(q(app))
            exit 0
          fi
          mv \(q(old)) \(q(app))
        fi
        rm -rf \(q(next))
        ditto \(q(staged)) \(q(rescue)) && open -R \(q(rescue))
        open \(q(app))
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "(\(script)) >/dev/null 2>&1 &"]
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            phase = .failed("Couldn't start the installer: \(error.localizedDescription)")
            return
        }
        NSApp.terminate(nil)
    }

    /// Whether this copy is signed with the release certificate (not a local development build).
    nonisolated static var runningReleaseBuild: Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        p.arguments = ["-dr", "-", Bundle.main.bundlePath]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        guard (try? p.run()) != nil else { return false }
        p.waitUntilExit()
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return out.lowercased().contains(releaseCertificateHash)
    }

    static var updateFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Framecast/Update", isDirectory: true)
    }

    // MARK: Window

    func showWindow() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
                         styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        w.backgroundColor = Theme.nsPanel
        w.contentView = NSHostingView(rootView: UpdateView(updater: self))
        w.center()
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.window = nil }
        }
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeWindow() { window?.close() }
}

// MARK: - Views

struct UpdateView: View {
    @ObservedObject var updater: Updater

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill").font(.system(size: 26)).foregroundStyle(Theme.accent)
                Text(title).font(.system(size: 16, weight: .semibold))
                Spacer()
            }
            content
        }
        .padding(22)
        .padding(.top, 8)
        .frame(width: 460, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.panel)
    }

    private var title: String {
        if updater.release != nil { return "Update available" }
        switch updater.phase {
        case .checking: return "Checking for updates…"
        case .upToDate: return "You're up to date"
        default: return "Software update"
        }
    }

    @ViewBuilder
    private var content: some View {
        if let release = updater.release {
            Text("Framecast \(release.version) is available. You have version \(Updater.currentVersion).")
                .font(.system(size: 12.5))
            if !release.notes.isEmpty {
                ScrollView {
                    Text(release.notes)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 140)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.fill.opacity(0.05)))
            }
            Link(destination: release.page) { Label("What's new", systemImage: "list.bullet") }
                .font(.system(size: 12))

            switch updater.phase {
            case .downloading(let f):
                ProgressView(value: f).tint(Theme.accent)
                HStack {
                    Text("Downloading… \(Int(f * 100))%").font(.system(size: 11.5)).foregroundStyle(Theme.textDim)
                    Spacer()
                    Button("Cancel") { updater.cancelDownload() }.buttonStyle(SecondaryButtonStyle())
                }
            case .installing:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Installing… Framecast will restart.").font(.system(size: 11.5)).foregroundStyle(Theme.textDim)
                }
            default:
                Text(updater.canInstall
                     ? "Framecast will close, install the update and open again. Your projects are saved first."
                     : "This copy can't update itself, so the download page will open.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
                if case .failed(let msg) = updater.phase { failure(msg) }
                HStack {
                    Spacer()
                    Button("Later") { updater.closeWindow() }
                        .buttonStyle(SecondaryButtonStyle())
                        .keyboardShortcut(.cancelAction)
                    Button(updater.canInstall ? "Update Now" : "Open Download Page") {
                        if updater.canInstall { updater.updateNow() } else {
                            NSWorkspace.shared.open(release.page)
                            updater.closeWindow()
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                }
            }
        } else {
            switch updater.phase {
            case .checking:
                ProgressView().controlSize(.small)
            case .upToDate:
                Text("Framecast \(Updater.currentVersion) is the latest version.").font(.system(size: 12.5))
            case .failed(let msg):
                failure(msg)
            default:
                EmptyView()
            }
            HStack {
                Spacer()
                Button("OK") { updater.closeWindow() }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func failure(_ msg: String) -> some View {
        Label(msg, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 11.5)).foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// "Update to x.y.z" pill for the home screen.
struct UpdateBadge: View {
    @ObservedObject var updater = Updater.shared

    var body: some View {
        if let release = updater.release {
            Button {
                updater.showWindow()
            } label: {
                Label("Update to \(release.version)", systemImage: "arrow.down.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(Theme.accent))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .help("A new version of Framecast is available")
        }
    }
}
