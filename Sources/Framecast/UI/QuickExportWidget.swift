import SwiftUI
import AppKit

/// Shown after a recording (if enabled in Settings → Quick export): export with the quick export settings
/// and copy the file, open the editor, or throw the recording away.
@MainActor
final class QuickExportWidget: ObservableObject {
    static let shared = QuickExportWidget()

    enum Phase: Equatable { case ready, exporting(Double), done(URL), failed(String) }

    @Published private(set) var phase: Phase = .ready
    @Published private(set) var name = ""
    @Published private(set) var thumbnail: NSImage?
    private(set) var folder: URL?
    private var panel: NSPanel?
    private var exporter: Exporter?
    private var task: Task<Void, Never>?
    private var autoClose: Task<Void, Never>?
    /// While the pointer is over the widget, it doesn't close by itself.
    var hovering = false
    /// Whether the finished export was copied to the clipboard (vs. saved to a chosen file).
    @Published private(set) var copied = false

    func show(folder: URL) {
        close()
        self.folder = folder
        phase = .ready
        name = (try? ProjectIO.load(folder: folder).name) ?? "Recording"
        thumbnail = NSImage(contentsOf: folder.appendingPathComponent(ProjectFiles.thumbnail))
        let host = NSHostingView(rootView: QuickExportView(widget: self))
        let size = CGSize(width: 340, height: host.fittingSize.height)
        let screen = NSScreen.withMouse
        let p = FloatingPanel(contentRect: CGRect(x: screen.visibleFrame.maxX - size.width - 20, y: screen.visibleFrame.minY + 20,
                                                  width: size.width, height: size.height))
        p.level = .floating
        p.isMovableByWindowBackground = true
        p.contentView = host
        p.orderFrontRegardless()
        panel = p
        DispatchQueue.main.async {
            let h = host.fittingSize.height
            p.setFrame(CGRect(x: p.frame.minX, y: screen.visibleFrame.minY + 20, width: size.width, height: h), display: true)
        }
    }

    func close() {
        task?.cancel()
        task = nil
        autoClose?.cancel()
        autoClose = nil
        exporter?.cancel()
        exporter = nil
        panel?.orderOut(nil)
        panel = nil
    }

    func edit() {
        guard let folder else { return }
        close()
        WindowManager.shared.openEditor(folder: folder)
    }

    func delete() {
        guard let folder else { return }
        close()
        try? FileManager.default.trashItem(at: folder, resultingItemURL: nil)
        ProjectLibrary.shared.reload()
    }

    /// Exports with the quick export settings. `destination` nil = Exports folder + clipboard.
    func export(to destination: URL? = nil) {
        guard let folder else { return }
        phase = .exporting(0)
        let settings = AppSettings.shared.exportSettings
        let name = self.name
        // Everything below belongs to this folder; a newer recording's widget must not be touched.
        func current() -> Bool { self.folder == folder && !Task.isCancelled }
        task = Task {
            do {
                let model = try EditorModel(folder: folder)
                for _ in 0..<200 where !model.isReady && model.loadError == nil { try await Task.sleep(nanoseconds: 50_000_000) }
                guard current() else { return }
                guard let job = model.exportJob() else { throw Exporter.ExportError.failed(model.loadError ?? "The recording couldn't be loaded.") }
                let url = destination ?? ProjectLibrary.shared.uniqueExportURL(name: name, ext: settings.format.fileExtension)
                guard current() else { return }
                let exp = Exporter()
                exporter = exp
                try await exp.export(job: job, settings: settings, to: url) { p in
                    DispatchQueue.main.async {
                        guard self.folder == folder, case .exporting = self.phase else { return }
                        self.phase = .exporting(p)
                    }
                }
                guard current() else { return }
                exporter = nil
                if destination == nil {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([url as NSURL])
                }
                copied = destination == nil
                phase = .done(url)
                scheduleAutoClose()
            } catch Exporter.ExportError.cancelled {
                if current() { phase = .ready }
            } catch {
                if current() { phase = .failed(error.localizedDescription) }
            }
        }
    }

    /// "Export complete" goes away after about 8 s without the pointer over it.
    private func scheduleAutoClose() {
        autoClose?.cancel()
        autoClose = Task { [weak self] in
            var left = 8.0
            while left > 0 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard let self, !Task.isCancelled else { return }
                left = self.hovering ? 8 : left - 0.5
            }
            guard let self, case .done = self.phase else { return }
            self.close()
        }
    }
}

private struct QuickExportView: View {
    @ObservedObject var widget: QuickExportWidget

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Group {
                    if let img = widget.thumbnail {
                        Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle().fill(Theme.fill.opacity(0.08))
                    }
                }
                .frame(width: 96, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(widget.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(status).font(.system(size: 11)).foregroundStyle(Theme.textDim).lineLimit(2)
                }
                Spacer(minLength: 0)
                Button { widget.close() } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                    .buttonStyle(.plain).foregroundStyle(Theme.textDim).help("Close")
                    .accessibilityLabel("Close")
            }
            switch widget.phase {
            case .exporting(let p):
                ProgressView(value: p).tint(Theme.accent)
            case .done(let url):
                HStack {
                    Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: { Label("Show in Finder", systemImage: "folder") }
                        .buttonStyle(SecondaryButtonStyle())
                    Spacer()
                    Button("Done") { widget.close() }.buttonStyle(PrimaryButtonStyle())
                }
            default:
                HStack(spacing: 8) {
                    Button { widget.export() } label: { Label("Export & Copy", systemImage: "square.and.arrow.up") }
                        .buttonStyle(PrimaryButtonStyle())
                    Button { widget.edit() } label: { Label("Edit", systemImage: "slider.horizontal.3") }
                        .buttonStyle(SecondaryButtonStyle())
                    Spacer()
                    Button { widget.delete() } label: { Image(systemName: "trash") }
                        .buttonStyle(SecondaryButtonStyle())
                        .help("Move the recording to the Trash")
                        .accessibilityLabel("Move recording to Trash")
                }
            }
        }
        .padding(16)
        .frame(width: 340)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.border)))
        .preferredColorScheme(.dark)
        .onHover { widget.hovering = $0 }
    }

    private var status: String {
        switch widget.phase {
        case .ready:
            let s = AppSettings.shared.exportSettings
            return s.format == .gif ? "GIF" : "MP4 · \(s.resolution.label) · \(s.fps) fps · \(s.quality.label)"
        case .exporting(let p): return "Exporting… \(Int(p * 100))%"
        case .done: return widget.copied ? "Exported and copied. Paste it anywhere." : "Exported and saved."
        case .failed(let msg): return msg
        }
    }
}
