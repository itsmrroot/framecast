import AppKit
import SwiftUI
import Combine
import Carbon.HIToolbox

private final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Area selection

enum AreaAspect: String, CaseIterable, Identifiable {
    case any, wide, classic, square, tall, vertical
    var id: String { rawValue }
    var label: String {
        switch self {
        case .any: return "Any aspect"
        case .wide: return "16:9"
        case .classic: return "4:3"
        case .square: return "1:1"
        case .tall: return "3:4"
        case .vertical: return "9:16"
        }
    }
    var ratio: CGFloat? {
        switch self {
        case .any: return nil
        case .wide: return 16.0 / 9.0
        case .classic: return 4.0 / 3.0
        case .square: return 1
        case .tall: return 3.0 / 4.0
        case .vertical: return 9.0 / 16.0
        }
    }
}

/// Shared state between the selection canvas (AppKit) and its control panel (SwiftUI).
@MainActor
final class AreaEditorModel: ObservableObject {
    /// In view coordinates (points, bottom-left origin), local to the screen.
    @Published var rect: CGRect?
    @Published var aspect: AreaAspect = .any { didSet { applyAspect() } }
    @Published var saved: [CGSize] = AreaEditorModel.loadSaved()
    let bounds: CGSize
    let confirmTitle: String
    var finish: ((CGRect?) -> Void)?

    init(bounds: CGSize, confirmTitle: String) {
        self.bounds = bounds
        self.confirmTitle = confirmTitle
    }

    func setSize(width: CGFloat, height: CGFloat) {
        guard let r = rect else { return }
        let w = min(max(20, width), bounds.width), h = min(max(20, height), bounds.height)
        rect = clampToBounds(CGRect(x: r.midX - w / 2, y: r.midY - h / 2, width: w, height: h))
    }

    func applyAspect() {
        guard let ratio = aspect.ratio, let r = rect else { return }
        var w = r.width, h = r.height
        if w / h > ratio { w = h * ratio } else { h = w / ratio }
        rect = clampToBounds(CGRect(x: r.midX - w / 2, y: r.midY - h / 2, width: w, height: h))
    }

    func clampToBounds(_ r: CGRect) -> CGRect {
        let w = min(r.width, bounds.width), h = min(r.height, bounds.height)
        return CGRect(x: min(max(0, r.minX), bounds.width - w), y: min(max(0, r.minY), bounds.height - h), width: w, height: h)
    }

    func saveCurrent() {
        guard let r = rect else { return }
        let size = CGSize(width: r.width.rounded(), height: r.height.rounded())
        guard !saved.contains(size) else { return }
        saved.insert(size, at: 0)
        saved = Array(saved.prefix(8))
        UserDefaults.standard.set(saved.map { [$0.width, $0.height] }, forKey: "rec.savedAreas")
    }

    private static func loadSaved() -> [CGSize] {
        (UserDefaults.standard.array(forKey: "rec.savedAreas") as? [[Double]] ?? []).compactMap {
            $0.count == 2 ? CGSize(width: $0[0], height: $0[1]) : nil
        }
    }
}

private final class AreaSelectionView: NSView {
    let model: AreaEditorModel
    private var controls: NSHostingView<AreaControls>?
    private var drag: (mode: Mode, start: CGPoint, rect: CGRect)?
    private var sub: AnyCancellable?

    enum Mode { case draw, move, n, s, e, w, ne, nw, se, sw }

    init(model: AreaEditorModel) {
        self.model = model
        super.init(frame: CGRect(origin: .zero, size: model.bounds))
        sub = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.needsDisplay = true; self?.positionControls() }
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let r = model.rect {
            let mode = hit(p, r)
            drag = (mode, p, r)
        } else {
            drag = (.draw, p, CGRect(origin: p, size: .zero))
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let d = drag else { return }
        let p = convert(event.locationInWindow, from: nil)
        let dx = p.x - d.start.x, dy = p.y - d.start.y
        var r: CGRect
        switch d.mode {
        case .draw:
            r = CGRect(x: min(d.start.x, p.x), y: min(d.start.y, p.y), width: abs(dx), height: abs(dy))
            if let ratio = model.aspect.ratio {
                let w = max(r.width, r.height * ratio)
                r = CGRect(x: dx < 0 ? d.start.x - w : d.start.x, y: dy < 0 ? d.start.y - w / ratio : d.start.y, width: w, height: w / ratio)
            }
        case .move:
            r = d.rect.offsetBy(dx: dx, dy: dy)
        default:
            r = resize(d.rect, mode: d.mode, dx: dx, dy: dy)
        }
        model.rect = model.clampToBounds(r)
    }

