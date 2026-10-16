import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum InspectorTab: String, CaseIterable, Identifiable {
    case background, cursor, zoom, camera, audio
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .background: return "photo.on.rectangle"
        case .cursor: return "cursorarrow"
        case .zoom: return "plus.magnifyingglass"
        case .camera: return "video"
        case .audio: return "speaker.wave.2"
        }
    }
}

struct InspectorView: View {
    @ObservedObject var model: EditorModel
    @ObservedObject var ui: EditorUIState

    var body: some View {
        VStack(spacing: 0) {
            if let z = model.selectedZoom {
                ZoomDetail(model: model, zoom: z)
            } else if let c = model.selectedClip {
                ClipDetail(model: model, clip: c)
            } else {
                tabBar
                Rectangle().fill(Theme.border).frame(height: 1)
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        switch ui.inspectorTab {
                        case .background: BackgroundTab(model: model)
                        case .cursor: CursorTab(model: model)
                        case .zoom: ZoomTab(model: model)
                        case .camera: CameraTab(model: model)
                        case .audio: AudioTab(model: model)
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(InspectorTab.allCases) { tab in
                Button {
                    ui.inspectorTab = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon).font(.system(size: 14))
                        Text(tab.label).font(.system(size: 10, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .foregroundStyle(ui.inspectorTab == tab ? Theme.text : Theme.textDim)
                    .background(RoundedRectangle(cornerRadius: 7).fill(ui.inspectorTab == tab ? Color.white.opacity(0.1) : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
    }
}

// MARK: - Background

private struct BackgroundTab: View {
    @ObservedObject var model: EditorModel

    private var bg: BackgroundStyle { model.doc.style.background }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Background")
            PillPicker(options: BackgroundKind.allCases,
                       selection: Binding(get: { bg.kind }, set: { k in model.edit(.render) { $0.style.background.kind = k } }),
                       label: \.label)
            switch bg.kind {
            case .wallpaper: wallpapers
            case .gradient: gradients
            case .solid: solids
            case .image: customImage
            }
            if bg.kind == .wallpaper || bg.kind == .image {
                LabeledSlider(label: "Blur", value: model.styleBinding(\.background.blur, key: "blur"), range: 0...40)
            }
        }

        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Frame")
            LabeledSlider(label: "Padding", value: model.styleBinding(\.padding, key: "padding"), range: 0...0.25,
                          format: { "\(Int($0 * 400))%" })
            LabeledSlider(label: "Rounded corners", value: model.styleBinding(\.cornerRadius, key: "corner"), range: 0...60)
            LabeledSlider(label: "Shadow", value: model.styleBinding(\.shadow, key: "shadow"), range: 0...1,
                          format: { "\(Int($0 * 100))%" })
            LabeledSlider(label: "Shadow softness", value: model.styleBinding(\.shadowBlur, key: "shadowBlur"), range: 4...120)
        }

        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Aspect ratio")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(AspectRatio.allCases) { a in
                    let selected = model.doc.style.aspect == a
                    Button {
                        model.edit(.render) { $0.style.aspect = a }
                    } label: {
                        Text(a.shortLabel)
                            .font(.system(size: 11.5, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Theme.accent.opacity(0.25) : Color.white.opacity(0.06)))
                            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(selected ? Theme.accent : .clear))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var wallpapers: some View {
        let current = bg.wallpaperPath ?? Backgrounds.defaultWallpaper()
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(Backgrounds.wallpapers, id: \.path) { url in
                WallpaperThumb(path: url.path, selected: current == url.path)
                    .onTapGesture {
                        model.edit(.render) { $0.style.background.wallpaperPath = url.path; $0.style.background.kind = .wallpaper }
                    }
                    .help(url.deletingPathExtension().lastPathComponent)
            }
        }
    }

    private var gradients: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            ForEach(Backgrounds.gradients.indices, id: \.self) { i in
                let g = Backgrounds.gradients[i]
                let selected = bg.gradientIndex == i
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient(colors: g.colors.map(\.color),
                                         startPoint: unitPoint(angle: g.angle + 180), endPoint: unitPoint(angle: g.angle)))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(selected ? Color.white : Theme.border, lineWidth: selected ? 2 : 1))
                    .onTapGesture { model.edit(.render) { $0.style.background.gradientIndex = i } }
                    .help(g.name)
            }
        }
    }

    private func unitPoint(angle: Double) -> UnitPoint {
        let a = angle * .pi / 180
        return UnitPoint(x: 0.5 + cos(a) / 2, y: 0.5 - sin(a) / 2)
    }

    private var solids: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                ForEach(Backgrounds.solidColors, id: \.self) { c in
                    Circle().fill(c.color)
                        .aspectRatio(1, contentMode: .fit)
                        .overlay(Circle().strokeBorder(bg.solid == c ? Color.white : Theme.border, lineWidth: bg.solid == c ? 2 : 1))
                        .onTapGesture { model.edit(.render) { $0.style.background.solid = c } }
                }
            }
            ColorPicker("Custom color", selection: Binding(get: { bg.solid.color }, set: { c in
                model.edit(.render, coalesce: "solid") { $0.style.background.solid = RGBA(c) }
            }), supportsOpacity: false)
            .font(.system(size: 12))
        }
    }

    private var customImage: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let path = bg.imagePath, let thumb = Backgrounds.thumbnail(path: path) {
                Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fill)
                    .frame(height: 120).frame(maxWidth: .infinity).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            Button {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.image]
                panel.message = "Choose a background image"
                if panel.runModal() == .OK, let url = panel.url {
                    model.edit(.render) { $0.style.background.imagePath = url.path }
                }
            } label: {
                Label(bg.imagePath == nil ? "Choose Image…" : "Change Image…", systemImage: "photo")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }
}

