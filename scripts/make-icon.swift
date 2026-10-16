// Renders the Framecast app icon to a 1024px PNG: swift scripts/make-icon.swift out.png
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
let bg = CGGradient(colorsSpace: cs, colors: [
    CGColor(srgbRed: 0.42, green: 0.32, blue: 1.0, alpha: 1),
    CGColor(srgbRed: 0.13, green: 0.55, blue: 1.0, alpha: 1),
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])

// Inner "screen" card
let screen = CGRect(x: 220, y: 300, width: 584, height: 400)
ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: CGColor(gray: 0, alpha: 0.35))
ctx.addPath(CGPath(roundedRect: screen, cornerWidth: 44, cornerHeight: 44, transform: nil))
ctx.setFillColor(CGColor(srgbRed: 0.08, green: 0.08, blue: 0.11, alpha: 1))
ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)

// Record dot
ctx.setFillColor(CGColor(srgbRed: 1, green: 0.3, blue: 0.33, alpha: 1))
ctx.fillEllipse(in: CGRect(x: 262, y: 612, width: 46, height: 46))

// Zoom ring
ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.95))
ctx.setLineWidth(26)
ctx.strokeEllipse(in: CGRect(x: 420, y: 390, width: 170, height: 170))
ctx.setLineCap(.round)
ctx.setLineWidth(34)
ctx.move(to: CGPoint(x: 575, y: 405)); ctx.addLine(to: CGPoint(x: 650, y: 330)); ctx.strokePath()

// Cursor arrow
let arrow = CGMutablePath()
let pts = [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 20.6), CGPoint(x: 4.9, y: 15.9), CGPoint(x: 8.1, y: 23.5),
           CGPoint(x: 11.7, y: 22), CGPoint(x: 8.6, y: 14.6), CGPoint(x: 15.3, y: 14.6)]
let s = 9.0, ox = 640.0, oy = 640.0
arrow.addLines(between: pts.map { CGPoint(x: ox + $0.x * s, y: oy - $0.y * s) })
arrow.closeSubpath()
ctx.setLineJoin(.round)
ctx.addPath(arrow); ctx.setStrokeColor(CGColor(gray: 1, alpha: 1)); ctx.setLineWidth(22); ctx.strokePath()
ctx.addPath(arrow); ctx.setFillColor(CGColor(gray: 0.05, alpha: 1)); ctx.fillPath()
ctx.restoreGState()

let img = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: img)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
