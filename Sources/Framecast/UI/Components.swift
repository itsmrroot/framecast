import SwiftUI
import AppKit

/// A menu item with a real ✓ when `on` (SwiftUI menus ignore a Label's checkmark image).
struct MenuCheck: View {
    let title: String
    let on: Bool
    let action: () -> Void
    init(_ title: String, _ on: Bool, action: @escaping () -> Void) {
        self.title = title; self.on = on; self.action = action
    }
    var body: some View {
        Toggle(title, isOn: Binding(get: { on }, set: { _ in action() }))
    }
}

enum Theme {
    /// A color with separate light- and dark-mode values.
    static func adaptive(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }

    // Near-black (or soft white) surfaces with an indigo accent and a gold timeline.
    static let nsBg = adaptive(light: NSColor(srgbRed: 0.955, green: 0.955, blue: 0.968, alpha: 1),
                               dark: NSColor(srgbRed: 0.039, green: 0.039, blue: 0.051, alpha: 1))
    static let nsPanel = adaptive(light: .white, dark: NSColor(srgbRed: 0.071, green: 0.071, blue: 0.086, alpha: 1))
    static let bg = Color(nsColor: nsBg)
    static let panel = Color(nsColor: nsPanel)
    static let raised = Color(nsColor: adaptive(light: NSColor(srgbRed: 0.925, green: 0.925, blue: 0.945, alpha: 1),
                                                dark: NSColor(srgbRed: 0.11, green: 0.11, blue: 0.13, alpha: 1)))
    /// Neutral overlay: white in dark mode, black in light mode. Use with `.opacity(…)`.
    static let fill = Color(nsColor: adaptive(light: .black, dark: .white))
    static let hover = Color(nsColor: adaptive(light: NSColor(white: 0, alpha: 0.06), dark: NSColor(white: 1, alpha: 0.07)))
    static let border = Color(nsColor: adaptive(light: NSColor(white: 0, alpha: 0.1), dark: NSColor(white: 1, alpha: 0.08)))
    static let accent = Color(red: 0.36, green: 0.27, blue: 0.97)
    static let zoom = Color(red: 0.42, green: 0.34, blue: 0.98)
    static let clip = Color(red: 0.86, green: 0.6, blue: 0.2)
    /// Lit gradients for timeline blocks: darker at the top, glowing at the bottom.
    // Timeline blocks, matched to Screen Studio: darker at the top, glowing toward the bottom.
    static let clipGradient = LinearGradient(colors: [Color(red: 0.53, green: 0.37, blue: 0.14), Color(red: 0.76, green: 0.54, blue: 0.22)],
                                             startPoint: .top, endPoint: .bottom)
    static let clipGradientSelected = LinearGradient(colors: [Color(red: 0.60, green: 0.43, blue: 0.17), Color(red: 0.85, green: 0.62, blue: 0.27)],
                                                     startPoint: .top, endPoint: .bottom)
    static let clipRim = Color(red: 0.86, green: 0.64, blue: 0.29)
    static let clipPin = Color(red: 0.91, green: 0.64, blue: 0.24)
    static let zoomGradient = LinearGradient(colors: [Color(red: 0.15, green: 0.13, blue: 0.40), Color(red: 0.19, green: 0.16, blue: 0.52)],
                                             startPoint: .top, endPoint: .bottom)
    static let zoomGradientSelected = LinearGradient(colors: [Color(red: 0.33, green: 0.25, blue: 0.93), Color(red: 0.47, green: 0.40, blue: 1.0)],
                                                     startPoint: .top, endPoint: .bottom)
    static let zoomRim = Color(red: 0.78, green: 0.74, blue: 1.0)
    static let playhead = Color(red: 0.33, green: 0.25, blue: 0.95)
    static let hoverPin = Color(nsColor: adaptive(light: NSColor(white: 0.55, alpha: 1), dark: NSColor(white: 0.3, alpha: 1)))
    static let blade = Color(red: 0.95, green: 0.3, blue: 0.27)
    static let record = Color(red: 1.0, green: 0.27, blue: 0.3)
    static let text = Color(nsColor: adaptive(light: NSColor(white: 0, alpha: 0.87), dark: NSColor(white: 1, alpha: 0.92)))
    static let textDim = Color(nsColor: adaptive(light: NSColor(white: 0, alpha: 0.55), dark: NSColor(white: 1, alpha: 0.55)))
    static let textFaint = Color(nsColor: adaptive(light: NSColor(white: 0, alpha: 0.32), dark: NSColor(white: 1, alpha: 0.32)))
}

struct SectionHeader: View {
    let title: String
    var trailing: AnyView? = nil
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
            Spacer()
            if let trailing { trailing }
        }
    }
}

struct LabeledSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double? = nil
    var format: (Double) -> String = { String(format: "%.0f", $0) }
    /// When set, shows a Reset button that returns the slider to this value.
    var reset: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label).font(.system(size: 12)).foregroundStyle(Theme.text)
                Spacer()
                Text(format(value))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.textDim)
                if let reset {
                    let atDefault = abs(value - reset) < 0.0001
                    Button("Reset") { value = reset }
                        .buttonStyle(.plain)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(atDefault ? Theme.textFaint : Theme.accent)
                        .disabled(atDefault)
                        .help("Back to the default")
                }
            }
            if let step {
                Slider(value: $value, in: range, step: step).controlSize(.small)
            } else {
                Slider(value: $value, in: range).controlSize(.small)
            }
        }
        .tint(Theme.accent)
    }
}

