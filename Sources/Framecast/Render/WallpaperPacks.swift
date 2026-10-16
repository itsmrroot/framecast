import Foundation
import CoreGraphics
import CoreImage
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Original wallpapers drawn by Framecast (no image files shipped): generated once per pack, then cached on disk
/// so projects can refer to them by path like any other wallpaper.
enum WallpaperPack: String, CaseIterable, Identifiable {
    case aurora, waves, glass, radiant, midnight, mesh
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    static let perPack = 8

    /// Two to four colours per wallpaper, sRGB hex.
    var palettes: [[UInt32]] {
        switch self {
        case .aurora:
            return [[0x0B1026, 0x3AE3C3, 0x5B6CFF, 0xB84DFF], [0x080A1A, 0xFF5FA2, 0x7A5CFF, 0x2EC5FF],
                    [0x0A0F1F, 0x40FF9A, 0x00B3FF, 0x6A4BFF], [0x120A1E, 0xFF8A3D, 0xFF3D7F, 0x8A3DFF],
                    [0x07121A, 0x2BD9FF, 0x2B6BFF, 0x9DFF6A], [0x0E0B1C, 0xF7D046, 0xFF6B6B, 0x6C5BFF],
                    [0x060914, 0xA36BFF, 0xFF6BD6, 0x6BE4FF], [0x0B0D12, 0x7CFFCB, 0x47A8FF, 0xFF7CE0]]
        case .waves:
            return [[0x1A1446, 0x5B4CF5, 0x9D7BFF, 0xF1C6FF], [0x0E2A47, 0x1F8FFF, 0x5BD1FF, 0xD6F6FF],
                    [0x3A0F2E, 0xE5397A, 0xFF8F6B, 0xFFE1B3], [0x0F3324, 0x18B37E, 0x7DE8B5, 0xE8FFF4],
                    [0x2B1A0A, 0xFF8A00, 0xFFC24B, 0xFFF2CC], [0x1B1B2F, 0x5F6BFF, 0xFF6BB5, 0xFFD36B],
                    [0x102030, 0x00C2A8, 0x3D7BFF, 0xC37BFF], [0x241536, 0xFF5E7E, 0xA35BFF, 0x5BC8FF]]
        case .glass:
            return [[0x6A5BFF, 0xFF7AC6, 0x7AD9FF], [0x2EC5FF, 0x7A5CFF, 0xFFB86B], [0xFF7A59, 0xFFD36B, 0xFF4D8D],
                    [0x3AE3C3, 0x2B6BFF, 0xB84DFF], [0xA3B8FF, 0xFFC2E0, 0xC2FFF0], [0x1F1F3A, 0x5B4CF5, 0x00D1FF],
                    [0xFF9A3D, 0xFF5FA2, 0x5B6CFF], [0x7CFFCB, 0x47A8FF, 0xF7D046]]
        case .radiant:
            return [[0x0B0B1A, 0xFF8A3D, 0xFFD36B], [0x0A0F24, 0x5B6CFF, 0xA9D1FF], [0x1A0716, 0xFF3D7F, 0xFFB3D1],
                    [0x04140F, 0x18D18A, 0xC2FFE6], [0x14081F, 0xA35BFF, 0xFFC2FF], [0x0A1420, 0x00B3FF, 0xFFFFFF],
                    [0x1F0D05, 0xFF5E2B, 0xFFE08A], [0x0C0C14, 0xF7D046, 0xFFFFFF]]
        case .midnight:
            return [[0x05060F, 0x3D2BFF, 0x00D1FF], [0x07050F, 0xFF2BD6, 0x6B2BFF], [0x030A0C, 0x00FFC2, 0x0077FF],
                    [0x0A0507, 0xFF3D3D, 0xFF8A3D], [0x06070D, 0x8A5CFF, 0xFF5FA2], [0x040810, 0x2BFFEA, 0xD62BFF],
                    [0x08060A, 0xFFD02B, 0xFF2B6B], [0x05080A, 0x4DFF7A, 0x2BB3FF]]
        case .mesh:
            return [[0xFF9A8B, 0xFF6A88, 0x7A5CFF, 0x2EC5FF], [0x84FAB0, 0x8FD3F4, 0x6A5BFF, 0xFDD0FF],
                    [0xF6D365, 0xFDA085, 0xFF5FA2, 0x5B6CFF], [0x43E97B, 0x38F9D7, 0x2B6BFF, 0x0B1026],
                    [0xA18CD1, 0xFBC2EB, 0xFAD0C4, 0x8EC5FC], [0x30CFD0, 0x330867, 0xE0C3FC, 0x5B4CF5],
                    [0xFF0844, 0xFFB199, 0xFEE140, 0xFA709A], [0x0BA360, 0x3CBA92, 0x2575FC, 0x6A11CB]]
        }
    }

    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Framecast/Wallpapers", isDirectory: true)
    }

    func url(_ index: Int) -> URL {
        WallpaperPack.folder.appendingPathComponent("\(rawValue)-\(index + 1).heic")
    }

    var urls: [URL] { (0..<WallpaperPack.perPack).map(url) }

    var isGenerated: Bool { urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) } }

    /// Draws any missing wallpapers of this pack (off the main thread).
    func generate() async {
        let pack = self
        await Task.detached(priority: .userInitiated) {
            try? FileManager.default.createDirectory(at: WallpaperPack.folder, withIntermediateDirectories: true)
            for i in 0..<WallpaperPack.perPack where !FileManager.default.fileExists(atPath: pack.url(i).path) {
                guard let img = WallpaperPainter.paint(pack, index: i, size: CGSize(width: 2048, height: 1280)),
                      let dest = CGImageDestinationCreateWithURL(pack.url(i) as CFURL, UTType.heic.identifier as CFString, 1, nil)
                else { continue }
                // HEIC keeps smooth gradients small (a fraction of the JPEG size).
                CGImageDestinationAddImage(dest, img, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
                CGImageDestinationFinalize(dest)
            }
        }.value
    }
}

