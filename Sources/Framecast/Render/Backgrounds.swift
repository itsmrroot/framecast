import Foundation
import CoreGraphics
import ImageIO
import CoreImage
import AppKit

struct GradientPreset {
    let name: String
    let colors: [RGBA]
    /// Angle in degrees, 0 = left→right, 90 = bottom→top.
    let angle: Double
}

enum Backgrounds {
    static let gradients: [GradientPreset] = [
        GradientPreset(name: "Aurora", colors: [RGBA(hex: 0x7F5AF0), RGBA(hex: 0x2CB1FF)], angle: 315),
        GradientPreset(name: "Sunset", colors: [RGBA(hex: 0xFF7A59), RGBA(hex: 0xFF3D77), RGBA(hex: 0x8C3DFF)], angle: 300),
        GradientPreset(name: "Ocean", colors: [RGBA(hex: 0x0EA5E9), RGBA(hex: 0x1E3A8A)], angle: 270),
        GradientPreset(name: "Mint", colors: [RGBA(hex: 0x34D399), RGBA(hex: 0x0EA5E9)], angle: 315),
        GradientPreset(name: "Peach", colors: [RGBA(hex: 0xFDBA74), RGBA(hex: 0xF472B6)], angle: 300),
        GradientPreset(name: "Lavender", colors: [RGBA(hex: 0xC4B5FD), RGBA(hex: 0x818CF8), RGBA(hex: 0x6366F1)], angle: 290),
        GradientPreset(name: "Midnight", colors: [RGBA(hex: 0x1E1B4B), RGBA(hex: 0x312E81), RGBA(hex: 0x0F172A)], angle: 300),
        GradientPreset(name: "Forest", colors: [RGBA(hex: 0x14532D), RGBA(hex: 0x22C55E)], angle: 60),
        GradientPreset(name: "Candy", colors: [RGBA(hex: 0xF0ABFC), RGBA(hex: 0x93C5FD)], angle: 330),
        GradientPreset(name: "Ember", colors: [RGBA(hex: 0xF59E0B), RGBA(hex: 0xDC2626)], angle: 300),
        GradientPreset(name: "Slate", colors: [RGBA(hex: 0x475569), RGBA(hex: 0x0F172A)], angle: 270),
        GradientPreset(name: "Sky", colors: [RGBA(hex: 0xE0F2FE), RGBA(hex: 0x7DD3FC), RGBA(hex: 0x3B82F6)], angle: 270),
        GradientPreset(name: "Rose", colors: [RGBA(hex: 0xFECDD3), RGBA(hex: 0xFB7185), RGBA(hex: 0xBE123C)], angle: 315),
        GradientPreset(name: "Lime", colors: [RGBA(hex: 0xD9F99D), RGBA(hex: 0x4ADE80)], angle: 300),
        GradientPreset(name: "Graphite", colors: [RGBA(hex: 0x27272A), RGBA(hex: 0x52525B)], angle: 300),
        GradientPreset(name: "Cosmic", colors: [RGBA(hex: 0x0F0C29), RGBA(hex: 0x302B63), RGBA(hex: 0x24243E)], angle: 300),
    ]

    static let solidColors: [RGBA] = [
        RGBA(hex: 0xFFFFFF), RGBA(hex: 0xF4F4F5), RGBA(hex: 0x18181B), RGBA(hex: 0x000000),
        RGBA(hex: 0x6366F1), RGBA(hex: 0x0EA5E9), RGBA(hex: 0x10B981), RGBA(hex: 0xF59E0B),
        RGBA(hex: 0xEF4444), RGBA(hex: 0xEC4899),
    ]

    /// macOS wallpapers available on this machine.
    static let wallpapers: [URL] = {
        let dir = URL(fileURLWithPath: "/System/Library/Desktop Pictures")
        let exts: Set<String> = ["heic", "jpg", "jpeg", "png"]
        let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return items.filter { exts.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }()

    static func defaultWallpaper() -> String? {
        let preferred = ["Sonoma.heic", "Mac Purple.heic", "Radial Sky Blue.heic"]
        for name in preferred {
            if let u = wallpapers.first(where: { $0.lastPathComponent == name }) { return u.path }
        }
        return wallpapers.first?.path
    }

    // MARK: Image cache

    private static let cache = NSCache<NSString, CGImage>()
    private static let thumbCache = NSCache<NSString, NSImage>()

    /// Loads an image downsampled so its long side is at most `maxPixel`.
    static func image(path: String, maxPixel: Int = 3200) -> CGImage? {
        let key = "\(path)#\(maxPixel)" as NSString
        if let img = cache.object(forKey: key) { return img }
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        cache.setObject(img, forKey: key)
        return img
    }

    static func thumbnail(path: String) -> NSImage? {
        let key = path as NSString
        if let img = thumbCache.object(forKey: key) { return img }
        guard let cg = image(path: path, maxPixel: 240) else { return nil }
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        thumbCache.setObject(img, forKey: key)
        return img
    }

    // MARK: Drawing

    static func drawGradient(_ preset: GradientPreset, in ctx: CGContext, rect: CGRect) {
        let colors = preset.colors.map(\.cgColor) as CFArray
        guard let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: nil) else { return }
        let a = preset.angle * .pi / 180
        let dx = cos(a), dy = sin(a)
        let half = (abs(rect.width * dx) + abs(rect.height * dy)) / 2
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let start = CGPoint(x: c.x - dx * half, y: c.y - dy * half)
        let end = CGPoint(x: c.x + dx * half, y: c.y + dy * half)
        ctx.drawLinearGradient(g, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    /// Renders the background fill for a canvas of the given size.
    static func render(_ bg: BackgroundStyle, size: CGSize, ciContext: CIContext) -> CGImage? {
        let w = Int(size.width), h = Int(size.height)
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        ctx.interpolationQuality = .high

        var imagePath: String?
        switch bg.kind {
        case .gradient:
            if let stops = bg.customGradient, stops.count >= 2 {
                drawGradient(GradientPreset(name: "Custom", colors: stops, angle: 315), in: ctx, rect: rect)
            } else {
                drawGradient(gradients[clamp(bg.gradientIndex, 0, gradients.count - 1)], in: ctx, rect: rect)
            }
        case .solid:
            ctx.setFillColor(bg.solid.cgColor)
            ctx.fill(rect)
        case .wallpaper:
            imagePath = bg.wallpaperPath ?? defaultWallpaper()
        case .image:
            imagePath = bg.imagePath
        }

        if let path = imagePath {
            if var img = image(path: path) {
                if bg.blur > 0.5 {
                    let ci = CIImage(cgImage: img)
                    let radius = bg.blur * Double(img.width) / 1000
                    let blurred = ci.clampedToExtent()
                        .applyingGaussianBlur(sigma: radius)
                        .cropped(to: ci.extent)
                    if let out = ciContext.createCGImage(blurred, from: ci.extent) { img = out }
                }
                let target = rect.aspectFill(aspect: CGFloat(img.width) / CGFloat(img.height))
                ctx.draw(img, in: target)
            } else {
                drawGradient(gradients[0], in: ctx, rect: rect)
            }
        }
        guard let out = ctx.makeImage() else { return nil }
        // The Hue slider rotates the gradient's colors.
        if bg.kind == .gradient, abs(bg.gradientHue) > 0.5 {
            let ci = CIImage(cgImage: out).applyingFilter("CIHueAdjust", parameters: [
                kCIInputAngleKey: bg.gradientHue * .pi / 180,
            ])
            return ciContext.createCGImage(ci, from: ci.extent) ?? out
        }
        return out
    }
}
