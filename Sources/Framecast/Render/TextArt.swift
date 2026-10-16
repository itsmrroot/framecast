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

    private let lock = NSLock()
    private var cache: [Key: CIImage] = [:]

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