private struct WallpaperThumb: View {
    let path: String
    let selected: Bool
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Rectangle().fill(Color.white.opacity(0.05))
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            }
        }
        .aspectRatio(16.0 / 10.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(selected ? Color.white : Theme.border, lineWidth: selected ? 2 : 1))
        .contentShape(Rectangle())
        .task(id: path) {
            let p = path
            let img = await Task.detached(priority: .userInitiated) { Backgrounds.thumbnail(path: p) }.value
            image = img
        }
    }
}

// MARK: - Cursor

private struct CursorTab: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Cursor")
            if model.cursorTrack.isEmpty {
                Text("This video has no cursor data. Cursor effects are available for recordings made with Framecast.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.textDim)
            } else {
                ToggleRow(label: "Show cursor", isOn: model.styleBinding(\.showCursor, key: "showCursor"))
                LabeledSlider(label: "Size", value: model.styleBinding(\.cursorSize, key: "cursorSize"), range: 0.5...4,
                              format: { String(format: "%.1f×", $0) })
                LabeledSlider(label: "Smooth movement", value: model.styleBinding(\.cursorSmoothing, key: "smoothing"), range: 0...1,
                              format: { $0 < 0.02 ? "Off" : "\(Int($0 * 100))%" })
                ToggleRow(label: "High-resolution arrow", isOn: model.styleBinding(\.highResCursor, key: "hires"))
                ToggleRow(label: "Motion blur", isOn: model.styleBinding(\.cursorMotionBlur, key: "mblur"))
                ToggleRow(label: "Hide when idle", isOn: model.styleBinding(\.hideIdleCursor, key: "idle"))
            }
        }
        if !model.cursorTrack.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Click effect")
                PillPicker(options: ClickEffect.allCases,
                           selection: model.styleBinding(\.clickEffect, key: "click"), label: \.label)
                Text("\(model.cursorTrack.clicks.count) clicks recorded")
                    .font(.system(size: 11)).foregroundStyle(Theme.textFaint)
            }
        }
    }
}

// MARK: - Zoom

private struct ZoomTab: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Zoom")
            LabeledSlider(label: "Default zoom level", value: model.styleBinding(\.defaultZoomScale, key: "defZoom"), range: 1.2...4,
                          format: { String(format: "%.1f×", $0) })
            LabeledSlider(label: "Transition duration", value: model.styleBinding(\.zoomTransition, key: "zoomT"), range: 0.3...1.6,
                          format: { String(format: "%.1fs", $0) })
            Text("\(model.doc.zooms.count) zoom\(model.doc.zooms.count == 1 ? "" : "s") on the timeline. Click one to edit it, or click an empty spot in the zoom lane to add one.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Automatic zoom")
            Button {
                model.regenerateAutoZooms()
            } label: {
                Label("Generate zooms from clicks", systemImage: "wand.and.stars").frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(model.cursorTrack.clicks.isEmpty)
            Button {
                model.removeAllZooms()
            } label: {
                Label("Remove all zooms", systemImage: "trash").frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(model.doc.zooms.isEmpty)
        }
    }
}

