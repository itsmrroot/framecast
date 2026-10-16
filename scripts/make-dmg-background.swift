// Renders the DMG window background at 1x and 2x: swift scripts/make-dmg-background.swift out-dir
// The window is 660 × 400 points; the app icon sits at (170, 190) and Applications at (490, 190).
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let W = 660.0, H = 400.0
let cs = CGColorSpace(name: CGColorSpace.sRGB)!

func render(scale: Double) -> CGImage {
    let ctx = CGContext(data: nil, width: Int(W * scale), height: Int(H * scale), bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: scale, y: scale)
    // Points from here on, bottom-left origin. Finder places icons with a top-left origin, so y = H - finderY.

    // Soft light gradient so Finder's dark icon labels stay readable.
    let bg = CGGradient(colorsSpace: cs, colors: [
        CGColor(srgbRed: 0.97, green: 0.97, blue: 1.0, alpha: 1),
        CGColor(srgbRed: 0.90, green: 0.90, blue: 0.99, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: H), end: CGPoint(x: W, y: 0), options: [])

    // Faint accent glow behind the icons.
    let glow = CGGradient(colorsSpace: cs, colors: [
        CGColor(srgbRed: 0.42, green: 0.32, blue: 1.0, alpha: 0.12),
        CGColor(srgbRed: 0.42, green: 0.32, blue: 1.0, alpha: 0),
    ] as CFArray, locations: [0, 1])!
    for x in [170.0, 490.0] {
        ctx.drawRadialGradient(glow, startCenter: CGPoint(x: x, y: H - 190), startRadius: 0,
                               endCenter: CGPoint(x: x, y: H - 190), endRadius: 120, options: [])
    }

    // Arrow from the app to Applications.
    let accent = CGColor(srgbRed: 0.42, green: 0.32, blue: 1.0, alpha: 0.85)
    let y = H - 190
    ctx.setStrokeColor(accent)
    ctx.setLineWidth(5)
    ctx.setLineCap(.round)
    ctx.setLineDash(phase: 0, lengths: [2, 11])
    ctx.move(to: CGPoint(x: 262, y: y)); ctx.addLine(to: CGPoint(x: 384, y: y)); ctx.strokePath()
    ctx.setLineDash(phase: 0, lengths: [])
    ctx.setFillColor(accent)
    ctx.move(to: CGPoint(x: 404, y: y)); ctx.addLine(to: CGPoint(x: 384, y: y + 12)); ctx.addLine(to: CGPoint(x: 384, y: y - 12))
    ctx.closePath(); ctx.fillPath()

    // Title and hint.
    func text(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, y: Double) {
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        let str = NSAttributedString(string: s, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: para,
        ])
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        str.draw(in: CGRect(x: 0, y: y, width: W, height: size * 1.5))
        NSGraphicsContext.restoreGraphicsState()
    }
    text("Install Framecast", size: 22, weight: .bold, color: NSColor(srgbRed: 0.1, green: 0.1, blue: 0.16, alpha: 1), y: H - 62)
    text("Drag Framecast into the Applications folder", size: 13, weight: .regular,
         color: NSColor(srgbRed: 0.35, green: 0.35, blue: 0.45, alpha: 1), y: 84)
    return ctx.makeImage()!
}

for (scale, name) in [(1.0, "background.png"), (2.0, "background@2x.png")] {
    let rep = NSBitmapImageRep(cgImage: render(scale: scale))
    rep.size = NSSize(width: W, height: H)
    try! rep.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent(name))
}
print("Wrote \(outDir.path)/background.png and background@2x.png")
