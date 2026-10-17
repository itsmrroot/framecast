import SwiftUI
import AppKit
import Carbon.HIToolbox

/// Watch the edited video full screen. It shares the editor's player, so play position carries over.
/// Space plays or pauses, ← → step, Esc (or the button) leaves.
@MainActor
final class FullScreenPlayer: NSObject, NSWindowDelegate {
    private static var current: FullScreenPlayer?

    private let window: NSWindow
    private let model: EditorModel
    private var keyMonitor: Any?

    static func show(model: EditorModel) {
        guard current == nil else { return }
        let p = FullScreenPlayer(model: model)
        current = p
        p.open()
    }

    private init(model: EditorModel) {
        self.model = model
        let screen = NSApp.keyWindow?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        window = NSWindow(contentRect: screen.frame, styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        super.init()
        window.title = model.doc.name
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenPrimary]
        window.delegate = self
        window.contentView = NSHostingView(rootView: FullScreenPlayerView(model: model) { [weak self] in self?.close() })
    }

    private func open() {
        model.scrub(comp: nil)
        window.makeKeyAndOrderFront(nil)
        window.toggleFullScreen(nil)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, self.window.isKeyWindow else { return e }
            switch Int(e.keyCode) {
            case kVK_Space: self.model.togglePlay(); return nil
            case kVK_Escape: self.close(); return nil
            case kVK_LeftArrow: self.model.step(frames: -1); return nil
            case kVK_RightArrow: self.model.step(frames: 1); return nil
            default: return e
            }
        }
    }

    func close() {
        if window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil) // windowDidExitFullScreen finishes closing
        } else {
            finish()
        }
    }

    func windowDidExitFullScreen(_ notification: Notification) { finish() }
    func windowWillClose(_ notification: Notification) { cleanup() }

    private func finish() {
        window.orderOut(nil)
        cleanup()
    }

    private func cleanup() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if FullScreenPlayer.current === self { FullScreenPlayer.current = nil }
    }
}

private struct FullScreenPlayerView: View {
    @ObservedObject var model: EditorModel
    let onClose: () -> Void
    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geo in
            let fit = CGRect(origin: .zero, size: geo.size).aspectFit(aspect: model.outputAspect)
            ZStack {
                Color.black
                PlayerLayerView(player: AVPlayerWrapper(player: model.player))
                    .frame(width: max(1, fit.width), height: max(1, fit.height))
                    .onTapGesture { model.togglePlay() }
                VStack {
                    Spacer()
                    controls.padding(.bottom, 36)
                }
                .opacity(controlsVisible || !model.isPlaying ? 1 : 0)
                .animation(.easeOut(duration: 0.25), value: controlsVisible)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onContinuousHover { _ in poke() }
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .onAppear(perform: poke)
    }

    /// Controls fade out after a couple of seconds without pointer movement while playing.
    private func poke() {
        controlsVisible = true
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if !Task.isCancelled { controlsVisible = false }
        }
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Button { model.togglePlay() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 18, weight: .semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
            Text(formatTime(model.compTime, fraction: false)).font(.system(size: 12, weight: .medium).monospacedDigit())
            Slider(value: Binding(get: { model.compTime }, set: { model.seek(comp: $0) }), in: 0...max(0.1, model.duration))
                .controlSize(.small)
                .tint(.white)
                .frame(width: 420)
            Text(formatTime(model.duration, fraction: false)).font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.6))
            Button(action: onClose) {
                Image(systemName: "arrow.down.right.and.arrow.up.left").font(.system(size: 14, weight: .semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .help("Exit full screen (Esc)")
            .accessibilityLabel("Exit full screen")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12)))
    }
}