private struct ZoomDetail: View {
    @ObservedObject var model: EditorModel
    let zoom: ZoomSegment

    var body: some View {
        VStack(spacing: 0) {
            DetailHeader(title: "Zoom", icon: "plus.magnifyingglass", color: Theme.zoom) { model.selection = .none }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LabeledSlider(label: "Zoom level",
                                  value: Binding(get: { zoom.scale }, set: { v in model.updateZoom(zoom.id, coalesce: "zs-\(zoom.id)") { $0.scale = v } }),
                                  range: 1.1...5, format: { String(format: "%.1f×", $0) })
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Focus").font(.system(size: 12))
                        PillPicker(options: ZoomMode.allCases,
                                   selection: Binding(get: { zoom.mode }, set: { m in model.updateZoom(zoom.id) { $0.mode = m } }),
                                   label: \.label)
                        if zoom.mode == .fixed {
                            FocusPicker(model: model, zoom: zoom)
                        } else {
                            Text("The camera smoothly follows your cursor while zoomed in.")
                                .font(.system(size: 11)).foregroundStyle(Theme.textDim)
                        }
                    }
                    HStack {
                        Text("Starts \(formatTime(zoom.start, fraction: true))")
                        Spacer()
                        Text("Lasts \(String(format: "%.1fs", zoom.duration))")
                    }
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Theme.textDim)
                    HStack {
                        Button { model.seek(source: zoom.start) } label: { Label("Go to zoom", systemImage: "arrow.right.to.line") }
                            .buttonStyle(SecondaryButtonStyle())
                        Spacer()
                        Button(role: .destructive) { model.deleteSelection() } label: { Label("Delete", systemImage: "trash") }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                }
                .padding(16)
            }
        }
    }
}

private struct FocusPicker: View {
    @ObservedObject var model: EditorModel
    let zoom: ZoomSegment
    @State private var frame: CGImage?

    var body: some View {
        let aspect = CGFloat(model.doc.info.pixelWidth) / CGFloat(max(1, model.doc.info.pixelHeight))
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                if let frame {
                    Image(decorative: frame, scale: 1).resizable()
                } else {
                    Rectangle().fill(Color.white.opacity(0.06))
                }
                // visible area at this zoom level
                let w = geo.size.width / zoom.scale, h = geo.size.height / zoom.scale
                let cx = clamp(zoom.focusX * geo.size.width, w / 2, geo.size.width - w / 2)
                let cy = clamp(zoom.focusY * geo.size.height, h / 2, geo.size.height - h / 2)
                Rectangle()
                    .strokeBorder(Color.white, lineWidth: 1.5)
                    .background(Color.white.opacity(0.08))
                    .frame(width: w, height: h)
                    .offset(x: cx - w / 2, y: cy - h / 2)
                Circle().fill(Theme.zoom).frame(width: 12, height: 12)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .offset(x: zoom.focusX * geo.size.width - 6, y: zoom.focusY * geo.size.height - 6)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                let x = clamp(Double(v.location.x / geo.size.width), 0, 1)
                let y = clamp(Double(v.location.y / geo.size.height), 0, 1)
                model.updateZoom(zoom.id, coalesce: "focus-\(zoom.id)") { $0.focusX = x; $0.focusY = y }
            })
        }
        .aspectRatio(aspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.border))
        .task(id: zoom.id) { frame = await model.rawFrame(at: zoom.start + min(1, zoom.duration / 2)) }
        Text("Drag to choose where the zoom points.")
            .font(.system(size: 11)).foregroundStyle(Theme.textDim)
    }
}

// MARK: - Clip