struct ToggleRow: View {
    let label: String
    var icon: String? = nil
    @Binding var isOn: Bool
    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon).frame(width: 16).foregroundStyle(Theme.textDim)
            }
            Text(label).font(.system(size: 12))
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(Theme.accent)
        }
        .contentShape(Rectangle())
        .onTapGesture { isOn.toggle() }
    }
}

/// Segmented control styled for the dark UI.
struct PillPicker<T: Hashable>: View {
    let options: [T]
    @Binding var selection: T
    let label: (T) -> String
    var icon: ((T) -> String)? = nil

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { opt in
                Button {
                    selection = opt
                } label: {
                    HStack(spacing: 5) {
                        if let icon { Image(systemName: icon(opt)).font(.system(size: 11)) }
                        Text(label(opt)).font(.system(size: 11.5, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(selection == opt ? Theme.fill.opacity(0.14) : Color.clear)
                    )
                    .foregroundStyle(selection == opt ? Theme.text : Theme.textDim)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == opt ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.fill.opacity(0.07)))
    }
}

/// A large icon-over-label choice tile (animation styles, zoom styles…).
struct ChoiceTiles<T: Hashable>: View {
    let options: [T]
    @Binding var selection: T
    let label: (T) -> String
    let icon: (T) -> String
    var detail: ((T) -> String)? = nil

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.self) { o in
                let on = selection == o
                Button { selection = o } label: {
                    VStack(spacing: 6) {
                        Image(systemName: icon(o)).font(.system(size: 18))
                        Text(label(o)).font(.system(size: 11.5, weight: .medium))
                        if let detail { Text(detail(o)).font(.system(size: 10)).foregroundStyle(Theme.textDim).lineLimit(1) }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.fill.opacity(on ? 0.1 : 0.04)))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(on ? Theme.accent : Theme.border, lineWidth: on ? 1.5 : 1))
                    .foregroundStyle(on ? Theme.text : Theme.textDim)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// A collapsible "Advanced" card for options most people won't need.
struct DisclosureCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { withAnimation(.easeOut(duration: 0.15)) { open.toggle() } } label: {
                HStack {
                    Text(title).font(.system(size: 12, weight: .medium))
                    Spacer()
                    Image(systemName: open ? "chevron.up" : "chevron.down").font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.fill.opacity(0.08)))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open { content }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.fill.opacity(0.04)))
    }
}

struct IconButton: View {
    let icon: String
    var label: String? = nil
    var help: String = ""
    var tint: Color = Theme.text
    var disabled = false
    /// A tool that stays on (like the split tool): drawn with a tinted background.
    var active = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 12, weight: .medium))
                if let label { Text(label).font(.system(size: 12, weight: .medium)) }
            }
            .padding(.horizontal, label == nil ? 0 : 9)
            .frame(minWidth: 28, minHeight: 26)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(active ? Theme.accent.opacity(0.2) : (hover && !disabled ? Theme.hover : Color.clear)))
            .foregroundStyle(disabled ? Theme.textFaint : tint)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hover = $0 }
        .help(help)
    }
}

/// Sun / moon button that switches between light and dark mode.
struct AppearanceButton: View {
    @ObservedObject private var app = AppSettings.shared
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        IconButton(icon: scheme == .dark ? "sun.max" : "moon",
                   help: scheme == .dark ? "Switch to light mode" : "Switch to dark mode") {
            app.toggleAppearance()
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = Theme.accent
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color.opacity(configuration.isPressed ? 0.8 : 1))
            )
            .contentShape(Rectangle())
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Theme.fill.opacity(configuration.isPressed ? 0.16 : 0.09))
            )
            .contentShape(Rectangle())
    }
}

struct Card<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.raised.opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border))
    }
}

extension RGBA {
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(Double(ns.redComponent), Double(ns.greenComponent), Double(ns.blueComponent), Double(ns.alphaComponent))
    }
}

/// Wraps an AVPlayerLayer.
struct PlayerLayerView: NSViewRepresentable {
    let player: AVPlayerWrapper

    func makeNSView(context: Context) -> PlayerNSView {
        let v = PlayerNSView()
        v.playerLayer.player = player.player
        return v
    }

    func updateNSView(_ nsView: PlayerNSView, context: Context) {
        if nsView.playerLayer.player !== player.player { nsView.playerLayer.player = player.player }
    }
}

import AVFoundation

struct AVPlayerWrapper {
    let player: AVPlayer
}

final class PlayerNSView: NSView {
    let playerLayer = AVPlayerLayer()
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer = CALayer()
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = .clear
        layer?.addSublayer(playerLayer)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}

/// "Move to Trash?" as a plain alert: readable buttons (the destructive style was red on red), and
/// the item can be put back from the Trash, so the action is the default.
@MainActor
enum TrashConfirmation {
    static func run(name: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Move “\(name)” to the Trash?"
        alert.informativeText = "You can put it back from the Trash in Finder."
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        return alert.runModal() == .alertFirstButtonReturn
    }
}
