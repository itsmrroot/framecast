import SwiftUI
import AppKit

/// Crops the recording: drag the box or its 8 handles on a frame of the video.
struct CropSheet: View {
    @ObservedObject var model: EditorModel
    @Binding var isPresented: Bool
    @State private var rect = CGRect(x: 0, y: 0, width: 1, height: 1)
    @State private var aspect: CropAspect = .free
    @State private var frame: CGImage?

    private var pixelSize: CGSize { CGSize(width: model.doc.info.pixelWidth, height: model.doc.info.pixelHeight) }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Label("Crop", systemImage: "crop").font(.system(size: 15, weight: .semibold))
                Spacer()
                Picker("Aspect", selection: $aspect) {
                    ForEach(CropAspect.allCases) { a in Text(a.label).tag(a) }
                }
                .frame(width: 170)
                .onChange(of: aspect) { _, a in rect = a.fit(rect, frame: pixelSize) }
                Text(String(format: "%d × %d px", Int(rect.width * pixelSize.width), Int(rect.height * pixelSize.height)))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(Theme.textDim)
                    .frame(width: 120, alignment: .trailing)
                Button("Reset") { rect = CGRect(x: 0, y: 0, width: 1, height: 1); aspect = .free }
                    .buttonStyle(SecondaryButtonStyle())
            }
            RectEditor(rect: $rect, ratio: aspect.ratio(frame: pixelSize), image: frame,
                       imageAspect: pixelSize.width / max(pixelSize.height, 1))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                Text("Trim off the menu bar, Dock or browser chrome. The cursor, zooms and effects follow the crop.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.textDim)
                Spacer()
                Button("Discard") { isPresented = false }
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("Confirm") {
                    let full = rect.minX < 0.001 && rect.minY < 0.001 && rect.width > 0.999 && rect.height > 0.999
                    model.edit(.render) {
                        $0.style.crop = full ? nil : CropRect(x: rect.minX, y: rect.minY, w: rect.width, h: rect.height)
                    }
                    isPresented = false
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 880, height: 640)
        .background(Theme.panel)
        .task {
            if let c = model.doc.style.crop { rect = c.rect }
            frame = await model.rawFrame(at: model.sourceTime, maxSize: 1400)
        }
    }
}

enum CropAspect: String, CaseIterable, Identifiable {
    case free, original, wide, classic, square, vertical, portrait
    var id: String { rawValue }
    var label: String {
        switch self {
        case .free: return "Any aspect"
        case .original: return "Original"
        case .wide: return "16:9"
        case .classic: return "4:3"
        case .square: return "1:1"
        case .vertical: return "9:16"
        case .portrait: return "4:5"
        }
    }

    /// Width / height of the crop in normalised units (accounts for the frame's own aspect).
    func ratio(frame: CGSize) -> CGFloat? {
        let fa = frame.width / max(frame.height, 1)
        let pixel: CGFloat
        switch self {
        case .free: return nil
        case .original: return 1
        case .wide: pixel = 16.0 / 9.0
        case .classic: pixel = 4.0 / 3.0
        case .square: pixel = 1
        case .vertical: pixel = 9.0 / 16.0
        case .portrait: pixel = 4.0 / 5.0
        }
        return pixel / fa
    }

    /// The largest rect with this aspect centred on the current one.
    func fit(_ r: CGRect, frame: CGSize) -> CGRect {
        guard let ratio = ratio(frame: frame) else { return r }
        var w = r.width, h = r.height
        if w / h > ratio { w = h * ratio } else { h = w / ratio }
        let maxW = min(1, ratio), maxH = min(1, 1 / ratio)
        if w > maxW || h > maxH { w = maxW; h = maxH }
        let x = clamp(r.midX - w / 2, 0, 1 - w), y = clamp(r.midY - h / 2, 0, 1 - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }
}

/// An image with an editable normalised rectangle: drag inside to move, drag a handle to resize.
struct RectEditor: View {
    @Binding var rect: CGRect
    /// Locked width/height in normalised units, or nil for any shape.
    let ratio: CGFloat?
    let image: CGImage?
    let imageAspect: CGFloat
    @State private var dragStart: (handle: Handle, rect: CGRect)?

    enum Handle { case move, n, s, e, w, ne, nw, se, sw }