    override func mouseUp(with event: NSEvent) {
        if let d = drag, d.mode == .draw, let r = model.rect, r.width < 20 || r.height < 20 {
            model.rect = nil
        }
        drag = nil
    }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case kVK_Escape: model.finish?(nil)
        case kVK_Return, kVK_ANSI_KeypadEnter: if model.rect != nil { model.finish?(model.rect) }
        default: super.keyDown(with: event)
        }
    }

    private func hit(_ p: CGPoint, _ r: CGRect) -> Mode {
        let t: CGFloat = 10
        let l = abs(p.x - r.minX) < t, rt = abs(p.x - r.maxX) < t, b = abs(p.y - r.minY) < t, tp = abs(p.y - r.maxY) < t
        let inX = p.x > r.minX - t && p.x < r.maxX + t, inY = p.y > r.minY - t && p.y < r.maxY + t
        if l && tp { return .nw }; if rt && tp { return .ne }; if l && b { return .sw }; if rt && b { return .se }
        if l && inY { return .w }; if rt && inY { return .e }; if tp && inX { return .n }; if b && inX { return .s }
        return r.contains(p) ? .move : .draw
    }

    private func resize(_ r0: CGRect, mode: Mode, dx: CGFloat, dy: CGFloat) -> CGRect {
        var minX = r0.minX, maxX = r0.maxX, minY = r0.minY, maxY = r0.maxY
        if [.w, .nw, .sw].contains(mode) { minX = min(r0.minX + dx, maxX - 20) }
        if [.e, .ne, .se].contains(mode) { maxX = max(r0.maxX + dx, minX + 20) }
        if [.s, .sw, .se].contains(mode) { minY = min(r0.minY + dy, maxY - 20) }
        if [.n, .nw, .ne].contains(mode) { maxY = max(r0.maxY + dy, minY + 20) }
        var r = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        if let ratio = model.aspect.ratio {
            let byWidth = [.e, .w, .ne, .nw, .se, .sw].contains(mode)
            let w = byWidth ? r.width : r.height * ratio, h = byWidth ? r.width / ratio : r.height
            let x = [.w, .nw, .sw].contains(mode) ? r.maxX - w : ([.n, .s].contains(mode) ? r.midX - w / 2 : r.minX)
            let y = [.s, .sw, .se].contains(mode) ? r.maxY - h : ([.e, .w].contains(mode) ? r.midY - h / 2 : r.minY)
            r = CGRect(x: x, y: y, width: w, height: h)
        }
        return r
    }

    private func positionControls() {
        guard let r = model.rect else { controls?.isHidden = true; return }
        if controls == nil {
            let host = NSHostingView(rootView: AreaControls(model: model))
            addSubview(host)
            controls = host
        }
        guard let host = controls else { return }
        host.isHidden = false
        let size = host.fittingSize
        var y = r.minY - size.height - 14
        if y < 20 { y = r.maxY + 14 }
        if y + size.height > bounds.height - 20 { y = r.minY + 14 }
        let x = min(max(10, r.midX - size.width / 2), bounds.width - size.width - 10)
        host.frame = CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.45).setFill()
        bounds.fill()
        guard let r = model.rect else {
            let text = "Drag to select an area to record. Esc to cancel." as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 18, weight: .medium), .foregroundColor: NSColor.white]
            let size = text.size(withAttributes: attrs)
            text.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attrs)
            return
        }
        NSColor.clear.setFill()
        r.fill(using: .copy)
        // Thirds grid.
        NSColor.white.withAlphaComponent(0.25).setStroke()
        for i in 1...2 {
            let x = r.minX + r.width * CGFloat(i) / 3, y = r.minY + r.height * CGFloat(i) / 3
            let grid = NSBezierPath()
            grid.move(to: CGPoint(x: x, y: r.minY)); grid.line(to: CGPoint(x: x, y: r.maxY))
            grid.move(to: CGPoint(x: r.minX, y: y)); grid.line(to: CGPoint(x: r.maxX, y: y))
            grid.lineWidth = 1
            grid.stroke()
        }
        let border = NSBezierPath(rect: r)
        border.lineWidth = 1.5
        border.setLineDash([6, 4], count: 2, phase: 0)
        NSColor.white.setStroke()
        border.stroke()
        for p in [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                  CGPoint(x: r.maxX, y: r.midY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.midX, y: r.maxY),
                  CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.minX, y: r.midY)] {
            let dot = NSBezierPath(ovalIn: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12))
            NSColor.white.setFill()
            dot.fill()
        }
    }
}

