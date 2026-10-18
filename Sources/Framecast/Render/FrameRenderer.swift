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
    let text = TextArt()
    private let segmenter = PersonSegmenter()
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
        let view = viewTransform(model: model, sourceTime: t, size: size)
        let cam = view.cam, s = view.scale, ox = view.origin.x, oy = view.origin.y, M = view.transform

        var out = model.background(size: size, ciContext: ciContext).transformed(by: M)

        // Screen (cropped to the visible part of the recording first)
        let target = sr.applying(M)
        var screen = screen
        if let full = screen, !model.crop.isFull, full.extent.width > 0 {
            let c = model.crop, e = full.extent
            let r = CGRect(x: e.minX + c.x * e.width, y: e.minY + (1 - c.y - c.h) * e.height,
                           width: c.w * e.width, height: c.h * e.height).integral
            screen = full.cropped(to: r).transformed(by: CGAffineTransform(translationX: -r.minX, y: -r.minY))
        }
        if let screen, screen.extent.width > 0 {
            let kx = target.width / screen.extent.width
            let ky = target.height / screen.extent.height
            var img: CIImage
            // One high-quality filter at every scale, so sharpness doesn't jump partway through a zoom.
            img = screen.applyingFilter("CILanczosScaleTransform", parameters: [
                kCIInputScaleKey: ky, kCIInputAspectRatioKey: kx / ky,
            ])
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

            if style.inset {
                // A thin border inside the screen, like a bezel.
                let w = max(1, CGFloat(style.insetSize) * L.unit * s)
                let r = CGFloat(style.cornerRadius) * L.unit * s
                let c = style.insetColor
                let ring = roundedRect(target, radius: r,
                                       color: CIColor(red: c.r, green: c.g, blue: c.b, alpha: CGFloat(style.insetOpacity)))
                    .applyingFilter("CISourceOutCompositing", parameters: [
                        kCIInputBackgroundImageKey: roundedRect(target.insetBy(dx: w, dy: w), radius: max(0, r - w)),
                    ])
                out = ring.composited(over: out)
            }
        }

        // Cinematic motion blur while the camera zooms or pans.
        if style.motionBlur > 0.01 {
            out = cameraMotionBlur(out, model: model, t: t, cam: cam, sr: sr, size: size, unit: L.unit, s: s, ox: ox, oy: oy)
        }

        // Blur and spotlight areas live on the recording, so they follow the zoom.
        let active = model.activeEffects(at: t)
        func regionRect(_ full: CGRect) -> CGRect {
            let r = model.crop.toCrop(full) // areas are drawn on the full frame
            return CGRect(x: sr.minX + r.minX * sr.width, y: sr.maxY - r.maxY * sr.height,
                   width: r.width * sr.width, height: r.height * sr.height).applying(M)
        }
        for (e, a) in active where e.kind == .blur {
            let r = regionRect(e.region).intersection(target)
            if r.width > 1, r.height > 1 { out = blurRegion(out, rect: r, effect: e, alpha: a, unit: L.unit * s) }
        }
        for (e, a) in active where e.kind == .spotlight {
            out = spotlight(out, hole: regionRect(e.region), dim: e.intensity * a, canvas: CGRect(origin: .zero, size: size), unit: L.unit * s)
        }
        // Arrows and shapes point at things in the recording, so they follow the zoom too.
        for (e, a) in active where e.kind == .annotation {
            out = annotation(e, in: regionRect(e.region), alpha: a, unit: L.unit * s).composited(over: out)
        }

        // Cursor + clicks
        let cursorVisibility = 1 - model.amount(of: .hideCursor, at: t)
        if style.showCursor, cursorVisibility > 0.001, let cp = model.cursor, cp.hasData {
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
                    let alpha = CGFloat((1 - p) * cursorVisibility)
                    out = clickEffect(style.clickEffect, at: pos, radius: r, alpha: alpha, unit: L.unit * s).composited(over: out)
                }
            }

            var st = cp.state(at: t)
            st.opacity *= cursorVisibility
            if st.opacity > 0.01 {
                let (art, info) = model.cursorArt(at: t)
                let pxPerPt = ptScale * s * cursorScale * model.pressScale(at: t)
                let pos = canvasPoint(st.position)
                let k = pxPerPt * CGFloat(info.width) / max(art.extent.width, 1)
                var img = art.transformed(by: CGAffineTransform(scaleX: k, y: k))
                // Put the hotspot at the origin, rotate around it, then move it to the cursor position.
                let hx = CGFloat(info.hotX) * pxPerPt
                let hy = CGFloat(info.height - info.hotY) * pxPerPt
                img = img.transformed(by: CGAffineTransform(translationX: -img.extent.minX - hx, y: -img.extent.minY - hy))
                let angle = cursorAngle(style: style, velocity: st.velocity)
                if abs(angle) > 0.001 { img = img.transformed(by: CGAffineTransform(rotationAngle: angle)) }
                img = img.transformed(by: CGAffineTransform(translationX: pos.x, y: pos.y))

                if style.cursorMotionBlur {
                    // pixels per frame at 60 fps
                    let vx = st.velocity.dx * sr.width * s / 60
                    let vy = -st.velocity.dy * sr.height * s / 60
                    let speed = hypot(vx, vy)
                    // Only a fast flick leaves a short, faint trail; ordinary movement stays crisp.
                    if speed / s > 25 * L.unit {
                        let len = min(speed * 0.5, 30 * L.unit)
                        let dx = vx / speed * len, dy = vy / speed * len
                        var ghosts = CIImage.empty()
                        let n = 4
                        for i in stride(from: n, through: 1, by: -1) {
                            let f = CGFloat(i) / CGFloat(n)
                            let g = withAlpha(img, 0.15 * (1 - f) + 0.03)
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

        // Image overlays sit on the canvas, like titles.
        for (e, a) in active where e.kind == .image {
            if let img = model.overlayImages[e.imageFile] {
                out = imageOverlay(img, effect: e, alpha: a, size: size, unit: L.unit).composited(over: out)
            }
        }

        // Titles sit on the canvas, unaffected by the zoom.
        for (e, a) in active where e.kind == .text && !e.text.isEmpty {
            out = titleCard(e, alpha: a, size: size, unit: L.unit, backdrop: out).composited(over: out)
        }

        // Webcam (not affected by the camera zoom)
        if style.camera.visible, let camera, camera.extent.width > 0 {
            let full = model.amount(of: .cameraFull, at: t)
            let hidden = model.amount(of: .cameraHidden, at: t)
            if hidden < 0.999 {
                out = webcamOverlay(camera, style: style.camera, size: size, unit: L.unit, zoom: s,
                                    full: full, hidden: hidden, move: model.cameraMove(at: t)).composited(over: out)
            }
        }

        // Captions, then keystrokes just above them.
        let minDim = min(size.width, size.height)
        var bottom = minDim * 0.045
        if let cue = model.caption(at: t) {
            let img = text.image(cue.text, kind: .caption, fontSize: 34 * L.unit * CGFloat(style.captionSize), maxWidth: size.width * 0.78)
            out = img.transformed(by: CGAffineTransform(translationX: (size.width - img.extent.width) / 2, y: bottom)).composited(over: out)
            bottom += img.extent.height + 12 * L.unit
        }
        if let (label, alpha) = model.keystroke(at: t) {
            var img = text.image(label, kind: .keycap, fontSize: 30 * L.unit * CGFloat(style.keystrokeSize), maxWidth: size.width * 0.7)
            img = img.transformed(by: CGAffineTransform(translationX: (size.width - img.extent.width) / 2, y: bottom))
            if alpha < 0.999 { img = withAlpha(img, CGFloat(alpha)) }
            out = img.composited(over: out)
        }

        return out.cropped(to: CGRect(origin: .zero, size: size))
    }

    // MARK: Motion

    /// Cursor rotation in radians (Core Image: counter-clockwise is positive).
    private func cursorAngle(style: Style, velocity v: CGVector) -> CGFloat {
        var deg = style.cursorAngle
        switch style.cursorRotation {
        case .off: break
        case .tilt:
            // Lean into fast horizontal movement (right = clockwise), upright at rest.
            deg -= clamp(Double(v.dx) * 60 * style.cursorTiltAmount, -35, 35)
        case .follow:
            // Point the arrow tip along the direction of travel once moving quickly enough.
            let speed = Double(hypot(v.dx, v.dy))
            if speed > 0.3 {
                var turn = atan2(Double(-v.dy), Double(v.dx)) * 180 / .pi - 135 // the tip points up-left at rest
                while turn > 180 { turn -= 360 }
                while turn < -180 { turn += 360 }
                deg += turn * min(1, (speed - 0.3) / 0.7)
            }
        }
        return CGFloat(deg * .pi / 180)
    }

    /// Blurs the frame along the camera's movement: directional blur for pans, zoom blur for zooms.
    private func cameraMotionBlur(_ image: CIImage, model: RenderModel, t: Double, cam: CameraPath.State,
                                  sr: CGRect, size: CGSize, unit: CGFloat, s: CGFloat, ox: CGFloat, oy: CGFloat) -> CIImage {
        let amount = CGFloat(model.style.motionBlur)
        let canvas = CGRect(origin: .zero, size: size)
        var out = image
        // Velocity from a frame either side (symmetric), so the blur changes smoothly from frame to frame
        // instead of flickering. Measured on the clamped view: what the viewer actually sees move.
        let h = 1.0 / 60
        let a = viewTransform(model: model, sourceTime: max(0, t - h), size: size)
        let b = viewTransform(model: model, sourceTime: t + h, size: size)
        guard s > 1.01 || a.scale > 1.01 || b.scale > 1.01 else { return image }
        let dx = (a.origin.x - b.origin.x) / 2 * s
        let dy = (a.origin.y - b.origin.y) / 2 * s
        // Every moving frame gets a blur in proportion to its speed, fading out as the camera slows
        // (as in Screen Studio), with no hard on/off threshold.
        let pan = min(max(0, hypot(dx, dy) * amount * 0.6 - 0.5 * unit), 24 * unit)
        if pan > 0.3 {
            out = out.clampedToExtent().applyingFilter("CIMotionBlur", parameters: [
                kCIInputRadiusKey: pan, kCIInputAngleKey: atan2(dy, dx),
            ]).cropped(to: canvas)
        }
        let zoomRate = abs(b.scale - a.scale) / 2 / max(s, 1)
        let zoom = min(max(0, zoomRate * amount * 110 * unit - 0.3 * unit), 16 * unit)
        if zoom > 0.3 {
            let fx = (sr.minX + cam.focus.x * sr.width - ox) * s
            let fy = (sr.maxY - cam.focus.y * sr.height - oy) * s
            out = out.clampedToExtent().applyingFilter("CIZoomBlur", parameters: [
                kCIInputCenterKey: CIVector(x: fx, y: fy), "inputAmount": zoom,
            ]).cropped(to: canvas)
        }
        return out
    }

    // MARK: Effects

    private func blurRegion(_ base: CIImage, rect: CGRect, effect e: EffectSegment, alpha: Double, unit: CGFloat) -> CIImage {
        let source = base.clampedToExtent()
        var img: CIImage
        if e.pixelate {
            img = source.applyingFilter("CIPixellate", parameters: [
                kCIInputScaleKey: max(4, (8 + 40 * e.intensity) * unit),
                kCIInputCenterKey: CIVector(x: rect.minX, y: rect.minY),
            ])
        } else {
            img = source.applyingGaussianBlur(sigma: Double((4 + 40 * e.intensity) * unit))
        }
        img = img.cropped(to: rect).applyingFilter("CISourceInCompositing", parameters: [
            kCIInputBackgroundImageKey: roundedRect(rect, radius: 8 * unit),
        ])
        if alpha < 0.999 { img = withAlpha(img, CGFloat(alpha)) }
        return img.composited(over: base)
    }

    /// An arrow, box or circle in `rect` (Core Image coordinates), drawn with Core Graphics.
    private func annotation(_ e: EffectSegment, in rect: CGRect, alpha: Double, unit: CGFloat) -> CIImage {
        let lw = max(1.5, CGFloat(e.strokeWidth) * unit)
        let pad = lw * 4
        let box = rect.insetBy(dx: -pad, dy: -pad).integral
        let w = Int(box.width), h = Int(box.height)
        guard w > 2, h > 2, w < 16384, h < 16384,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return .empty() }
        let c = e.strokeColor
        let color = CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: CGFloat(alpha))
        ctx.setStrokeColor(color)
        ctx.setFillColor(color)
        ctx.setLineWidth(lw)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        // A soft shadow keeps it visible on any background.
        ctx.setShadow(offset: CGSize(width: 0, height: -lw * 0.4), blur: lw * 1.2, color: CGColor(gray: 0, alpha: 0.35 * CGFloat(alpha)))
        let r = CGRect(x: rect.minX - box.minX, y: rect.minY - box.minY, width: rect.width, height: rect.height)
        switch e.shape {
        case .box:
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: lw * 1.5, cornerHeight: lw * 1.5, transform: nil))
            ctx.strokePath()
        case .ellipse:
            ctx.strokeEllipse(in: r)
        case .arrow:
            let (a, b) = e.arrowDirection.points // top-left unit square; Core Graphics is bottom-left
            let tail = CGPoint(x: r.minX + a.x * r.width, y: r.maxY - a.y * r.height)
            let tip = CGPoint(x: r.minX + b.x * r.width, y: r.maxY - b.y * r.height)
            let angle = atan2(tip.y - tail.y, tip.x - tail.x)
            let head = lw * 3.6
            let base = CGPoint(x: tip.x - cos(angle) * head * 0.8, y: tip.y - sin(angle) * head * 0.8)
            ctx.move(to: tail)
            ctx.addLine(to: base)
            ctx.strokePath()
            ctx.move(to: tip)
            ctx.addLine(to: CGPoint(x: tip.x - cos(angle - 0.45) * head, y: tip.y - sin(angle - 0.45) * head))
            ctx.addLine(to: CGPoint(x: tip.x - cos(angle + 0.45) * head, y: tip.y - sin(angle + 0.45) * head))
            ctx.closePath()
            ctx.fillPath()
        }
        guard let cg = ctx.makeImage() else { return .empty() }
        return CIImage(cgImage: cg).transformed(by: CGAffineTransform(translationX: box.minX, y: box.minY))
    }

    /// An image placed on the canvas: centred on textX/textY (top-left), with rounded corners and a shadow.
    private func imageOverlay(_ source: CIImage, effect e: EffectSegment, alpha: Double, size: CGSize, unit: CGFloat) -> CIImage {
        let ext = source.extent
        guard ext.width > 0, ext.height > 0 else { return .empty() }
        let w = CGFloat(e.imageWidth) * size.width
        let k = w / ext.width
        let h = ext.height * k
        let x = CGFloat(e.textX) * size.width - w / 2
        let y = (1 - CGFloat(e.textY)) * size.height - h / 2 - CGFloat(1 - alpha) * 16 * unit
        let rect = CGRect(x: x, y: y, width: w, height: h)
        var img = source.transformed(by: CGAffineTransform(translationX: -ext.minX, y: -ext.minY))
            .transformed(by: CGAffineTransform(scaleX: k, y: k))
            .transformed(by: CGAffineTransform(translationX: x, y: y))
        let radius = CGFloat(e.imageCorner) * unit
        if radius > 0.5 {
            img = img.applyingFilter("CISourceInCompositing", parameters: [kCIInputBackgroundImageKey: roundedRect(rect, radius: radius)])
        }
        if e.imageShadow {
            let shadow = roundedRect(rect.offsetBy(dx: 0, dy: -8 * unit), radius: radius, color: CIColor(red: 0, green: 0, blue: 0, alpha: 0.35))
                .applyingGaussianBlur(sigma: Double(18 * unit))
            img = img.composited(over: shadow)
        }
        return withAlpha(img, CGFloat(alpha))
    }

    private func spotlight(_ base: CIImage, hole: CGRect, dim: Double, canvas: CGRect, unit: CGFloat) -> CIImage {
        let shade = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: CGFloat(min(0.92, dim)))).cropped(to: canvas)
        let shaded = shade.composited(over: base)
        // White inside the hole keeps the original; black elsewhere shows the shaded frame.
        let mask = roundedRect(hole, radius: 12 * unit)
            .composited(over: CIImage(color: .black).cropped(to: canvas))
            .applyingGaussianBlur(sigma: Double(5 * unit))
            .cropped(to: canvas)
        return base.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: shaded, kCIInputMaskImageKey: mask,
        ]).cropped(to: canvas)
    }

    private func titleCard(_ e: EffectSegment, alpha: Double, size: CGSize, unit: CGFloat, backdrop: CIImage) -> CIImage {
        let style = e.titleStyle
        let title = text.title(e.text, subtitle: e.subtitle, style: style, fontSize: 58 * unit * CGFloat(e.textSize), maxWidth: size.width * 0.82)
        let img = title.image
        let w = img.extent.width, h = img.extent.height
        let margin = min(size.width, size.height) * 0.08
        var y: CGFloat
        var x: CGFloat
        switch style.align {
        case .left: x = margin
        case .center: x = (size.width - w) / 2
        case .right: x = size.width - margin - w
        }
        switch e.placement {
        case .top: y = size.height - margin - h
        case .center: y = (size.height - h) / 2
        case .bottom: y = margin
        case .custom:
            // Dragged on the preview: textX/textY are the card's centre (top-left normalised), kept on the canvas.
            x = min(max(0, CGFloat(e.textX) * size.width - w / 2), size.width - w)
            y = min(max(0, (1 - CGFloat(e.textY)) * size.height - h / 2), size.height - h)
        }
        y -= CGFloat(1 - alpha) * 24 * unit
        var card = img.transformed(by: CGAffineTransform(translationX: x, y: y))
        if style.card == .none { return withAlpha(card, CGFloat(alpha)) }
        if style.card == .glass {
            // Frosted glass: the video behind the card, blurred and a little more vivid.
            let rect = card.extent
            let frosted = backdrop.clampedToExtent()
                .applyingGaussianBlur(sigma: Double(28 * unit))
                .applyingFilter("CIColorControls", parameters: ["inputSaturation": 1.3, "inputBrightness": -0.02])
                .cropped(to: rect)
            let glass = frosted.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: CIImage.empty(), kCIInputMaskImageKey: roundedRect(rect, radius: title.radius),
            ])
            card = card.composited(over: glass)
        }
        let shadow = roundedRect(card.extent.offsetBy(dx: 0, dy: -10 * unit), radius: title.radius,
                                 color: CIColor(red: 0, green: 0, blue: 0, alpha: style.card == .glass ? 0.22 : 0.35))
            .applyingGaussianBlur(sigma: Double(22 * unit))
        return withAlpha(card.composited(over: shadow), CGFloat(alpha))
    }

    /// Where the camera is: screen rect, zoom scale and the canvas transform (Core Image coordinates).
    struct ViewTransform {
        let screenRect: CGRect
        let cam: CameraPath.State
        let scale: CGFloat
        let origin: CGPoint
        let transform: CGAffineTransform

        /// A full-frame normalised (top-left) rect of the recording → a rect in top-left view coordinates.
        func viewRect(fullFrame r: CGRect, crop: CropRect, canvasHeight h: CGFloat) -> CGRect {
            let c = crop.toCrop(r)
            let sr = screenRect
            let ci = CGRect(x: sr.minX + c.minX * sr.width, y: sr.maxY - c.maxY * sr.height,
                            width: c.width * sr.width, height: c.height * sr.height).applying(transform)
            return CGRect(x: ci.minX, y: h - ci.maxY, width: ci.width, height: ci.height)
        }

        /// The inverse: a top-left view point → full-frame normalised point.
        func fullFramePoint(view p: CGPoint, crop: CropRect, canvasHeight h: CGFloat) -> CGPoint {
            let ci = CGPoint(x: p.x, y: h - p.y).applying(transform.inverted())
            let sr = screenRect
            let cx = (ci.x - sr.minX) / max(sr.width, 1), cy = (sr.maxY - ci.y) / max(sr.height, 1)
            return CGPoint(x: crop.x + cx * crop.w, y: crop.y + cy * crop.h)
        }
    }

    func viewTransform(model: RenderModel, sourceTime t: Double, size: CGSize) -> ViewTransform {
        let sr = model.layout(for: size).screenRect
        let cam = model.camera.state(at: t)
        let s = CGFloat(max(1, cam.scale))
        let focus = CGPoint(x: sr.minX + cam.focus.x * sr.width, y: sr.maxY - cam.focus.y * sr.height)
        let vw = size.width / s, vh = size.height / s
        let cx = clampAxis(focus.x, view: vw, lo: sr.minX, hi: sr.maxX, total: size.width)
        let cy = clampAxis(focus.y, view: vh, lo: sr.minY, hi: sr.maxY, total: size.height)
        let ox = cx - vw / 2, oy = cy - vh / 2
        return ViewTransform(screenRect: sr, cam: cam, scale: s, origin: CGPoint(x: ox, y: oy),
                             transform: CGAffineTransform(a: s, b: 0, c: 0, d: s, tx: -ox * s, ty: -oy * s))
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

    private func webcamOverlay(_ source: CIImage, style cs: CameraStyle, size: CGSize, unit: CGFloat, zoom: CGFloat,
                               full: Double, hidden: Double, move: (EffectSegment, Double)? = nil) -> CIImage {
        var cam = source
        let removeBackground = cs.background == .remove
        if cs.background != .none, let mask = segmenter.mask(for: cam) {
            let bg: CIImage = cs.background == .blur
                ? cam.clampedToExtent().applyingGaussianBlur(sigma: Double(cam.extent.width / 70)).cropped(to: cam.extent)
                : CIImage.empty()
            cam = cam.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: bg, kCIInputMaskImageKey: mask,
            ]).cropped(to: source.extent)
        }

        // Bubble geometry, then blend towards the full canvas for "camera full screen".
        let minDim = min(size.width, size.height)
        var d = CGFloat(cs.size) * minDim
        if cs.shrinkOnZoom {
            d *= CGFloat(lerp(1, 0.7, Double(min(1, max(0, zoom - 1))) * (1 - full)))
        }
        let margin = 0.04 * minDim
        func bubbleRect(_ corner: CameraCorner, _ d: CGFloat) -> CGRect {
            let bx: CGFloat, by: CGFloat
            switch corner {
            case .topLeft: bx = margin; by = size.height - margin - d
            case .topRight: bx = size.width - margin - d; by = size.height - margin - d
            case .bottomLeft: bx = margin; by = margin
            case .bottomRight: bx = size.width - margin - d; by = margin
            }
            return CGRect(x: bx, y: by, width: d, height: d)
        }
        var bubble = bubbleRect(cs.corner, d)
        if let (e, a) = move {
            // Glide to the other corner and size, and back when the effect ends.
            let to = bubbleRect(e.cameraCorner, CGFloat(e.cameraSize) * minDim)
            let k = CGFloat(a)
            bubble = CGRect(x: bubble.minX + (to.minX - bubble.minX) * k, y: bubble.minY + (to.minY - bubble.minY) * k,
                            width: bubble.width + (to.width - bubble.width) * k, height: bubble.height + (to.height - bubble.height) * k)
        }
        let f = CGFloat(full)
        var rect = CGRect(x: bubble.minX * (1 - f), y: bubble.minY * (1 - f),
                          width: bubble.width + (size.width - bubble.width) * f,
                          height: bubble.height + (size.height - bubble.height) * f)
        if hidden > 0 {
            let k = 1 - 0.25 * CGFloat(hidden)
            rect = CGRect(x: rect.midX - rect.width * k / 2, y: rect.midY - rect.height * k / 2,
                          width: rect.width * k, height: rect.height * k)
        }

        // Fill the target rect with the camera image (aspect fill), mirrored if needed.
        let e = cam.extent.width > 0 ? cam.extent : source.extent
        let crop = e.aspectFit(aspect: rect.width / max(rect.height, 1))
        var img = cam.cropped(to: crop)
        img = img.transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
        if cs.mirror {
            img = img.transformed(by: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: crop.width, ty: 0))
        }
        let k = rect.width / max(crop.width, 1)
        img = img.transformed(by: CGAffineTransform(scaleX: k, y: k))
            .transformed(by: CGAffineTransform(translationX: rect.minX, y: rect.minY))

        let shapeRadius: CGFloat
        switch cs.shape {
        case .circle: shapeRadius = rect.width / 2
        case .rounded: shapeRadius = rect.width * 0.18
        case .square: shapeRadius = 0
        }
        // A cut-out person isn't clipped to the bubble shape, so their head and shoulders stay whole.
        let radius = removeBackground ? 0 : shapeRadius * (1 - f)
        img = radius > 0.5
            ? img.applyingFilter("CISourceInCompositing", parameters: [kCIInputBackgroundImageKey: roundedRect(rect, radius: radius)])
            : img.cropped(to: rect)

        var result = img
        let chrome = 1 - f
        if removeBackground {
            let silhouette = img.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.45),
            ])
            result = img.composited(over: silhouette.applyingGaussianBlur(sigma: Double(10 * unit))
                .transformed(by: CGAffineTransform(translationX: 0, y: -6 * unit)))
        } else if chrome > 0.01 {
            if cs.border {
                let bw = 3 * unit
                let border = roundedRect(rect.insetBy(dx: -bw, dy: -bw), radius: radius > 0 ? radius + bw : 0,
                                         color: CIColor(red: 1, green: 1, blue: 1, alpha: 0.9 * chrome))
                result = result.composited(over: border)
            }
            let shadowRect = rect.insetBy(dx: -2 * unit, dy: -2 * unit).offsetBy(dx: 0, dy: -8 * unit)
            let shadow = roundedRect(shadowRect, radius: radius > 0 ? radius : 0, color: CIColor(red: 0, green: 0, blue: 0, alpha: 0.45 * chrome))
                .applyingGaussianBlur(sigma: Double(14 * unit))
            result = result.composited(over: shadow)
        }
        if hidden > 0.001 { result = withAlpha(result, CGFloat(1 - hidden)) }
        return result
    }
}
