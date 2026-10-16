import SwiftUI
import AppKit

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
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.textDim)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label).font(.system(size: 12)).foregroundStyle(Theme.text)
                Spacer()
                Text(format(value))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.textDim)
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
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.fill.opacity(0.07)))
    }
}

struct IconButton: View {
    let icon: String
    var label: String? = nil
    var help: String = ""
    var tint: Color = Theme.text
    var disabled = false
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
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(hover && !disabled ? Theme.hover : Color.clear))
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
