import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Metal
import CoreVideo

/// Composes a final frame: background → shadowed, rounded screen → click effects → cursor,
/// all inside an animated "camera", then the webcam bubble on top.
final class FrameRenderer: @unchecked Sendable {
    static let shared = FrameRenderer()

    let ciContext: CIContext
    private let outputColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    private init() {
        let options: [CIContextOption: Any] = [
            .cacheIntermediates: false,
            .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            .workingFormat: CIFormat.RGBAh,
        ]
        if let device = MTLCreateSystemDefaultDevice() {
            ciContext = CIContext(mtlDevice: device, options: options)
        } else {
            ciContext = CIContext(options: options)
        }
    }

    func render(model: RenderModel, compTime: Double, screen: CVPixelBuffer?, camera: CVPixelBuffer?, into output: CVPixelBuffer) {
        let size = CGSize(width: CVPixelBufferGetWidth(output), height: CVPixelBufferGetHeight(output))
        let image = compose(model: model, compTime: compTime,
                            screen: screen.map { CIImage(cvPixelBuffer: $0) },
                            camera: camera.map { CIImage(cvPixelBuffer: $0) },
                            size: size)
        ciContext.render(image, to: output, bounds: CGRect(origin: .zero, size: size), colorSpace: outputColorSpace)
    }

    func compose(model: RenderModel, compTime: Double, screen: CIImage?, camera: CIImage?, size: CGSize) -> CIImage {
        let style = model.style
        let L = model.layout(for: size)
        let sr = L.screenRect
        let t = model.editMap.sourceTime(comp: compTime)

        // Virtual camera
        let cam = model.camera.state(at: t)
        let s = CGFloat(max(1, cam.scale))
        let focus = CGPoint(x: sr.minX + cam.focus.x * sr.width, y: sr.maxY - cam.focus.y * sr.height)
        let vw = size.width / s, vh = size.height / s
        let cx = clampAxis(focus.x, view: vw, lo: sr.minX, hi: sr.maxX, total: size.width)
        let cy = clampAxis(focus.y, view: vh, lo: sr.minY, hi: sr.maxY, total: size.height)
        let ox = cx - vw / 2, oy = cy - vh / 2
        let M = CGAffineTransform(a: s, b: 0, c: 0, d: s, tx: -ox * s, ty: -oy * s)

        var out = model.background(size: size, ciContext: ciContext).transformed(by: M)

        // Screen
        let target = sr.applying(M)
        if let screen, screen.extent.width > 0 {
            let kx = target.width / screen.extent.width
            let ky = target.height / screen.extent.height
            var img: CIImage
            if kx < 0.8 {
                img = screen.applyingFilter("CILanczosScaleTransform", parameters: [
                    kCIInputScaleKey: ky, kCIInputAspectRatioKey: kx / ky,
                ])
            } else {
                img = screen.transformed(by: CGAffineTransform(scaleX: kx, y: ky))
            }
            img = img.transformed(by: CGAffineTransform(translationX: target.minX - img.extent.minX, y: target.minY - img.extent.minY))
            let radius = CGFloat(style.cornerRadius) * L.unit * s
            if radius > 0.5 {
                img = img.applyingFilter("CISourceInCompositing", parameters: [
                    kCIInputBackgroundImageKey: roundedRect(target, radius: radius),
                ])
            } else {
                img = img.cropped(to: target)
            }
            out = img.composited(over: out)
        }

        // Cursor + clicks
        if style.showCursor, let cp = model.cursor, cp.hasData {
            func canvasPoint(_ p: CGPoint) -> CGPoint {
                CGPoint(x: sr.minX + p.x * sr.width, y: sr.maxY - p.y * sr.height).applying(M)
            }
            let ptScale = sr.width / max(model.pointSize.width, 1)
            let cursorScale = CGFloat(style.cursorSize)

            if style.clickEffect != .none {
                let duration = 0.5
                for c in model.clicks where c.button == 0 && t >= c.t && t - c.t < duration {
                    let p = (t - c.t) / duration
                    let pos = canvasPoint(cp.state(at: c.t).position)
                    let r = CGFloat(10 + 34 * easeOutCubic(p)) * ptScale * s * cursorScale / 1.6
                    let alpha = CGFloat(1 - p)
                    out = clickEffect(style.clickEffect, at: pos, radius: r, alpha: alpha, unit: L.unit * s).composited(over: out)
                }
            }

            let st = cp.state(at: t)
            if st.opacity > 0.01 {
                let (art, info) = model.cursorArt(at: t)
                let pxPerPt = ptScale * s * cursorScale * model.pressScale(at: t)
                let pos = canvasPoint(st.position)
                let k = pxPerPt * CGFloat(info.width) / max(art.extent.width, 1)
                var img = art.transformed(by: CGAffineTransform(scaleX: k, y: k))
                let originX = pos.x - CGFloat(info.hotX) * pxPerPt
                let originY = pos.y - CGFloat(info.height - info.hotY) * pxPerPt
                img = img.transformed(by: CGAffineTransform(translationX: originX - img.extent.minX, y: originY - img.extent.minY))

                if style.cursorMotionBlur {
                    // pixels per frame at 60 fps
                    let vx = st.velocity.dx * sr.width * s / 60
                    let vy = -st.velocity.dy * sr.height * s / 60
                    let speed = hypot(vx, vy)
                    if speed > 3 * L.unit {
                        let len = min(speed * 1.2, 90 * L.unit * s)
                        let dx = vx / speed * len, dy = vy / speed * len
                        var ghosts = CIImage.empty()
                        let n = 6
                        for i in stride(from: n, through: 1, by: -1) {
                            let f = CGFloat(i) / CGFloat(n)
                            let g = withAlpha(img, 0.32 * (1 - f) + 0.04)
                                .transformed(by: CGAffineTransform(translationX: -dx * f, y: -dy * f))
                            ghosts = g.composited(over: ghosts)
                        }
                        out = withAlpha(ghosts, CGFloat(st.opacity)).composited(over: out)
                    }
                }
                if st.opacity < 0.999 { img = withAlpha(img, CGFloat(st.opacity)) }
                out = img.composited(over: out)
            }
        }

        // Webcam bubble (not affected by the camera zoom)
        if style.camera.visible, let camera, camera.extent.width > 0 {
            out = webcamOverlay(camera, style: style.camera, size: size, unit: L.unit, zoom: s).composited(over: out)
        }

        return out.cropped(to: CGRect(origin: .zero, size: size))
    }

