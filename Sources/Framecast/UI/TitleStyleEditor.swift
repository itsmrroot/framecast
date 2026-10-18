import SwiftUI
import AppKit

/// Look, typeface, weight, alignment, colours and background for a title.
struct TitleStyleEditor: View {
    @Binding var style: TitleStyle
    /// Text slides have their own background, so they hide the card choice.
    var showsCard = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            section(lookTitle) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(TitleStyle.presets, id: \.name) { preset in
                        PresetTile(name: preset.name, style: preset.style, selected: currentLook == preset.name) {
                            // Keep the alignment you chose; a look is about type and colour.
                            var s = preset.style
                            s.align = style.align
                            s.look = preset.name
                            style = s
                        }
                    }
                }
            }

            section("Typeface") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(TitleFont.allCases) { f in
                        Button { style.font = f } label: {
                            VStack(spacing: 2) {
                                Text("Aa").font(Self.swiftUIFont(f, weight: style.weight, size: 20))
                                Text(f.label).font(.system(size: 10)).foregroundStyle(Theme.textDim)
                            }
                            .frame(maxWidth: .infinity).frame(height: 52)
                            .background(RoundedRectangle(cornerRadius: 9).fill(Theme.fill.opacity(style.font == f ? 0.12 : 0.05)))
                            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(style.font == f ? Theme.accent : .clear, lineWidth: 1.5))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(f.label)
                        .accessibilityAddTraits(style.font == f ? .isSelected : [])
                    }
                }
            }

            section("Weight") {
                PillPicker(options: TitleWeight.allCases, selection: $style.weight, label: \.label)
            }

            section("Alignment") {
                HStack(spacing: 8) {
                    PillPicker(options: TitleAlign.allCases, selection: $style.align, label: { _ in "" }, icon: { $0.icon })
                        .frame(width: 150)
                    Spacer()
                }
            }

            section("Text color") {
                SwatchRow(colors: TitleStyle.palette, selection: style.textColor, allowsAuto: true) { style.textColor = $0 }
            }

            if showsCard { section("Background") {
                PillPicker(options: TitleCard.allCases, selection: $style.card, label: \.label)
                if style.card == .color {
                    SwatchRow(colors: TitleStyle.palette, selection: style.cardColor, allowsAuto: false) { c in
                        if let c { style.cardColor = c }
                    }
                }
                Text(cardHint).font(.system(size: 11)).foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            } }
        }
    }

    /// The look this title uses: the one picked (kept while you tweak it), or one it exactly matches.
    private var currentLook: String? {
        style.look ?? TitleStyle.presets.first { $0.style.looksLike(style) }?.name
    }

    private var lookTitle: String {
        guard let name = currentLook, let preset = TitleStyle.presets.first(where: { $0.name == name }) else { return "Look" }
        return preset.style.looksLike(style) ? "Look" : "Look · \(name), edited"
    }

    private var cardHint: String {
        switch style.card {
        case .light: return "A bright card, like a notification."
        case .dark: return "A dark card that stands out on light screens."
        case .glass: return "Frosted glass: the video shows through, blurred."
        case .color: return "A card in the color you pick."
        case .none: return "Just the text, with a soft shadow so it stays readable."
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 12))
            content()
        }
    }

    static func swiftUIFont(_ f: TitleFont, weight: TitleWeight, size: CGFloat) -> Font {
        Font(TextArt.font(f, weight: weight, size: size) as CTFont)
    }
}

/// A miniature of a title look.
private struct PresetTile: View {
    let name: String
    let style: TitleStyle
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    // A little "video" behind the card, so glass and bare text read correctly.
                    LinearGradient(colors: [Color(red: 0.36, green: 0.27, blue: 0.97), Color(red: 0.95, green: 0.4, blue: 0.6)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Text("Aa")
                        .font(TitleStyleEditor.swiftUIFont(style.font, weight: style.weight, size: 15))
                        .foregroundStyle(style.resolvedTextColor.color)
                        .shadow(color: style.card == .none ? .black.opacity(0.5) : .clear, radius: 2, y: 1)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background { card }
                }
                .frame(height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Theme.accent : Theme.border, lineWidth: selected ? 2 : 1))
                .scaleEffect(hover ? 1.04 : 1)
                Text(name).font(.system(size: 10, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Theme.text : Theme.textDim)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
        .accessibilityLabel("\(name) look")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var card: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        switch style.card {
        case .light: shape.fill(Color.white.opacity(0.95))
        case .dark: shape.fill(Color(white: 0.11).opacity(0.92))
        case .glass: shape.fill(.ultraThinMaterial).overlay(shape.strokeBorder(Color.white.opacity(0.35)))
        case .color: shape.fill(style.cardColor.color)
        case .none: EmptyView()
        }
    }
}

/// Apple's colours as round swatches, plus a custom colour well.
struct SwatchRow: View {
    let colors: [RGBA]
    let selection: RGBA?
    let allowsAuto: Bool
    let onPick: (RGBA?) -> Void

    var body: some View {
        let custom = selection.map { s in !colors.contains(s) } ?? false
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 6), count: 9), alignment: .leading, spacing: 6) {
            if allowsAuto {
                swatch(selected: selection == nil, label: "Automatic") {
                    Circle().fill(AngularGradient(colors: [.white, .black, .white], center: .center))
                        .overlay(Text("A").font(.system(size: 9, weight: .bold)).foregroundStyle(.gray))
                } action: { onPick(nil) }
            }
            ForEach(colors, id: \.self) { c in
                swatch(selected: selection == c, label: TitleStyle.name(of: c)) {
                    Circle().fill(c.color)
                } action: { onPick(c) }
            }
            ColorPicker("", selection: Binding(get: { selection?.color ?? .white }, set: { onPick(RGBA($0)) }), supportsOpacity: false)
                .labelsHidden()
                .frame(width: 24, height: 24)
                .overlay(Circle().strokeBorder(custom ? Theme.accent : .clear, lineWidth: 2).padding(-3).allowsHitTesting(false))
                .help("Custom color")
        }
    }

    private func swatch<S: View>(selected: Bool, label: String, @ViewBuilder fill: () -> S, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            fill()
                .frame(width: 22, height: 22)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.15)))
                .padding(2)
                .overlay(Circle().strokeBorder(selected ? Theme.accent : .clear, lineWidth: 2))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