    var body: some View {
        GeometryReader { geo in
            let box = CGRect(origin: .zero, size: geo.size).aspectFit(aspect: imageAspect)
            let r = CGRect(x: box.minX + rect.minX * box.width, y: box.minY + rect.minY * box.height,
                           width: rect.width * box.width, height: rect.height * box.height)
            ZStack(alignment: .topLeading) {
                Group {
                    if let image { Image(decorative: image, scale: 1).resizable() } else { Rectangle().fill(Theme.fill.opacity(0.06)) }
                }
                .frame(width: box.width, height: box.height)
                .offset(x: box.minX, y: box.minY)
                // Dim outside the crop.
                Path { p in
                    p.addRect(box)
                    p.addRect(r)
                }
                .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
                // Border and thirds grid.
                Path { p in
                    for i in 1...2 {
                        let fx = r.minX + r.width * CGFloat(i) / 3, fy = r.minY + r.height * CGFloat(i) / 3
                        p.move(to: CGPoint(x: fx, y: r.minY)); p.addLine(to: CGPoint(x: fx, y: r.maxY))
                        p.move(to: CGPoint(x: r.minX, y: fy)); p.addLine(to: CGPoint(x: r.maxX, y: fy))
                    }
                }
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
                Rectangle().strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])).foregroundStyle(.white)
                    .frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)
                ForEach(handlePoints(r), id: \.0) { _, p in
                    Circle().fill(.white).frame(width: 12, height: 12)
                        .shadow(color: .black.opacity(0.4), radius: 2)
                        .position(p)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 1)
                .onChanged { v in
                    if dragStart == nil { dragStart = (hit(v.startLocation, r), rect) }
                    guard let (handle, r0) = dragStart else { return }
                    rect = adjust(r0, handle: handle, dx: v.translation.width / box.width, dy: v.translation.height / box.height)
                }
                .onEnded { _ in dragStart = nil })
        }
    }

    private func handlePoints(_ r: CGRect) -> [(Int, CGPoint)] {
        [(0, CGPoint(x: r.minX, y: r.minY)), (1, CGPoint(x: r.midX, y: r.minY)), (2, CGPoint(x: r.maxX, y: r.minY)),
         (3, CGPoint(x: r.maxX, y: r.midY)), (4, CGPoint(x: r.maxX, y: r.maxY)), (5, CGPoint(x: r.midX, y: r.maxY)),
         (6, CGPoint(x: r.minX, y: r.maxY)), (7, CGPoint(x: r.minX, y: r.midY))]
    }

    private func hit(_ p: CGPoint, _ r: CGRect) -> Handle {
        let tol: CGFloat = 14
        let nearL = abs(p.x - r.minX) < tol, nearR = abs(p.x - r.maxX) < tol
        let nearT = abs(p.y - r.minY) < tol, nearB = abs(p.y - r.maxY) < tol
        let inX = p.x > r.minX - tol && p.x < r.maxX + tol, inY = p.y > r.minY - tol && p.y < r.maxY + tol
        switch (nearL, nearR, nearT, nearB) {
        case (true, _, true, _): return .nw
        case (_, true, true, _): return .ne
        case (true, _, _, true): return .sw
        case (_, true, _, true): return .se
        case (true, _, _, _) where inY: return .w
        case (_, true, _, _) where inY: return .e
        case (_, _, true, _) where inX: return .n
        case (_, _, _, true) where inX: return .s
        default: return .move
        }
    }

    private func adjust(_ r0: CGRect, handle: Handle, dx: CGFloat, dy: CGFloat) -> CGRect {
        let minSize: CGFloat = 0.05
        if handle == .move {
            return CGRect(x: clamp(r0.minX + dx, 0, 1 - r0.width), y: clamp(r0.minY + dy, 0, 1 - r0.height),
                          width: r0.width, height: r0.height)
        }
        var minX = r0.minX, minY = r0.minY, maxX = r0.maxX, maxY = r0.maxY
        switch handle {
        case .w, .nw, .sw: minX = clamp(r0.minX + dx, 0, maxX - minSize)
        case .e, .ne, .se: maxX = clamp(r0.maxX + dx, minX + minSize, 1)
        default: break
        }
        switch handle {
        case .n, .nw, .ne: minY = clamp(r0.minY + dy, 0, maxY - minSize)
        case .s, .sw, .se: maxY = clamp(r0.maxY + dy, minY + minSize, 1)
        default: break
        }
        var r = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        if let ratio {
            // Keep the locked aspect, anchored on the opposite edge or corner.
            let byWidth = [.e, .w, .ne, .nw, .se, .sw].contains(handle)
            var w = r.width, h = r.height
            if byWidth { h = w / ratio } else { w = h * ratio }
            if h > 1 { h = 1; w = h * ratio }
            if w > 1 { w = 1; h = w / ratio }
            let x = [.w, .nw, .sw].contains(handle) ? r.maxX - w : ([.n, .s].contains(handle) ? r.midX - w / 2 : r.minX)
            let y = [.n, .nw, .ne].contains(handle) ? r.maxY - h : ([.e, .w].contains(handle) ? r.midY - h / 2 : r.minY)
            r = CGRect(x: clamp(x, 0, 1 - w), y: clamp(y, 0, 1 - h), width: w, height: h)
        }
        return r
    }
}
