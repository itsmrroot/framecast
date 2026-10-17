import Foundation
import CoreImage
import CoreText
import AppKit

/// Renders text badges (captions, keystrokes, titles) with Core Text, cached per string and size.
final class TextArt: @unchecked Sendable {
    enum Kind: Hashable {
        /// Dark translucent pill, used for keystrokes.
        case keycap
        /// Rounded dark box with wrapped lines, used for captions.
        case caption
        /// Large bold title on a frosted card.
        case title
    }

    private struct Key: Hashable {
        let text: String
        let kind: Kind
        let fontSize: Int
        let maxWidth: Int
    }

    private struct TitleKey: Hashable {
        let text: String
        let subtitle: String
        let style: TitleStyle
        let fontSize: Int
        let maxWidth: Int
    }

    /// A rendered title: the card (or bare text) and its corner radius, for the renderer's glass and shadow.
    struct Title {
        let image: CIImage
        let radius: CGFloat
    }

    private let lock = NSLock()
    private var cache: [Key: CIImage] = [:]
    private var titleCache: [TitleKey: Title] = [:]

    func title(_ text: String, subtitle: String, style: TitleStyle, fontSize: CGFloat, maxWidth: CGFloat) -> Title {
        let key = TitleKey(text: text, subtitle: subtitle, style: style, fontSize: Int(fontSize.rounded()), maxWidth: Int(maxWidth.rounded()))
        lock.lock()
        if let hit = titleCache[key] { lock.unlock(); return hit }
        lock.unlock()
        let t = renderTitle(text, subtitle: subtitle, style: style, fontSize: CGFloat(key.fontSize), maxWidth: CGFloat(key.maxWidth))
        lock.lock()
        if titleCache.count > 200 { titleCache.removeAll() }
        titleCache[key] = t
        lock.unlock()
        return t
    }

    static func font(_ font: TitleFont, weight: TitleWeight, size: CGFloat) -> NSFont {
        let w: NSFont.Weight
        switch weight {
        case .regular: w = .regular
        case .medium: w = .medium
        case .semibold: w = .semibold
        case .bold: w = .bold
        case .heavy: w = .heavy
        }
        let base = NSFont.systemFont(ofSize: size, weight: w)
        let design: NSFontDescriptor.SystemDesign
        switch font {
        case .system: return base
        case .condensed: return NSFont.systemFont(ofSize: size, weight: w, width: .condensed)
        case .expanded: return NSFont.systemFont(ofSize: size, weight: w, width: .expanded)
        case .rounded: design = .rounded
        case .serif: design = .serif
        case .mono: design = .monospaced
        }
        guard let d = base.fontDescriptor.withDesign(design) else { return base }
        return NSFont(descriptor: d, size: size) ?? base
    }

