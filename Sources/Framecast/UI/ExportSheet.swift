import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ExportSheet: View {
    @ObservedObject var model: EditorModel
    @Binding var isPresented: Bool

    enum Phase: Equatable {
        case setup
        case exporting
        case done(URL)
        case failed(String)
    }

    @State private var settings = AppSettings.shared.exportSettings
    @State private var phase: Phase = .setup
    @State private var progress: Double = 0
    @State private var exporter: Exporter?
    @State private var startedAt = Date()
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "square.and.arrow.up").foregroundStyle(Theme.accent)
                Text("Export").font(.system(size: 16, weight: .semibold))
                Spacer()
            }

            switch phase {
            case .setup: setup
            case .exporting: exporting
            case .done(let url): done(url)
            case .failed(let msg): failed(msg)
            }
        }
        .padding(22)
        .frame(width: 600)
        .background(Theme.panel)
        .focusEffectDisabled() // no leftover focus ring on the format tile
    }

    // MARK: Setup

    private var setup: some View {
        VStack(alignment: .leading, spacing: 16) {
            PillPicker(options: ExportFormat.allCases, selection: $settings.format, label: \.label)

            if settings.format == .mp4 {
                row("Resolution") {
                    Picker("", selection: $settings.resolution) {
                        ForEach(ExportResolution.allCases) { r in Text(r.label).tag(r) }
                    }.labelsHidden().pickerStyle(.segmented).frame(width: 260)
                }
                row("Frame rate") {
                    // Segmented, not pop-up menus: Esc in an open pop-up closed the whole sheet.
                    Picker("", selection: $settings.fps) {
                        ForEach(ExportSettings.frameRates, id: \.self) { Text("\($0)").tag($0) }
                    }.labelsHidden().pickerStyle(.segmented).frame(width: 300)
                    Text("fps").font(.system(size: 11)).foregroundStyle(Theme.textDim)
                }
                row("Compression") {
                    Picker("", selection: $settings.quality) {
                        ForEach(ExportQuality.allCases) { q in Text(q.label).tag(q) }
                    }.labelsHidden().pickerStyle(.segmented).frame(width: 380)
                }
                Text(settings.quality.detail)
                    .font(.system(size: 11)).foregroundStyle(Theme.textDim)
                row("Codec") {
                    Picker("", selection: $settings.codec) {
                        ForEach(ExportCodec.allCases) { c in Text(c.label).tag(c) }
                    }.labelsHidden().pickerStyle(.segmented).frame(width: 340)
                }
            } else {
                row("Width") {
                    Picker("", selection: $settings.gifWidth) {
                        Text("640").tag(640); Text("800").tag(800); Text("960").tag(960); Text("1280").tag(1280)
                    }.labelsHidden().pickerStyle(.segmented).frame(width: 260)
                }
                row("Frame rate") {
                    Picker("", selection: $settings.gifFPS) {
                        Text("10").tag(10); Text("15").tag(15); Text("20").tag(20); Text("30").tag(30)
                    }.labelsHidden().pickerStyle(.segmented).frame(width: 260)
                }
            }

            summary

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("Export…") { start() }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var summary: some View {
        let size = outputSize
        let duration = model.duration
        var text = "\(Int(size.width)) × \(Int(size.height)) · \(formatTime(duration))"
        if settings.format == .mp4 {
            let bitrate = size.width * size.height * Double(settings.fps) * settings.quality.bitsPerPixel
            // The bitrate is the most the encoder may use. Screen recordings are mostly still between frames, so
            // they usually come out at a quarter to a third of it (a 4K test: 450 MB budget, 121 MB file).
            let mb = bitrate * duration / 8 / 1_000_000
            text += String(format: " · about %.0f–%.0f MB", max(1, mb * 0.25), max(1, mb))
        } else {
            // Rough: screen recordings compress to about 0.1 byte per pixel per frame as GIF.
            let mb = size.width * size.height * Double(settings.gifFPS) * duration * 0.1 / 1_000_000
            text += String(format: " · roughly %.0f MB", max(1, mb))
        }
        return Text(text)
            .font(.system(size: 11.5).monospacedDigit())
            .foregroundStyle(Theme.textDim)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.fill.opacity(0.05)))
    }

    private var outputSize: CGSize {
        guard let job = model.built.map({ model.makeRenderModel(for: $0) }) else { return .zero }
        return settings.format == .mp4 ? job.outputSize(shortSide: settings.resolution.rawValue) : job.outputSize(longSide: settings.gifWidth)
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.text)
            Spacer()
            content()
        }
    }

    // MARK: Progress

    private var exporting: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProgressView(value: progress).tint(Theme.accent)
            HStack {
                Text("Rendering… \(Int(progress * 100))%")
                Spacer()
                Text(remaining).foregroundStyle(Theme.textDim)
            }
            .font(.system(size: 12).monospacedDigit())
            HStack {
                Spacer()
                Button("Cancel") {
                    exporter?.cancel()
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private var remaining: String {
        guard progress > 0.03 else { return "" }
        let elapsed = Date().timeIntervalSince(startedAt)
        let left = elapsed / progress * (1 - progress)
        return "about \(formatTime(left)) left"
    }

    private func done(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 26)).foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Export complete").font(.system(size: 13, weight: .semibold))
                    Text(url.lastPathComponent).font(.system(size: 11)).foregroundStyle(Theme.textDim).lineLimit(1)
                }
            }
            HStack {
                Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: { Label("Show in Finder", systemImage: "folder") }
                    .buttonStyle(SecondaryButtonStyle())
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([url as NSURL])
                    copied = true
                } label: { Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc") }
                    .buttonStyle(SecondaryButtonStyle())
                Button { NSWorkspace.shared.open(url) } label: { Label("Open", systemImage: "play.rectangle") }
                    .buttonStyle(SecondaryButtonStyle())
                Spacer()
                Button("Done") { isPresented = false }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func failed(_ msg: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(msg, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
            HStack {
                Spacer()
                Button("Back") { phase = .setup }.buttonStyle(SecondaryButtonStyle())
                Button("Close") { isPresented = false }.buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    // MARK: Run

    private func start() {
        let panel = SavePanels.make(name: model.doc.name, ext: settings.format.fileExtension,
                                    types: [settings.format == .mp4 ? .mpeg4Movie : .gif])
        guard let url = SavePanels.run(panel) else { return }
        guard let job = model.exportJob() else { return }

        model.player.pause()
        let exp = Exporter()
        exporter = exp
        progress = 0
        startedAt = Date()
        phase = .exporting
        let s = settings
        Task {
            do {
                try await exp.export(job: job, settings: s, to: url) { p in
                    DispatchQueue.main.async { progress = p }
                }
                phase = .done(url)
            } catch Exporter.ExportError.cancelled {
                phase = .setup
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }
}
