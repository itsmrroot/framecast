import AppKit
import SwiftUI

/// Floating teleprompter: notes you can read while recording. Hidden from the recording.
@MainActor
final class SpeakerNotes: ObservableObject {
    static let shared = SpeakerNotes()

    @Published var text: String { didSet { UserDefaults.standard.set(text, forKey: "notes.text") } }
    @Published var fontSize: Double { didSet { UserDefaults.standard.set(fontSize, forKey: "notes.fontSize") } }
    /// Points per second while auto-scrolling.
    @Published var speed: Double { didSet { UserDefaults.standard.set(speed, forKey: "notes.speed") } }
    @Published private(set) var scrolling = false
    var isVisible: Bool { panel?.isVisible == true }

    private var panel: NSPanel?
    private weak var textView: NSTextView?
    private var timer: Timer?

    private init() {
        let d = UserDefaults.standard
        d.register(defaults: ["notes.fontSize": 20.0, "notes.speed": 30.0])
        text = d.string(forKey: "notes.text") ?? ""
        fontSize = d.double(forKey: "notes.fontSize")
        speed = d.double(forKey: "notes.speed")
    }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        if panel == nil {
            let screen = NSScreen.withMouse
            let size = CGSize(width: 420, height: 300)
            let p = FloatingPanel(contentRect: CGRect(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.maxY - size.height - 30,
                                                      width: size.width, height: size.height), keyable: true)
            p.styleMask.insert(.resizable)
            p.isMovableByWindowBackground = true
            p.contentView = NSHostingView(rootView: SpeakerNotesView(notes: self))
            panel = p
        }
        panel?.orderFrontRegardless()
        panel?.makeKey()
    }

    func hide() {
        stopScrolling()
        panel?.orderOut(nil)
    }

    func attach(_ tv: NSTextView) { textView = tv }

    func toggleScrolling() {
        if !isVisible { show() }
        scrolling ? stopScrolling() : startScrolling()
    }

    private func startScrolling() {
        scrolling = true
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let tv = self.textView, let clip = tv.enclosingScrollView?.contentView else { return }
                var origin = clip.bounds.origin
                origin.y += CGFloat(self.speed / 30)
                let maxY = max(0, tv.frame.height - clip.bounds.height)
                if origin.y >= maxY { origin.y = maxY; self.stopScrolling() }
                clip.scroll(to: origin)
                tv.enclosingScrollView?.reflectScrolledClipView(clip)
            }
        }
    }

    private func stopScrolling() {
        scrolling = false
        timer?.invalidate()
        timer = nil
    }
}

private struct SpeakerNotesView: View {
    @ObservedObject var notes: SpeakerNotes

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "text.alignleft").foregroundStyle(.white.opacity(0.6))
                Text("Speaker notes").font(.system(size: 12, weight: .semibold))
                Spacer()
                Button { notes.toggleScrolling() } label: {
                    Image(systemName: notes.scrolling ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.plain)
                .help("Start or stop scrolling (⌥⌘.)")
                Button { notes.hide() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .help("Hide (⌥⌘/)")
            }
            .font(.system(size: 12))
            .padding(.horizontal, 12)
            .frame(height: 34)
            NotesTextView(notes: notes)
            HStack(spacing: 12) {
                Image(systemName: "textformat.size").foregroundStyle(.white.opacity(0.6))
                Slider(value: $notes.fontSize, in: 12...48).controlSize(.mini).frame(width: 90)
                Image(systemName: "gauge.with.dots.needle.33percent").foregroundStyle(.white.opacity(0.6))
                Slider(value: $notes.speed, in: 5...120).controlSize(.mini).frame(width: 90)
                Spacer()
            }
            .tint(Theme.accent)
            .padding(.horizontal, 12)
            .frame(height: 32)
        }
        .foregroundStyle(.white)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(white: 0.08).opacity(0.94)))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .environment(\.colorScheme, .dark)
    }
}

/// An NSTextView so the notes can be scrolled programmatically.
private struct NotesTextView: NSViewRepresentable {
    @ObservedObject var notes: SpeakerNotes

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        guard let tv = scroll.documentView as? NSTextView else { return scroll }
        tv.delegate = context.coordinator
        tv.drawsBackground = false
        tv.textColor = .white
        tv.insertionPointColor = .white
        tv.isRichText = false
        tv.textContainerInset = NSSize(width: 12, height: 8)
        tv.string = notes.text.isEmpty ? "" : notes.text
        tv.font = .systemFont(ofSize: notes.fontSize, weight: .medium)
        notes.attach(tv)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        let font = NSFont.systemFont(ofSize: notes.fontSize, weight: .medium)
        if tv.font != font { tv.font = font }
    }

    func makeCoordinator() -> Coordinator { Coordinator(notes: notes) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let notes: SpeakerNotes
        init(notes: SpeakerNotes) { self.notes = notes }
        func textDidChange(_ n: Notification) {
            guard let tv = n.object as? NSTextView else { return }
            MainActor.assumeIsolated { notes.text = tv.string }
        }
    }
}