/// The drawing behind each pack: soft shapes on a canvas, heavily blurred, with fine grain against banding.
enum WallpaperPainter {
    private static let ci = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])

    static func paint(_ pack: WallpaperPack, index: Int, size: CGSize) -> CGImage? {
        let colors = pack.palettes[index % pack.palettes.count].map { NSColor(rgb: $0).cgColor }
        var rng = SeededRandom(seed: UInt64(index + 1) * 7919 + UInt64(pack.rawValue.hashValueStable))
        let w = Int(size.width), h = Int(size.height)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let rect = CGRect(origin: .zero, size: size)
        var blur: Double = 0
        var overlay: ((CGContext) -> Void)?

        switch pack {
        case .aurora, .midnight:
            ctx.setFillColor(colors[0]); ctx.fill(rect)
            let count = pack == .aurora ? 6 : 4
            for i in 0..<count {
                let c = colors[1 + i % (colors.count - 1)]
                let r = CGFloat(rng.next(in: 0.25...0.5)) * size.width
                let center = CGPoint(x: CGFloat(rng.next(in: 0...1)) * size.width,
                                     y: CGFloat(rng.next(in: pack == .aurora ? 0.3...1.0 : 0...1)) * size.height)
                ctx.setFillColor(c.copy(alpha: pack == .aurora ? 0.85 : 0.7)!)
                ctx.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r * 0.55, width: r * 2, height: r * 1.1))
            }
            blur = pack == .aurora ? 220 : 260
            if pack == .midnight {
                // A sprinkle of faint stars on top.
                overlay = { c in
                    for _ in 0..<160 {
                        let s = CGFloat(rng.next(in: 1...3.2))
                        c.setFillColor(CGColor(gray: 1, alpha: CGFloat(rng.next(in: 0.15...0.6))))
                        c.fillEllipse(in: CGRect(x: CGFloat(rng.next(in: 0...1)) * size.width, y: CGFloat(rng.next(in: 0...1)) * size.height, width: s, height: s))
                    }
                }
            }
        case .waves:
            fillLinear(ctx, rect, [colors[0], colors[1]], angle: 290)
            // Stacked ribbons from back to front, each lighter than the last.
            for band in 0..<5 {
                let t = CGFloat(band) / 4
                let base = size.height * (0.85 - t * 0.7)
                let amp = size.height * CGFloat(rng.next(in: 0.06...0.14))
                let freq = CGFloat(rng.next(in: 0.8...1.8))
                let phase = CGFloat(rng.next(in: 0...(2 * .pi)))
                let path = CGMutablePath()
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 0, y: base))
                var x: CGFloat = 0
                while x <= size.width {
                    let y = base + amp * sin(freq * x / size.width * 2 * .pi + phase)
                    path.addLine(to: CGPoint(x: x, y: y))
                    x += 8
                }
                path.addLine(to: CGPoint(x: size.width, y: 0))
                path.closeSubpath()
                let c1 = colors[min(colors.count - 1, 1 + band % (colors.count - 1))]
                let c2 = colors[min(colors.count - 1, 1 + (band + 1) % (colors.count - 1))]
                ctx.saveGState()
                ctx.addPath(path); ctx.clip()
                fillLinear(ctx, rect, [c1.copy(alpha: 0.95)!, c2.copy(alpha: 0.95)!], angle: Double(rng.next(in: 200...340)))
                ctx.restoreGState()
                // A glowing crest along the top of each ribbon.
                ctx.addPath(path)
                ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.18))
                ctx.setLineWidth(6)
                ctx.strokePath()
            }
            blur = 18
        case .glass:
            fillLinear(ctx, rect, [colors[0], colors[1]], angle: Double(rng.next(in: 0...360)))
            for i in 0..<4 {
                let c = colors[i % colors.count]
                let r = CGFloat(rng.next(in: 0.2...0.38)) * size.width
                ctx.setFillColor(c)
                ctx.fillEllipse(in: CGRect(x: CGFloat(rng.next(in: -0.1...0.9)) * size.width, y: CGFloat(rng.next(in: -0.1...0.8)) * size.height, width: r * 2, height: r * 2))
            }
            blur = 160
            // Frosted panes with bright edges.
            overlay = { c in
                for _ in 0..<3 {
                    let pw = CGFloat(rng.next(in: 0.28...0.45)) * size.width
                    let ph = CGFloat(rng.next(in: 0.3...0.55)) * size.height
                    let pane = CGRect(x: CGFloat(rng.next(in: 0.05...0.6)) * size.width, y: CGFloat(rng.next(in: 0.05...0.5)) * size.height, width: pw, height: ph)
                    let path = CGPath(roundedRect: pane, cornerWidth: 56, cornerHeight: 56, transform: nil)
                    c.setShadow(offset: CGSize(width: 0, height: -24), blur: 60, color: CGColor(gray: 0, alpha: 0.18))
                    c.addPath(path); c.setFillColor(CGColor(gray: 1, alpha: 0.14)); c.fillPath()
                    c.setShadow(offset: .zero, blur: 0, color: nil)
                    c.addPath(path); c.setStrokeColor(CGColor(gray: 1, alpha: 0.45)); c.setLineWidth(3); c.strokePath()
                }
            }
        case .radiant:
            ctx.setFillColor(colors[0]); ctx.fill(rect)
            let fromRight = rng.next(in: 0...1) >= 0.5
            let corner = CGPoint(x: fromRight ? size.width : 0, y: size.height * CGFloat(rng.next(in: 0.6...1.1)))
            let mirror: CGFloat = fromRight ? -1 : 1 // rays always fan across the image, from either side
            // Light rays fanning out from a corner.
            for i in 0..<14 {
                let a = Double(i) / 14 * .pi * 0.75 - 0.5 + rng.next(in: -0.05...0.05)
                let len = size.width * 1.6
                let spread = rng.next(in: 0.02...0.06)
                let path = CGMutablePath()
                path.move(to: corner)
                path.addLine(to: CGPoint(x: corner.x + mirror * CGFloat(cos(a - spread)) * len, y: corner.y - CGFloat(sin(a - spread)) * len))
                path.addLine(to: CGPoint(x: corner.x + mirror * CGFloat(cos(a + spread)) * len, y: corner.y - CGFloat(sin(a + spread)) * len))
                path.closeSubpath()
                ctx.addPath(path)
                ctx.setFillColor(colors[1 + i % (colors.count - 1)].copy(alpha: CGFloat(rng.next(in: 0.25...0.6)))!)
                ctx.fillPath()
            }
            if let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [colors.last!, colors[1].copy(alpha: 0)!] as CFArray, locations: [0, 1]) {
                ctx.drawRadialGradient(g, startCenter: corner, startRadius: 0, endCenter: corner, endRadius: size.width * 0.7, options: [])
            }
            blur = 40
        case .mesh:
            // Bilinear blend of four corner colours, then soft blobs for extra depth.
            let cs = colors.count >= 4 ? colors : colors + colors
            let cells = 48
            let cw = size.width / CGFloat(cells), chh = size.height / CGFloat(cells)
            let comps = cs.prefix(4).map { NSColor(cgColor: $0)!.usingColorSpace(.sRGB)! }
            for yi in 0..<cells {
                for xi in 0..<cells {
                    let u = CGFloat(xi) / CGFloat(cells - 1), v = CGFloat(yi) / CGFloat(cells - 1)
                    func mix(_ k: (NSColor) -> CGFloat) -> CGFloat {
                        let top = k(comps[0]) * (1 - u) + k(comps[1]) * u
                        let bot = k(comps[2]) * (1 - u) + k(comps[3]) * u
                        return top * v + bot * (1 - v)
                    }
                    ctx.setFillColor(CGColor(srgbRed: mix { $0.redComponent }, green: mix { $0.greenComponent }, blue: mix { $0.blueComponent }, alpha: 1))
                    ctx.fill(CGRect(x: CGFloat(xi) * cw, y: CGFloat(yi) * chh, width: cw + 1, height: chh + 1))
                }
            }
            for i in 0..<3 {
                let r = CGFloat(rng.next(in: 0.15...0.3)) * size.width
                ctx.setFillColor(cs[i].copy(alpha: 0.5)!)
                ctx.fillEllipse(in: CGRect(x: CGFloat(rng.next(in: 0...0.8)) * size.width, y: CGFloat(rng.next(in: 0...0.8)) * size.height, width: r * 2, height: r * 2))
            }
            blur = 120
        }

        guard let base = ctx.makeImage() else { return nil }
        var img = CIImage(cgImage: base)
        if blur > 0 {
            img = img.clampedToExtent().applyingGaussianBlur(sigma: blur).cropped(to: rect)
        }
        // Fine grain stops gradients from banding.
        let noise = CIFilter(name: "CIRandomGenerator")!.outputImage!.cropped(to: rect)
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputAVector": CIVector(x: 0.012, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: 1, y: 1, z: 1, w: 0),
            ])
        img = noise.composited(over: img)
        guard var out = ci.createCGImage(img, from: rect) else { return nil }
        if let overlay, let octx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            octx.draw(out, in: rect)
            overlay(octx)
            if let o = octx.makeImage() { out = o }
        }
        return out
    }

    private static func fillLinear(_ ctx: CGContext, _ rect: CGRect, _ colors: [CGColor], angle: Double) {
        guard let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil) else { return }
        let a = angle * .pi / 180
        let dx = CGFloat(cos(a)), dy = CGFloat(sin(a))
        let half = (abs(rect.width * dx) + abs(rect.height * dy)) / 2
        let c = CGPoint(x: rect.midX, y: rect.midY)
        ctx.drawLinearGradient(g, start: CGPoint(x: c.x - dx * half, y: c.y - dy * half), end: CGPoint(x: c.x + dx * half, y: c.y + dy * half),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
}

/// Deterministic random numbers, so each wallpaper looks the same every time it's generated.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func nextUInt() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func next(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + Double(nextUInt() % 1_000_000) / 1_000_000 * (range.upperBound - range.lowerBound)
    }
}

private extension String {
    /// Stable across launches (Swift's hashValue is randomised per process).
    var hashValueStable: Int { unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) } & 0xFFFF }
}

private extension NSColor {
    convenience init(rgb: UInt32) {
        self.init(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}
