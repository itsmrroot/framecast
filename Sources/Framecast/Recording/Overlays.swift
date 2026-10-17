import AppKit
import SwiftUI
import Carbon.HIToolbox

// MARK: - Countdown

/// "Get ready" pill: cancel, or Continue to skip the rest of the countdown.
@MainActor
private final class CountdownModel: ObservableObject {
    @Published var progress: Double = 0
    @Published var remaining: Int
    var skipped = false
    var cancelled = false
    init(_ seconds: Int) { remaining = seconds }
}

private struct CountdownPill: View {
    @ObservedObject var model: CountdownModel

    var body: some View {
        HStack(spacing: 14) {
            Button { model.cancelled = true } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.black)
                    .frame(width: 24, height: 24).background(Circle().fill(Color.white.opacity(0.9)))
            }
            .buttonStyle(.plain)
            .help("Cancel")
            .accessibilityLabel("Cancel recording")
            VStack(alignment: .leading, spacing: 1) {
                Text("Get ready…").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                Text("Recording starts in \(model.remaining)s").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.easeOut(duration: 0.2), value: model.remaining)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Recording starts in \(model.remaining) seconds")
            Button { model.skipped = true } label: {
                HStack(spacing: 8) {
                    ZStack {
                        Circle().stroke(Color.white.opacity(0.3), lineWidth: 2.5)
                        Circle().trim(from: 0, to: model.progress).stroke(Color.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 16, height: 16)
                    Text("Continue").font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14).frame(height: 34)
                .background(Capsule().fill(Theme.accent))
            }
            .buttonStyle(.plain)
            .help("Start recording now")
            .accessibilityLabel("Start recording now")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Countdown")
        .padding(.horizontal, 14)
        .frame(height: 58)
        .background(Capsule().fill(Color(white: 0.1).opacity(0.96)).overlay(Capsule().strokeBorder(Color.white.opacity(0.12))))
        .fixedSize()
    }
}

@MainActor
enum Countdown {
    /// Returns false if the user cancelled.
    static func run(seconds: Int, on screen: NSScreen) async -> Bool {
        guard seconds > 0 else { return true }
        let model = CountdownModel(seconds)
        let host = NSHostingView(rootView: CountdownPill(model: model))
        let size = host.fittingSize
        let panel = FloatingPanel(contentRect: CGRect(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2,
                                                      width: size.width, height: size.height))
        panel.level = .screenSaver
        panel.contentView = host
        panel.orderFrontRegardless()
        let start = Date()
        var lastSecond = -1
        while !model.skipped && !model.cancelled {
            let elapsed = Date().timeIntervalSince(start)
            if elapsed >= Double(seconds) { break }
            model.progress = elapsed / Double(seconds)
            let left = seconds - Int(elapsed)
            if left != lastSecond {
                lastSecond = left
                model.remaining = left
                NSSound(named: "Tink")?.play()
            }
            try? await Task.sleep(nanoseconds: 33_000_000)
        }
        panel.orderOut(nil)
        return !model.cancelled
    }
}

// MARK: - Floating recording controls

struct RecordingControlsView: View {
    @ObservedObject var coordinator: RecordingCoordinator
    /// Restart and Discard throw away the take, so after 10 s they need a second click (a dialog would be recorded).
    @State private var confirming: Action?
    @State private var confirmTask: Task<Void, Never>?

    enum Action { case restart, discard }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(coordinator.phase == .paused ? Color.orange : Color.red)
                .frame(width: 10, height: 10)
                .opacity(coordinator.phase == .paused ? 1 : (Int(coordinator.elapsed * 2) % 2 == 0 ? 1 : 0.4))
            Text(confirming == nil ? formatTime(coordinator.elapsed) : "Sure?")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(minWidth: 44, alignment: .leading)

            Divider().frame(height: 18).overlay(Color.white.opacity(0.2))

            ControlButton(icon: "stop.fill", tint: .red, help: "Stop recording (⌘⇧2)", label: "Stop recording") {
                coordinator.stop()
            }
            ControlButton(icon: coordinator.phase == .paused ? "play.fill" : "pause.fill", help: "Pause / resume",
                          label: coordinator.phase == .paused ? "Resume recording" : "Pause recording") {
                coordinator.togglePause()
            }
            if confirming == .restart {
                confirmButton("arrow.counterclockwise", "Click again to restart") { coordinator.restart() }
            } else {
                ControlButton(icon: "arrow.counterclockwise", help: "Restart recording", label: "Restart recording") {
                    guarded(.restart) { coordinator.restart() }
                }
            }
            if confirming == .discard {
                confirmButton("trash", "Click again to discard") { coordinator.cancel() }
            } else {
                ControlButton(icon: "trash", help: "Cancel and discard", label: "Discard recording") {
                    guarded(.discard) { coordinator.cancel() }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            Capsule(style: .continuous)
                .fill(Color(white: 0.09).opacity(0.92))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.12)))
        )
        .fixedSize()
        .animation(.easeOut(duration: 0.15), value: confirming)
    }

    private func guarded(_ action: Action, run: @escaping () -> Void) {
        guard coordinator.elapsed > 10 else { run(); return }
        confirming = action
        confirmTask?.cancel()
        confirmTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled { confirming = nil }
        }
    }

    /// Same size as the button it replaces (the panel doesn't resize), filled red until clicked or 3 s pass.
    private func confirmButton(_ icon: String, _ title: String, run: @escaping () -> Void) -> some View {
        Button {
            confirmTask?.cancel()
            confirming = nil
            run()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.red))
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}

private struct ControlButton: View {
    let icon: String
    var tint: Color = .white
    let help: String
    let label: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.white.opacity(hover ? 0.16 : 0.06)))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
        .accessibilityLabel(label)
    }
}

@MainActor
final class ControlBarPanel {
    private var panel: NSPanel?

    func show(on screen: NSScreen, coordinator: RecordingCoordinator) {
        let host = NSHostingView(rootView: RecordingControlsView(coordinator: coordinator))
        let size = host.fittingSize
        let frame = CGRect(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.minY + 24, width: size.width, height: size.height)
        let p = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.sharingType = .none
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = host
        p.orderFrontRegardless()
        panel = p
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

// MARK: - Global hotkey

final class GlobalHotKey {
    static let shared = GlobalHotKey()
    private var ref: EventHotKeyRef?
    private var handlerInstalled = false
    fileprivate var action: (() -> Void)?

    /// Registers ⌘⇧2 by default.
    func register(keyCode: Int = kVK_ANSI_2, modifiers: Int = cmdKey | shiftKey, action: @escaping () -> Void) {
        self.action = action
        if !handlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { GlobalHotKey.shared.action?() }
                return noErr
            }, 1, &spec, nil, nil)
            handlerInstalled = true
        }
        if let ref { UnregisterEventHotKey(ref) }
        let id = EventHotKeyID(signature: OSType(0x46524D43), id: 1)
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &ref)
    }
}
