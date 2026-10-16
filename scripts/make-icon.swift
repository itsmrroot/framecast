// Renders the Framecast app icon to a 1024px PNG: swift scripts/make-icon.swift out.png
// The same mark as the logo in the app: a white record symbol on an indigo-to-blue rounded square.
import AppKit

let size = 1024.0
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

// macOS icon grid: 824px rounded square centred in 1024.
let inset = 100.0
let rect = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let squircle = CGPath(roundedRect: rect, cornerWidth: 185, cornerHeight: 185, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: CGColor(gray: 0, alpha: 0.35))
ctx.addPath(squircle); ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(squircle); ctx.clip()
// Top-left indigo to bottom-right blue, like the logo in the app.
let bg = CGGradient(colorsSpace: cs, colors: [
    CGColor(srgbRed: 0.42, green: 0.33, blue: 0.98, alpha: 1),
    CGColor(srgbRed: 0.2, green: 0.6, blue: 1.0, alpha: 1),
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
// Soft top highlight for depth.
let shine = CGGradient(colorsSpace: cs, colors: [
    CGColor(gray: 1, alpha: 0.18), CGColor(gray: 1, alpha: 0),
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(shine, start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.midY), options: [])

// Record symbol: ring and centre dot.
let c = CGPoint(x: size / 2, y: size / 2)
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 24, color: CGColor(gray: 0, alpha: 0.22))
ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
ctx.setLineWidth(58)
ctx.strokeEllipse(in: CGRect(x: c.x - 245, y: c.y - 245, width: 490, height: 490))
ctx.setFillColor(CGColor(gray: 1, alpha: 1))
ctx.fillEllipse(in: CGRect(x: c.x - 128, y: c.y - 128, width: 256, height: 256))
ctx.restoreGState()

let img = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: img)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