private struct ClipDetail: View {
    @ObservedObject var model: EditorModel
    let clip: Clip
    private let speeds: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 2, 3, 4, 8]

    var body: some View {
        VStack(spacing: 0) {
            DetailHeader(title: "Clip", icon: "film", color: Theme.clip) { model.selection = .none }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Speed").font(.system(size: 12))
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                            ForEach(speeds, id: \.self) { s in
                                let selected = abs(clip.speed - s) < 0.001
                                Button {
                                    model.setClip(clip.id, speed: s)
                                } label: {
                                    Text("\(s, specifier: "%g")×")
                                        .font(.system(size: 12, weight: .medium))
                                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                                        .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Theme.clip.opacity(0.3) : Color.white.opacity(0.06)))
                                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(selected ? Theme.clip : .clear))
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Text("Speed up typing or waiting, or slow down important moments.")
                            .font(.system(size: 11)).foregroundStyle(Theme.textDim)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        row("Source", "\(formatTime(clip.start, fraction: true)) – \(formatTime(clip.end, fraction: true))")
                        row("Length in video", String(format: "%.1fs", clip.duration / clip.speed))
                    }
                    HStack {
                        Button { model.splitAtPlayhead() } label: { Label("Split", systemImage: "scissors") }
                            .buttonStyle(SecondaryButtonStyle())
                        Spacer()
                        Button(role: .destructive) { model.deleteSelection() } label: { Label("Cut clip", systemImage: "trash") }
                            .buttonStyle(SecondaryButtonStyle())
                            .disabled(model.doc.clips.count < 2)
                    }
                }
                .padding(16)
            }
        }
    }

    private func row(_ a: String, _ b: String) -> some View {
        HStack {
            Text(a).foregroundStyle(Theme.textDim)
            Spacer()
            Text(b).monospacedDigit()
        }
        .font(.system(size: 11.5))
    }
}

private struct DetailHeader: View {
    let title: String
    let icon: String
    let color: Color
    let onClose: () -> Void

    var body: some View {
        HStack {
            Image(systemName: icon).foregroundStyle(color)
            Text(title).font(.system(size: 13, weight: .semibold))
            Spacer()
            IconButton(icon: "xmark", help: "Close (Esc)", action: onClose)
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }
}

// MARK: - Camera

private struct CameraTab: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Camera")
            if !model.doc.info.hasWebcam {
                Text("No camera was recorded. Turn on Camera before recording to add a webcam bubble.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.textDim)
            } else {
                ToggleRow(label: "Show camera", isOn: model.styleBinding(\.camera.visible, key: "camVis"))
                Text("Shape").font(.system(size: 12))
                PillPicker(options: CameraShape.allCases, selection: model.styleBinding(\.camera.shape, key: "camShape"), label: \.label)
                LabeledSlider(label: "Size", value: model.styleBinding(\.camera.size, key: "camSize"), range: 0.1...0.5,
                              format: { "\(Int($0 * 100))%" })
                Text("Position").font(.system(size: 12))
                positionGrid
                ToggleRow(label: "Mirror", isOn: model.styleBinding(\.camera.mirror, key: "camMirror"))
                ToggleRow(label: "Shrink while zoomed", isOn: model.styleBinding(\.camera.shrinkOnZoom, key: "camShrink"))
                ToggleRow(label: "Border", isOn: model.styleBinding(\.camera.border, key: "camBorder"))
            }
        }
    }

    private var positionGrid: some View {
        let corners: [[CameraCorner]] = [[.topLeft, .topRight], [.bottomLeft, .bottomRight]]
        return VStack(spacing: 6) {
            ForEach(0..<2, id: \.self) { r in
                HStack(spacing: 6) {
                    ForEach(corners[r]) { c in
                        let selected = model.doc.style.camera.corner == c
                        Button {
                            model.edit(.render) { $0.style.camera.corner = c }
                        } label: {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selected ? Theme.accent.opacity(0.3) : Color.white.opacity(0.06))
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(selected ? Theme.accent : .clear))
                                .overlay(alignment: alignment(c)) {
                                    Circle().fill(selected ? Theme.accent : Theme.textDim).frame(width: 10, height: 10).padding(6)
                                }
                                .frame(height: 40)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func alignment(_ c: CameraCorner) -> Alignment {
        switch c {
        case .topLeft: return .topLeading
        case .topRight: return .topTrailing
        case .bottomLeft: return .bottomLeading
        case .bottomRight: return .bottomTrailing
        }
    }
}

// MARK: - Audio

private struct AudioTab: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Audio")
            if !model.doc.info.hasSystemAudio && !model.doc.info.hasMic {
                Text("This recording has no audio.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.textDim)
            }
            if model.doc.info.hasSystemAudio {
                LabeledSlider(label: "System audio", value: model.styleBinding(\.systemVolume, key: "sysVol"), range: 0...2,
                              format: { "\(Int($0 * 100))%" })
            }
            if model.doc.info.hasMic {
                LabeledSlider(label: "Microphone", value: model.styleBinding(\.micVolume, key: "micVol"), range: 0...2,
                              format: { "\(Int($0 * 100))%" })
            }
            Text("Sped-up clips keep their natural pitch.")
                .font(.system(size: 11)).foregroundStyle(Theme.textFaint)
        }
    }
}