    private func renderTitle(_ text: String, subtitle: String, style: TitleStyle, fontSize: CGFloat, maxWidth: CGFloat) -> Title {
        let size = max(4, fontSize)
        let para = NSMutableParagraphStyle()
        para.alignment = style.align == .left ? .left : (style.align == .right ? .right : .center)
        para.lineBreakMode = .byWordWrapping
        let tc = style.resolvedTextColor
        let color = NSColor(srgbRed: tc.r, green: tc.g, blue: tc.b, alpha: 1)
        var attrs: [NSAttributedString.Key: Any] = [
            .font: TextArt.font(style.font, weight: style.weight, size: size),
            .foregroundColor: color, .paragraphStyle: para,
            // Large display text reads better slightly tightened, as in Apple's own titles.
            .kern: style.font == .mono ? 0 : -size * 0.012,
        ]
        let bare = style.card == .none
        if bare {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor(white: 0, alpha: 0.55)
            shadow.shadowBlurRadius = size * 0.22
            shadow.shadowOffset = CGSize(width: 0, height: -size * 0.04)
            attrs[.shadow] = shadow
        }
        let attr = NSMutableAttributedString(string: text, attributes: attrs)
        let sub = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sub.isEmpty {
            let subPara = para.mutableCopy() as! NSMutableParagraphStyle
            subPara.paragraphSpacingBefore = size * 0.12
            var subAttrs = attrs
            subAttrs[.font] = TextArt.font(style.font, weight: style.weight == .heavy || style.weight == .bold ? .medium : .regular, size: size * 0.48)
            subAttrs[.foregroundColor] = color.withAlphaComponent(0.72)
            subAttrs[.paragraphStyle] = subPara
            subAttrs[.kern] = 0
            attr.append(NSAttributedString(string: "\n" + sub, attributes: subAttrs))
        }

        let padX = bare ? size * 0.35 : size * 0.9
        let padY = bare ? size * 0.3 : size * 0.5
        let setter = CTFramesetterCreateWithAttributedString(attr)
        let constraint = CGSize(width: max(10, maxWidth - 2 * padX), height: .greatestFiniteMagnitude)
        let fit = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(location: 0, length: 0), nil, constraint, nil)
        let textSize = CGSize(width: ceil(fit.width) + 2, height: ceil(fit.height) + 1)
        let w = Int(textSize.width + 2 * padX), h = Int(textSize.height + 2 * padY)
        let radius = size * 0.45
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return Title(image: .empty(), radius: radius) }
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        switch style.card {
        case .light:
            ctx.addPath(path); ctx.setFillColor(CGColor(gray: 1, alpha: 0.95)); ctx.fillPath()
        case .dark:
            ctx.addPath(path); ctx.setFillColor(CGColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 0.92)); ctx.fillPath()
            hairline(ctx, rect: rect, radius: radius, alpha: 0.12)
        case .glass:
            // The renderer puts the blurred video underneath; a dark tint (like macOS's dark material)
            // keeps white text readable on bright video, and a light edge catches the "glass".
            ctx.addPath(path); ctx.setFillColor(CGColor(gray: 0.08, alpha: 0.34)); ctx.fillPath()
            hairline(ctx, rect: rect, radius: radius, alpha: 0.3)
        case .color:
            let c = style.cardColor
            ctx.saveGState()
            ctx.addPath(path); ctx.clip()
            // A soft top-to-bottom sheen, like a lit button.
            let top = CGColor(srgbRed: min(1, c.r * 1.12 + 0.04), green: min(1, c.g * 1.12 + 0.04), blue: min(1, c.b * 1.12 + 0.04), alpha: 1)
            let bottom = CGColor(srgbRed: c.r * 0.88, green: c.g * 0.88, blue: c.b * 0.88, alpha: 1)
            if let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [bottom, top] as CFArray, locations: [0, 1]) {
                ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: h), options: [])
            }
            ctx.restoreGState()
            hairline(ctx, rect: rect, radius: radius, alpha: 0.2)
        case .none:
            break
        }
        let framePath = CGPath(rect: CGRect(x: padX, y: padY, width: textSize.width, height: textSize.height), transform: nil)
        CTFrameDraw(CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), framePath, nil), ctx)
        guard let cg = ctx.makeImage() else { return Title(image: .empty(), radius: radius) }
        return Title(image: CIImage(cgImage: cg), radius: radius)
    }

    private func hairline(_ ctx: CGContext, rect: CGRect, radius: CGFloat, alpha: CGFloat) {
        ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.setStrokeColor(CGColor(gray: 1, alpha: alpha))
        ctx.setLineWidth(1.5)
        ctx.strokePath()
    }

    /// Returns an image with its origin at (0, 0), sized in output pixels.
    func image(_ text: String, kind: Kind, fontSize: CGFloat, maxWidth: CGFloat) -> CIImage {
        let key = Key(text: text, kind: kind, fontSize: Int(fontSize.rounded()), maxWidth: Int(maxWidth.rounded()))
        lock.lock()
        if let hit = cache[key] { lock.unlock(); return hit }
        lock.unlock()

        let img = render(text, kind: kind, fontSize: CGFloat(key.fontSize), maxWidth: CGFloat(key.maxWidth))
        lock.lock()
        if cache.count > 400 { cache.removeAll() }
        cache[key] = img
        lock.unlock()
        return img
    }

    private func render(_ text: String, kind: Kind, fontSize: CGFloat, maxWidth: CGFloat) -> CIImage {
        let weight: NSFont.Weight = kind == .title ? .bold : (kind == .keycap ? .semibold : .medium)
        let font = NSFont.systemFont(ofSize: max(4, fontSize), weight: weight)
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineBreakMode = .byWordWrapping
        let color: NSColor = kind == .title ? NSColor(white: 0.08, alpha: 1) : .white
        let attr = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: color, .paragraphStyle: para,
            .kern: kind == .keycap ? fontSize * 0.04 : 0,
        ])

        let padX: CGFloat, padY: CGFloat
        switch kind {
        case .keycap: padX = fontSize * 0.7; padY = fontSize * 0.42
        case .caption: padX = fontSize * 0.6; padY = fontSize * 0.32
        case .title: padX = fontSize * 0.9; padY = fontSize * 0.5
        }

        let setter = CTFramesetterCreateWithAttributedString(attr)
        let constraint = CGSize(width: max(10, maxWidth - 2 * padX), height: .greatestFiniteMagnitude)
        let fit = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(location: 0, length: 0), nil, constraint, nil)
        let textSize = CGSize(width: ceil(fit.width) + 2, height: ceil(fit.height) + 1)
        let size = CGSize(width: textSize.width + 2 * padX, height: textSize.height + 2 * padY)
        let w = Int(size.width), h = Int(size.height)
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return .empty() }

        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        let radius: CGFloat
        switch kind {
        case .keycap: radius = min(CGFloat(h) / 2, fontSize * 0.55)
        case .caption: radius = fontSize * 0.4
        case .title: radius = fontSize * 0.45
        }
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        ctx.addPath(path)
        switch kind {
        case .keycap: ctx.setFillColor(CGColor(gray: 0.08, alpha: 0.82))
        case .caption: ctx.setFillColor(CGColor(gray: 0, alpha: 0.72))
        case .title: ctx.setFillColor(CGColor(gray: 1, alpha: 0.94))
        }
        ctx.fillPath()
        if kind == .keycap {
            ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), cornerWidth: radius, cornerHeight: radius, transform: nil))
            ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.16))
            ctx.setLineWidth(1.5)
            ctx.strokePath()
        }

        let framePath = CGPath(rect: CGRect(x: padX, y: padY, width: textSize.width, height: textSize.height), transform: nil)
        let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), framePath, nil)
        CTFrameDraw(frame, ctx)

        guard let cg = ctx.makeImage() else { return .empty() }
        return CIImage(cgImage: cg)
    }
}