    // MARK: Helpers

    private func clampAxis(_ c: CGFloat, view v: CGFloat, lo: CGFloat, hi: CGFloat, total: CGFloat) -> CGFloat {
        var c = c
        if v <= hi - lo {
            c = min(max(c, lo + v / 2), hi - v / 2)
        } else {
            c = min(max(c, hi - v / 2), lo + v / 2)
        }
        return min(max(c, v / 2), total - v / 2)
    }

    private func roundedRect(_ rect: CGRect, radius: CGFloat, color: CIColor = .white) -> CIImage {
        let f = CIFilter.roundedRectangleGenerator()
        f.extent = rect
        f.radius = Float(min(radius, min(rect.width, rect.height) / 2))
        f.color = color
        return f.outputImage ?? CIImage.empty()
    }

    private func withAlpha(_ img: CIImage, _ a: CGFloat) -> CIImage {
        img.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: a)])
    }

    private func disc(at p: CGPoint, radius r: CGFloat, color: CIColor) -> CIImage {
        let f = CIFilter.radialGradient()
        f.center = p
        f.radius0 = Float(max(0, r - 1.5))
        f.radius1 = Float(r)
        f.color0 = color
        f.color1 = CIColor(red: 0, green: 0, blue: 0, alpha: 0)
        return (f.outputImage ?? .empty()).cropped(to: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
    }

    private func clickEffect(_ kind: ClickEffect, at p: CGPoint, radius r: CGFloat, alpha: CGFloat, unit: CGFloat) -> CIImage {
        switch kind {
        case .none:
            return .empty()
        case .ripple:
            let fill = disc(at: p, radius: r, color: CIColor(red: 1, green: 1, blue: 1, alpha: 0.38 * alpha))
            let edge = ring(at: p, radius: r, thickness: 2 * unit, color: CIColor(red: 0.3, green: 0.3, blue: 0.35, alpha: 0.35 * alpha))
            return edge.composited(over: fill)
        case .ring:
            return ring(at: p, radius: r, thickness: 3.5 * unit, color: CIColor(red: 1, green: 1, blue: 1, alpha: 0.9 * alpha))
        }
    }

    private func ring(at p: CGPoint, radius r: CGFloat, thickness: CGFloat, color: CIColor) -> CIImage {
        let outer = disc(at: p, radius: r, color: color)
        let inner = CIFilter.radialGradient()
        inner.center = p
        inner.radius0 = Float(max(0, r - thickness))
        inner.radius1 = Float(max(0, r - thickness) + 1.5)
        inner.color0 = CIColor(red: 0, green: 0, blue: 0, alpha: 0)
        inner.color1 = CIColor(red: 1, green: 1, blue: 1, alpha: 1)
        let mask = (inner.outputImage ?? .empty()).cropped(to: outer.extent)
        return outer.applyingFilter("CISourceInCompositing", parameters: [kCIInputBackgroundImageKey: mask])
    }

    private func webcamOverlay(_ cam: CIImage, style cs: CameraStyle, size: CGSize, unit: CGFloat, zoom: CGFloat) -> CIImage {
        let minDim = min(size.width, size.height)
        var d = CGFloat(cs.size) * minDim
        if cs.shrinkOnZoom {
            d *= CGFloat(lerp(1, 0.7, Double(min(1, max(0, zoom - 1)))))
        }
        let e = cam.extent
        let side = min(e.width, e.height)
        var img = cam.cropped(to: CGRect(x: e.midX - side / 2, y: e.midY - side / 2, width: side, height: side))
        img = img.transformed(by: CGAffineTransform(translationX: -img.extent.minX, y: -img.extent.minY))
        if cs.mirror {
            img = img.transformed(by: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: side, ty: 0))
        }
        img = img.transformed(by: CGAffineTransform(scaleX: d / side, y: d / side))

        let margin = 0.04 * minDim
        let x: CGFloat, y: CGFloat
        switch cs.corner {
        case .topLeft: x = margin; y = size.height - margin - d
        case .topRight: x = size.width - margin - d; y = size.height - margin - d
        case .bottomLeft: x = margin; y = margin
        case .bottomRight: x = size.width - margin - d; y = margin
        }
        img = img.transformed(by: CGAffineTransform(translationX: x - img.extent.minX, y: y - img.extent.minY))
        let rect = CGRect(x: x, y: y, width: d, height: d)
        let radius: CGFloat
        switch cs.shape {
        case .circle: radius = d / 2
        case .rounded: radius = d * 0.18
        case .square: radius = 0
        }
        img = radius > 0
            ? img.applyingFilter("CISourceInCompositing", parameters: [kCIInputBackgroundImageKey: roundedRect(rect, radius: radius)])
            : img.cropped(to: rect)

        var result = img
        if cs.border {
            let bw = 3 * unit
            let border = roundedRect(rect.insetBy(dx: -bw, dy: -bw), radius: radius > 0 ? radius + bw : 0,
                                     color: CIColor(red: 1, green: 1, blue: 1, alpha: 0.9))
            result = result.composited(over: border)
        }
        let shadowRect = rect.insetBy(dx: -2 * unit, dy: -2 * unit).offsetBy(dx: 0, dy: -8 * unit)
        let shadow = roundedRect(shadowRect, radius: radius > 0 ? radius : 0, color: CIColor(red: 0, green: 0, blue: 0, alpha: 0.45))
            .applyingGaussianBlur(sigma: 14 * unit)
        return result.composited(over: shadow)
    }
}
