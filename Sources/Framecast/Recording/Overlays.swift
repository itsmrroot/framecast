import AppKit
import SwiftUI
import Carbon.HIToolbox

// MARK: - Area selection

private final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class AreaSelectionView: NSView {
    var onFinish: ((CGRect?) -> Void)?
    private var startPoint: CGPoint?
    private var current: CGRect?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        current = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let s = startPoint else { return }
        let p = convert(event.locationInWindow, from: nil)
        current = CGRect(x: min(s.x, p.x), y: min(s.y, p.y), width: abs(p.x - s.x), height: abs(p.y - s.y))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let r = current, r.width > 20, r.height > 20 else {
            startPoint = nil; current = nil; needsDisplay = true
            return
        }
        // Convert to top-left origin, local to the screen.
        let flipped = CGRect(x: r.minX, y: bounds.height - r.maxY, width: r.width, height: r.height).integral
        onFinish?(flipped)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) { onFinish?(nil) }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.45).setFill()
        bounds.fill()
        if let r = current {
            NSColor.clear.setFill()
            r.fill(using: .copy)
            let path = NSBezierPath(rect: r.insetBy(dx: -0.5, dy: -0.5))
            path.lineWidth = 1.5
            NSColor.white.setStroke()
            path.stroke()
            let label = "\(Int(r.width)) × \(Int(r.height))" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: NSColor.white,
            ]
            let size = label.size(withAttributes: attrs)
            let box = CGRect(x: r.midX - size.width / 2 - 8, y: r.minY - size.height - 14, width: size.width + 16, height: size.height + 6)
            NSColor.black.withAlphaComponent(0.75).setFill()
            NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
            label.draw(at: CGPoint(x: box.minX + 8, y: box.minY + 3), withAttributes: attrs)
        } else {
            let text = "Drag to select an area to record — Esc to cancel" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 18, weight: .medium),
                .foregroundColor: NSColor.white,
            ]
            let size = text.size(withAttributes: attrs)
            text.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attrs)
        }
    }
}

@MainActor
enum AreaSelector {
    private static var window: NSWindow?

    /// Lets the user drag out a rectangle on the given screen. Returns a rect in screen-local points (top-left origin).
    static func select(on screen: NSScreen) async -> CGRect? {
        await withCheckedContinuation { cont in
            let w = KeyableWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.level = .screenSaver
            w.isOpaque = false
            w.backgroundColor = .clear
            w.sharingType = .none
            w.ignoresMouseEvents = false
            w.setFrame(screen.frame, display: true)
            let view = AreaSelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.onFinish = { rect in
                w.orderOut(nil)
                window = nil
                cont.resume(returning: rect)
            }
            w.contentView = view
            window = w
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
            w.makeFirstResponder(view)
        }
    }
}

// MARK: - Countdown

private struct CountdownView: View {
    @ObservedObject var model: CountdownModel
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
            Text("\(model.value)")
                .font(.system(size: 96, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText(countsDown: true))
                .animation(.spring(duration: 0.35), value: model.value)
        }
        .frame(width: 180, height: 180)
    }
}

@MainActor
private final class CountdownModel: ObservableObject {
    @Published var value: Int
    init(_ v: Int) { value = v }
}

@MainActor
enum Countdown {
    static func run(seconds: Int, on screen: NSScreen) async {
        guard seconds > 0 else { return }
        let model = CountdownModel(seconds)
        let size = CGSize(width: 180, height: 180)
        let frame = CGRect(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2, width: size.width, height: size.height)
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.sharingType = .none
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(rootView: CountdownView(model: model))
        panel.orderFrontRegardless()
        for v in stride(from: seconds, through: 1, by: -1) {
            model.value = v
            NSSound(named: "Tink")?.play()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        panel.orderOut(nil)
    }
}

// MARK: - Floating recording controls

struct RecordingControlsView: View {
    @ObservedObject var coordinator: RecordingCoordinator

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(coordinator.phase == .paused ? Color.orange : Color.red)
                .frame(width: 10, height: 10)
                .opacity(coordinator.phase == .paused ? 1 : (Int(coordinator.elapsed * 2) % 2 == 0 ? 1 : 0.4))
            Text(formatTime(coordinator.elapsed))
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(minWidth: 44, alignment: .leading)

            Divider().frame(height: 18).overlay(Color.white.opacity(0.2))

            ControlButton(icon: "stop.fill", tint: .red, help: "Stop recording (⌘⇧2)") {
                coordinator.stop()
            }
            ControlButton(icon: coordinator.phase == .paused ? "play.fill" : "pause.fill", help: "Pause / resume") {
                coordinator.togglePause()
            }
            ControlButton(icon: "arrow.counterclockwise", help: "Restart recording") {
                coordinator.restart()
            }
            ControlButton(icon: "trash", help: "Cancel and discard") {
                coordinator.cancel()
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
    }
}

private struct ControlButton: View {
    let icon: String
    var tint: Color = .white
    let help: String
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