private struct AreaControls: View {
    @ObservedObject var model: AreaEditorModel
    @State private var w = ""
    @State private var h = ""

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                field($w) { apply() }
                Text("×").foregroundStyle(.white.opacity(0.6))
                field($h) { apply() }
            }
            Menu {
                ForEach(AreaAspect.allCases) { a in
                    Button { model.aspect = a } label: { if model.aspect == a { Label(a.label, systemImage: "checkmark") } else { Text(a.label) } }
                }
            } label: { Label(model.aspect.label, systemImage: "aspectratio") }
                .menuStyle(.borderlessButton).fixedSize()
            Menu {
                if model.saved.isEmpty { Text("No saved sizes") }
                ForEach(model.saved, id: \.self) { s in
                    Button("\(Int(s.width)) × \(Int(s.height))") { model.aspect = .any; model.setSize(width: s.width, height: s.height) }
                }
                Divider()
                Button("Save Current Size") { model.saveCurrent() }
            } label: { Label("Saved", systemImage: "bookmark") }
                .menuStyle(.borderlessButton).fixedSize()
            Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1, height: 22)
            Button("Cancel") { model.finish?(nil) }
                .buttonStyle(.plain).foregroundStyle(.white.opacity(0.75))
            Button {
                model.finish?(model.rect)
            } label: {
                Label(model.confirmTitle, systemImage: "record.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 12).frame(height: 30)
                    .background(Capsule().fill(Theme.accent))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
        }
        .font(.system(size: 12))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(height: 46)
        .background(Capsule().fill(Color(white: 0.1).opacity(0.96)).overlay(Capsule().strokeBorder(Color.white.opacity(0.12))))
        .environment(\.colorScheme, .dark)
        .fixedSize()
        .onAppear(perform: sync)
        .onChange(of: model.rect) { _, _ in sync() }
    }

    private func field(_ text: Binding<String>, onSubmit: @escaping () -> Void) -> some View {
        TextField("", text: text)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .font(.system(size: 12).monospacedDigit())
            .frame(width: 52, height: 24)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.1)))
            .onSubmit(onSubmit)
    }

    private func sync() {
        guard let r = model.rect else { return }
        w = "\(Int(r.width.rounded()))"
        h = "\(Int(r.height.rounded()))"
    }

    private func apply() {
        guard let wv = Double(w), let hv = Double(h) else { sync(); return }
        model.aspect = .any
        model.setSize(width: wv, height: hv)
    }
}

@MainActor
enum AreaSelector {
    private static var window: NSWindow?

    /// Lets the user draw and adjust a rectangle on `screen`. Returns it in screen-local points (top-left origin).
    static func select(on screen: NSScreen, initial: CGRect? = nil, confirmTitle: String = "Start Recording") async -> CGRect? {
        await withCheckedContinuation { cont in
            let w = KeyableWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.level = .screenSaver
            w.isOpaque = false
            w.backgroundColor = .clear
            w.sharingType = .none
            w.setFrame(screen.frame, display: true)
            let model = AreaEditorModel(bounds: screen.frame.size, confirmTitle: confirmTitle)
            if let r = initial, r.width > 10, r.height > 10 {
                model.rect = model.clampToBounds(CGRect(x: r.minX, y: screen.frame.height - r.maxY, width: r.width, height: r.height))
            }
            let view = AreaSelectionView(model: model)
            var finished = false
            model.finish = { rect in
                guard !finished else { return }
                finished = true
                w.orderOut(nil)
                window = nil
                cont.resume(returning: rect.map { CGRect(x: $0.minX, y: screen.frame.height - $0.maxY, width: $0.width, height: $0.height).integral })
            }
            w.contentView = view
            window = w
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
            w.makeFirstResponder(view)
            if model.rect != nil { view.needsDisplay = true; model.objectWillChange.send() }
        }
    }
}

// MARK: - Display picker

/// Hover a display to see its name and a Start recording button; nothing records until it's clicked.
@MainActor
enum DisplayPicker {
    private static var windows: [NSWindow] = []

    static func pick() async -> NSScreen? {
        await withCheckedContinuation { cont in
            var finished = false
            @MainActor func finish(_ s: NSScreen?) {
                guard !finished else { return }
                finished = true
                windows.forEach { $0.orderOut(nil) }
                windows.removeAll()
                cont.resume(returning: s)
            }
            for screen in NSScreen.screens {
                let w = KeyableWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
                w.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)
                w.isOpaque = false
                w.backgroundColor = .clear
                w.sharingType = .none
                w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                let view = DisplayPickView(name: screen.localizedName,
                                           onHover: { [weak w] in w?.makeKey() },
                                           onStart: { finish(screen) },
                                           onCancel: { finish(nil) })
                w.contentView = NSHostingView(rootView: view)
                w.setFrame(screen.frame, display: true)
                w.orderFrontRegardless()
                windows.append(w)
            }
            NSApp.activate(ignoringOtherApps: true)
            windows.first { $0.screen == NSScreen.withMouse }?.makeKey()
        }
    }
}

private struct DisplayPickView: View {
    let name: String
    let onHover: () -> Void
    let onStart: () -> Void
    let onCancel: () -> Void
    @State private var hovered = false

    var body: some View {
        ZStack {
            Rectangle().fill(hovered ? Theme.accent.opacity(0.2) : Color.black.opacity(0.001))
            if hovered {
                VStack(spacing: 18) {
                    Text(name).font(.system(size: 40, weight: .bold)).foregroundStyle(.white).shadow(radius: 8)
                    Button(action: onStart) {
                        Label("Start recording", systemImage: "record.circle")
                            .font(.system(size: 15, weight: .semibold))
                            .padding(.horizontal, 18).frame(height: 40)
                            .background(Capsule().fill(Theme.accent))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                    Text("Esc to cancel").font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
                }
            }
            Button("", action: onCancel).keyboardShortcut(.cancelAction).opacity(0).frame(width: 0, height: 0)
        }
        .contentShape(Rectangle())
        .onHover { inside in
            hovered = inside
            if inside { onHover() }
        }
        .environment(\.colorScheme, .dark)
    }
}
