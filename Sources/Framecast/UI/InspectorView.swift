import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum InspectorTab: String, CaseIterable, Identifiable {
    case background, cursor, zoom, animation, camera, audio, captions, chapters
    var id: String { rawValue }
    /// ⌘1… shortcut number.
    var number: Int { (InspectorTab.allCases.firstIndex(of: self) ?? 0) + 1 }
    var label: String { self == .background ? "Style" : rawValue.capitalized }
    var icon: String {
        switch self {
        case .background: return "photo.on.rectangle"
        case .cursor: return "cursorarrow"
        case .zoom: return "plus.magnifyingglass"
        case .camera: return "video"
        case .animation: return "wand.and.rays"
        case .audio: return "speaker.wave.2"
        case .captions: return "captions.bubble"
        case .chapters: return "list.bullet.rectangle"
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
            } else if let e = model.selectedEffect {
                EffectDetail(model: model, effect: e)
            } else {
                HStack {
                    Text(ui.inspectorTab.label)
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(height: 46)
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        switch ui.inspectorTab {
                        case .background: BackgroundTab(model: model)
                        case .cursor: CursorTab(model: model)
                        case .zoom: ZoomTab(model: model)
                        case .camera: CameraTab(model: model)
                        case .animation: AnimationTab(model: model)
                        case .audio: AudioTab(model: model)
                        case .captions: CaptionsTab(model: model)
                        case .chapters: ChaptersTab(model: model)
                        }
                    }
                    .padding(16)
                }
                .id(ui.inspectorTab) // each panel opens at the top
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
                    .background(RoundedRectangle(cornerRadius: 7).fill(ui.inspectorTab == tab ? Theme.fill.opacity(0.1) : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
    }
}

// MARK: - Background

enum WallpaperCategory: String, CaseIterable, Identifiable {
    case favorites, macOS, aurora, waves, glass, radiant, midnight, mesh
    var id: String { rawValue }
    var label: String { self == .macOS ? "macOS" : rawValue.capitalized }
    /// Framecast's own generated pack, if this category is one.
    var pack: WallpaperPack? { WallpaperPack(rawValue: rawValue) }
}

private struct BackgroundTab: View {
    @ObservedObject var model: EditorModel
    @AppStorage("bg.wallpaperCategory") private var wallpaperCategory: WallpaperCategory = .macOS
    @AppStorage("bg.favorites") private var favoritesStore = ""
    @State private var generating = false
    @State private var packRefresh = 0

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
                LabeledSlider(label: "Blur", value: model.styleBinding(\.background.blur, key: "blur"), range: 0...40, reset: 0)
            }
        }

        VStack(alignment: .leading, spacing: 14) {
            let d = Style()
            SectionHeader(title: "Frame")
            LabeledSlider(label: "Padding", value: model.styleBinding(\.padding, key: "padding"), range: 0...0.25,
                          format: { "\(Int($0 * 400))%" }, reset: d.padding)
            LabeledSlider(label: "Rounded corners", value: model.styleBinding(\.cornerRadius, key: "corner"), range: 0...60, reset: d.cornerRadius)
            LabeledSlider(label: "Shadow", value: model.styleBinding(\.shadow, key: "shadow"), range: 0...1,
                          format: { "\(Int($0 * 100))%" }, reset: d.shadow)
            PillPicker(options: ShadowStyle.allCases, selection: model.styleBinding(\.shadowStyle, key: "shStyle"), label: \.label)
            LabeledSlider(label: "Shadow softness", value: model.styleBinding(\.shadowBlur, key: "shadowBlur"), range: 4...120, reset: d.shadowBlur)
            if model.doc.style.shadowStyle == .directional {
                LabeledSlider(label: "Shadow distance", value: model.styleBinding(\.shadowDistance, key: "shDist"), range: 0...80,
                              reset: d.shadowDistance)
                LabeledSlider(label: "Shadow angle", value: model.styleBinding(\.shadowAngle, key: "shAngle"), range: 0...359,
                              format: { "\(Int($0))°" }, reset: d.shadowAngle)
            }
            ToggleRow(label: "Inset border inside the screen", isOn: model.styleBinding(\.inset, key: "inset"))
            if model.doc.style.inset {
                LabeledSlider(label: "Inset size", value: model.styleBinding(\.insetSize, key: "insetSize"), range: 1...30, reset: d.insetSize)
                LabeledSlider(label: "Inset opacity", value: model.styleBinding(\.insetOpacity, key: "insetOp"), range: 0.05...1,
                              format: { "\(Int($0 * 100))%" }, reset: d.insetOpacity)
                ColorPicker("Inset color", selection: Binding(get: { model.doc.style.insetColor.color }, set: { c in
                    model.edit(.render, coalesce: "insetColor") { $0.style.insetColor = RGBA(c) }
                }), supportsOpacity: false)
                .font(.system(size: 12))
            }
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
                            .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Theme.accent.opacity(0.25) : Theme.fill.opacity(0.06)))
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
        return VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(WallpaperCategory.allCases) { cat in
                    let on = wallpaperCategory == cat
                    Button { wallpaperCategory = cat } label: {
                        Group {
                            if cat == .favorites { Image(systemName: on ? "star.fill" : "star") } else { Text(cat.label) }
                        }
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 12).frame(height: 30)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.fill.opacity(on ? 0.1 : 0.04)))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(on ? Theme.accent.opacity(0.7) : .clear))
                        .foregroundStyle(on ? Theme.text : Theme.textDim)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            }
            Button {
                let pool = wallpaperList.isEmpty ? Backgrounds.wallpapers : wallpaperList
                if let w = pool.filter({ $0.path != current }).randomElement() {
                    model.edit(.render) { $0.style.background.wallpaperPath = w.path }
                }
            } label: { Label("Pick random wallpaper", systemImage: "sparkles").frame(maxWidth: .infinity) }
                .buttonStyle(SecondaryButtonStyle())
            wallpaperGrid(current: current)
        }
    }

    /// Wallpapers in the selected category.
    private var wallpaperList: [URL] {
        _ = packRefresh
        switch wallpaperCategory {
        case .favorites:
            let all = Backgrounds.wallpapers + WallpaperPack.allCases.flatMap(\.urls)
            return favorites.compactMap { f in all.first { $0.path == f } }.filter { FileManager.default.fileExists(atPath: $0.path) }
        case .macOS:
            return Backgrounds.wallpapers
        default:
            return wallpaperCategory.pack?.urls.filter { FileManager.default.fileExists(atPath: $0.path) } ?? []
        }
    }

    @ViewBuilder
    private func wallpaperGrid(current: String?) -> some View {
        let list = wallpaperList
        if let pack = wallpaperCategory.pack, !pack.isGenerated {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Creating \(pack.label) wallpapers…").font(.system(size: 11.5)).foregroundStyle(Theme.textDim)
            }
            .task(id: pack) {
                generating = true
                await pack.generate()
                generating = false
                packRefresh += 1
            }
        } else if list.isEmpty {
            Text("Right-click a wallpaper and choose Add to Favorites to keep it here.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8), spacing: 6) {
            ForEach(list, id: \.path) { url in
                WallpaperThumb(path: url.path, selected: current == url.path)
                    .onTapGesture {
                        model.edit(.render) { $0.style.background.wallpaperPath = url.path; $0.style.background.kind = .wallpaper }
                    }
                    .contextMenu {
                        if favorites.contains(url.path) {
                            Button("Remove from Favorites") { toggleFavorite(url.path) }
                        } else {
                            Button("Add to Favorites") { toggleFavorite(url.path) }
                        }
                    }
                    .help(url.deletingPathExtension().lastPathComponent)
            }
        }
    }

    private func toggleFavorite(_ path: String) {
        var f = favorites
        if let i = f.firstIndex(of: path) { f.remove(at: i) } else { f.append(path) }
        favoritesStore = f.joined(separator: "\n")
    }

    private var favorites: [String] { favoritesStore.split(separator: "\n").map(String.init) }

    private var gradients: some View {
        VStack(alignment: .leading, spacing: 10) {
            let stops = bg.customGradient ?? Backgrounds.gradients[clamp(bg.gradientIndex, 0, Backgrounds.gradients.count - 1)].colors
            HStack(spacing: 10) {
                ForEach(0..<2, id: \.self) { i in
                    ColorPicker("", selection: Binding(get: { (i == 0 ? stops.first : stops.last)?.color ?? .white }, set: { c in
                        model.edit(.render, coalesce: "grad\(i)") { d in
                            var s2 = [stops.first ?? RGBA(hex: 0x4776E6), stops.last ?? RGBA(hex: 0x8E54E9)]
                            s2[i] = RGBA(c)
                            d.style.background.customGradient = s2
                        }
                    }), supportsOpacity: false)
                    .labelsHidden()
                }
                Text(bg.customGradient == nil ? "Preset" : "Custom").font(.system(size: 11)).foregroundStyle(Theme.textDim)
                Spacer()
                Button {
                    model.edit(.render) { d in
                        let a = Double.random(in: 0...1)
                        d.style.background.customGradient = [
                            RGBA(Color(nsColor: NSColor(hue: a, saturation: 0.7, brightness: 0.95, alpha: 1))),
                            RGBA(Color(nsColor: NSColor(hue: (a + 0.12).truncatingRemainder(dividingBy: 1), saturation: 0.75, brightness: 0.85, alpha: 1))),
                        ]
                    }
                } label: { Image(systemName: "shuffle") }
                    .buttonStyle(SecondaryButtonStyle())
                    .help("Random gradient")
            }
            LabeledSlider(label: "Hue", value: model.styleBinding(\.background.gradientHue, key: "hue"), range: -180...180,
                          format: { "\(Int($0))°" }, reset: 0)
            presetGradients
        }
    }

    private var presetGradients: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            ForEach(Backgrounds.gradients.indices, id: \.self) { i in
                let g = Backgrounds.gradients[i]
                let selected = bg.customGradient == nil && bg.gradientIndex == i
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient(colors: g.colors.map(\.color),
                                         startPoint: unitPoint(angle: g.angle + 180), endPoint: unitPoint(angle: g.angle)))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(selected ? Theme.accent : Theme.border, lineWidth: selected ? 2 : 1))
                    .onTapGesture { model.edit(.render) { $0.style.background.gradientIndex = i; $0.style.background.customGradient = nil } }
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
                        .overlay(Circle().strokeBorder(bg.solid == c ? Theme.accent : Theme.border, lineWidth: bg.solid == c ? 2 : 1))
                        .onTapGesture { model.edit(.render) { $0.style.background.solid = c } }
                }
            }
            ColorPicker("Custom color", selection: Binding(get: { bg.solid.color }, set: { c in
                model.edit(.render, coalesce: "solid") { $0.style.background.solid = RGBA(c) }
            }), supportsOpacity: false)
            .font(.system(size: 12))
        }
    }

    /// Saves a pasted image into the project so it travels with it.
    private func pasteImage() {
        let pb = NSPasteboard.general
        if let url = (pb.readObjects(forClasses: [NSURL.self]) as? [URL])?.first, NSImage(contentsOf: url) != nil {
            model.edit(.render) { $0.style.background.imagePath = url.path }
            return
        }
        guard let image = NSImage(pasteboard: pb), let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { NSSound.beep(); return }
        let url = model.folder.appendingPathComponent("background-\(UUID().uuidString.prefix(8)).png")
        guard (try? png.write(to: url)) != nil else { NSSound.beep(); return }
        model.edit(.render) { $0.style.background.imagePath = url.path }
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
                VStack(spacing: 6) {
                    Image(systemName: "photo.badge.plus").font(.system(size: 20))
                    Text(bg.imagePath == nil ? "Click or drop an image" : "Click or drop to change")
                        .font(.system(size: 11))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .foregroundStyle(Theme.textDim)
                .background(RoundedRectangle(cornerRadius: 10).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4])).foregroundStyle(Theme.border))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                _ = providers.first?.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, NSImage(contentsOf: url) != nil else { return }
                    DispatchQueue.main.async { model.edit(.render) { $0.style.background.imagePath = url.path } }
                }
                return true
            }
            Button("Paste Image") { pasteImage() }
                .buttonStyle(SecondaryButtonStyle())
                .help("Use the image on the clipboard")
        }
    }
}

private struct WallpaperThumb: View {
    let path: String
    let selected: Bool
    @State private var image: NSImage?

    var body: some View {
        // The square decides the size; the (wide) image is cropped to it, never the other way round.
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    Rectangle().fill(Theme.fill.opacity(0.05))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        // The selected one gets an inset white ring with a dark gap, like a focus ring.
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .strokeBorder(selected ? Color.white : Color.white.opacity(0.12), lineWidth: selected ? 2 : 0.5))
        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).inset(by: 2)
            .strokeBorder(selected ? Color.black.opacity(0.5) : .clear, lineWidth: 1))
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
        let d = Style()
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Cursor")
            if model.cursorTrack.isEmpty {
                Text("This video has no cursor data. Cursor effects are available for recordings made with Framecast.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.textDim)
            } else {
                ToggleRow(label: "Show cursor", isOn: model.styleBinding(\.showCursor, key: "showCursor"))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(CursorStyleKind.allCases) { k in
                            CursorStyleTile(kind: k, selected: model.doc.style.cursorStyle == k) {
                                model.edit(.render) { $0.style.cursorStyle = k }
                            }
                        }
                    }
                }
                LabeledSlider(label: "Size", value: model.styleBinding(\.cursorSize, key: "cursorSize"), range: 0.5...4,
                              format: { String(format: "%.1f×", $0) }, reset: d.cursorSize)
                ToggleRow(label: "Always use the pointer", isOn: model.styleBinding(\.alwaysPointer, key: "alwaysPtr"))
                hint("Keeps the arrow over text fields and links instead of the I-beam or hand.")
                ToggleRow(label: "Hide when not moving", isOn: model.styleBinding(\.hideIdleCursor, key: "idle"))
                ToggleRow(label: "Motion blur", isOn: model.styleBinding(\.cursorMotionBlur, key: "mblur"))
                ToggleRow(label: "Loop cursor position", isOn: model.styleBinding(\.loopCursor, key: "loopCur"))
                hint("Glides back to where it started at the end, so looping videos and GIFs join up.")
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
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Rotation")
                LabeledSlider(label: "Rotate cursor", value: model.styleBinding(\.cursorAngle, key: "curAngle"), range: -45...45,
                              format: { "\(Int($0))°" }, reset: 0)
                Text("Rotate while moving").font(.system(size: 12))
                PillPicker(options: CursorRotation.allCases, selection: model.styleBinding(\.cursorRotation, key: "curRot"), label: \.label)
                switch model.doc.style.cursorRotation {
                case .off: EmptyView()
                case .tilt:
                    LabeledSlider(label: "Tilt amount", value: model.styleBinding(\.cursorTiltAmount, key: "tilt"), range: 0.05...1,
                                  format: { "\(Int($0 * 100))%" }, reset: d.cursorTiltAmount)
                    hint("Leans into fast sideways movement and springs back upright.")
                case .follow:
                    hint("The arrow turns to point where it's going.")
                }
            }
            DisclosureCard(title: "Advanced") {
                LabeledSlider(label: "Stop cursor movement at the end", value: model.styleBinding(\.cursorStopAtEnd, key: "stopEnd"),
                              range: 0...5, format: { $0 < 0.05 ? "Off" : String(format: "%.1fs", $0) }, reset: 0)
                hint("Freezes the cursor for the last seconds, so reaching for the stop button isn't shown.")
                ToggleRow(label: "Remove cursor shakes", isOn: model.styleBinding(\.removeCursorShakes, key: "shakes"))
                if model.doc.style.removeCursorShakes {
                    LabeledSlider(label: "Shake threshold", value: model.styleBinding(\.cursorShakeThreshold, key: "shakeT"),
                                  range: 0.05...1, format: { "\(Int($0 * 100))%" }, reset: d.cursorShakeThreshold)
                }
                ToggleRow(label: "Optimize cursor changes", isOn: model.styleBinding(\.optimizeCursorChanges, key: "optCur"))
                hint("Ignores cursor shapes shown for a split second, so the cursor doesn't flicker over buttons.")
            }
        }
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Keystrokes")
            if model.keys.isEmpty {
                Text("No keystrokes were recorded. Turn on “Record keystrokes” before recording to show shortcuts on screen.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                PillPicker(options: KeystrokeMode.allCases, selection: model.styleBinding(\.keystrokes, key: "keys"), label: \.label)
                LabeledSlider(label: "Size", value: model.styleBinding(\.keystrokeSize, key: "keySize"), range: 0.6...2,
                              format: { String(format: "%.1f×", $0) }, reset: 1)
                Text("\(model.keys.filter(\.isShortcut).count) shortcuts · \(model.keys.count) key presses recorded")
                    .font(.system(size: 11)).foregroundStyle(Theme.textFaint)
            }
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(Theme.textDim).fixedSize(horizontal: false, vertical: true)
    }
}

/// A preview tile for a cursor style, drawn from the same art the renderer uses.
private struct CursorStyleTile: View {
    let kind: CursorStyleKind
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9).fill(Theme.fill.opacity(0.05))
                    if let img = CursorStyleTile.preview(kind) {
                        Image(nsImage: img).resizable().interpolation(.high).scaledToFit().padding(12)
                    } else {
                        Image(systemName: "cursorarrow").font(.system(size: 22))
                    }
                }
                .frame(width: 58, height: 58)
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(selected ? Theme.accent : Theme.border, lineWidth: selected ? 2 : 1))
                Text(kind.label).font(.system(size: 10)).foregroundStyle(selected ? Theme.text : Theme.textDim).lineLimit(1)
            }
            .frame(width: 64)
        }
        .buttonStyle(.plain)
    }

    private static var cache: [CursorStyleKind: NSImage] = [:]

    static func preview(_ kind: CursorStyleKind) -> NSImage? {
        if let hit = cache[kind] { return hit }
        guard kind != .system else { return nil }
        let ci = CursorArt.art(kind).0
        guard let cg = FrameRenderer.shared.ciContext.createCGImage(ci, from: ci.extent) else { return nil }
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache[kind] = img
        return img
    }
}

// MARK: - Zoom

private struct ZoomTab: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Zoom")
            LabeledSlider(label: "Default zoom level", value: model.styleBinding(\.defaultZoomScale, key: "defZoom"), range: 1.2...4,
                          format: { String(format: "%.1f×", $0) }, reset: 2)
            ToggleRow(label: "Disable all zooms", isOn: model.styleBinding(\.zoomsDisabled, key: "zoomsOff"))
            Text("\(model.doc.zooms.count) zoom\(model.doc.zooms.count == 1 ? "" : "s") on the timeline\(model.doc.style.zoomsDisabled ? ", kept but not shown" : ""). Click one to edit it, or click an empty spot in the zoom lane to add one.")
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

// MARK: - Animation

private struct AnimationTab: View {
    @ObservedObject var model: EditorModel

    private static let cursorPresets: [(String, String, Double)] = [
        ("Smooth", "water.waves", 0.8), ("Medium", "wave.3.right", 0.55), ("Rapid", "bolt", 0.3), ("None", "nosign", 0),
    ]

    var body: some View {
        let d = Style()
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Screen animation")
            ChoiceTiles(options: ScreenAnimation.allCases, selection: model.styleBinding(\.screenAnimation, key: "screenAnim"),
                        label: \.label, icon: \.icon, detail: \.detail)
            LabeledSlider(label: "Zoom transition", value: model.styleBinding(\.zoomTransition, key: "zoomT"), range: 0.3...1.6,
                          format: { String(format: "%.1fs", $0) }, reset: d.zoomTransition)
            ToggleRow(label: "Start zooms early", isOn: model.styleBinding(\.startZoomEarly, key: "early"))
            Text("Zoom in before each zoom starts, so it's fully zoomed right on time.")
                .font(.system(size: 11)).foregroundStyle(Theme.textDim).fixedSize(horizontal: false, vertical: true)
        }
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Motion blur")
            LabeledSlider(label: "Screen motion blur", value: model.styleBinding(\.motionBlur, key: "mblurScreen"), range: 0...1,
                          format: { $0 < 0.01 ? "Off" : "\(Int($0 * 100))%" }, reset: d.motionBlur)
            Text("Moving elements get a cinematic blur while the camera zooms and pans.")
                .font(.system(size: 11)).foregroundStyle(Theme.textDim).fixedSize(horizontal: false, vertical: true)
        }
        if !model.cursorTrack.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Cursor animation")
                let current = model.doc.style.cursorSmoothing
                HStack(spacing: 6) {
                    ForEach(AnimationTab.cursorPresets, id: \.0) { name, icon, value in
                        let on = abs(current - value) < 0.02
                        Button { model.edit(.render) { $0.style.cursorSmoothing = value } } label: {
                            VStack(spacing: 5) {
                                Image(systemName: icon).font(.system(size: 15))
                                Text(name).font(.system(size: 10.5, weight: .medium))
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 9).fill(Theme.fill.opacity(on ? 0.1 : 0.04)))
                            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(on ? Theme.accent : Theme.border, lineWidth: on ? 1.5 : 1))
                            .foregroundStyle(on ? Theme.text : Theme.textDim)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                LabeledSlider(label: "Fine-tune smoothing", value: model.styleBinding(\.cursorSmoothing, key: "smoothing"), range: 0...1,
                              format: { $0 < 0.02 ? "Off" : "\(Int($0 * 100))%" }, reset: d.cursorSmoothing)
            }
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
                    ToggleRow(label: "Instant animation", isOn: Binding(get: { zoom.instant }, set: { v in
                        model.updateZoom(zoom.id) { $0.instant = v }
                    }))
                    Text("Cuts straight in and out instead of easing.")
                        .font(.system(size: 11)).foregroundStyle(Theme.textDim)
                    HStack {
                        Text("Starts \(formatTime(zoom.start, fraction: true))")
                        Spacer()
                        Text("Lasts \(String(format: "%.1fs", zoom.duration))")
                    }
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Theme.textDim)
                    WideButton(title: "Focus the timeline on the zoom start", icon: "arrow.right.to.line") { model.seek(source: zoom.start) }
                    Divider().padding(.vertical, 4)
                    WideButton(title: "Remove zoom", icon: "trash", destructive: true) { model.deleteSelection() }
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
                    Rectangle().fill(Theme.fill.opacity(0.06))
                }
                // visible area at this zoom level
                let w = geo.size.width / zoom.scale, h = geo.size.height / zoom.scale
                let cx = clamp(zoom.focusX * geo.size.width, w / 2, geo.size.width - w / 2)
                let cy = clamp(zoom.focusY * geo.size.height, h / 2, geo.size.height - h / 2)
                Rectangle()
                    .strokeBorder(Color.white, lineWidth: 1.5)
                    .background(Theme.fill.opacity(0.08))
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
    private let speeds: [Double] = [0.5, 0.75, 1, 1.2, 1.4, 1.6, 1.8, 2, 3, 4, 8, 16, 24]

    var body: some View {
        VStack(spacing: 0) {
            DetailHeader(title: clip.freeze ? "Freeze frame" : "Clip", icon: clip.freeze ? "snowflake" : "film", color: Theme.clip) { model.selection = .none }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if clip.freeze {
                        LabeledSlider(label: "Hold for", value: Binding(get: { clip.holdSeconds }, set: { model.setFreezeLength(clip.id, seconds: $0) }),
                                      range: 0.5...10, format: { String(format: "%.1fs", $0) })
                        Text("The picture holds still here, silently. Great for giving viewers time to read, or behind an intro or outro slide.")
                            .font(.system(size: 11)).foregroundStyle(Theme.textDim).fixedSize(horizontal: false, vertical: true)
                        WideButton(title: "Remove freeze frame", icon: "trash", destructive: true) { model.deleteSelection() }
                    } else {
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
                                        .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Theme.clip.opacity(0.3) : Theme.fill.opacity(0.06)))
                                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(selected ? Theme.clip : .clear))
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Text("Speed up typing or waiting, or slow down important moments.")
                            .font(.system(size: 11)).foregroundStyle(Theme.textDim)
                        Button { model.applySpeedToAll(clip.speed) } label: {
                            Label("Apply \(clip.speed, specifier: "%g")× to all clips", systemImage: "rectangle.stack").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(model.doc.clips.count < 2 || model.doc.clips.allSatisfy { abs($0.speed - clip.speed) < 0.001 })
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        row("Source", "\(formatTime(clip.start, fraction: true)) – \(formatTime(clip.end, fraction: true))")
                        row("Length in video", String(format: "%.1fs", clip.duration / clip.speed))
                    }
                    WideButton(title: "Cut at playhead", icon: "scissors") { model.splitAtPlayhead() }
                    WideButton(title: "Freeze frame at playhead", icon: "snowflake") {
                        if let f = model.insertFreezeFrame(at: model.sourceTime) { model.selection = .clip(f.id) }
                    }
                    }
                    Divider().padding(.vertical, 4)
                    WideButton(title: "Remove clip", icon: "trash", destructive: true) { model.deleteSelection() }
                        .disabled(model.doc.clips.count < 2)
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
            Button(action: onClose) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.left").font(.system(size: 12, weight: .semibold))
                    Text("Close \(title) editor").font(.system(size: 12.5, weight: .medium))
                }
                .padding(.horizontal, 12).frame(height: 32)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.fill.opacity(0.06)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Back (Esc)")
            Spacer()
            Image(systemName: icon).foregroundStyle(color)
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
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
                Text("Background").font(.system(size: 12))
                PillPicker(options: CameraBackground.allCases, selection: model.styleBinding(\.camera.background, key: "camBg"), label: \.label)
                if model.doc.style.camera.background == .remove {
                    Text("Your cut-out floats over the recording. Works best with good lighting.")
                        .font(.system(size: 11)).foregroundStyle(Theme.textDim)
                }
                Text("Shape").font(.system(size: 12))
                PillPicker(options: CameraShape.allCases, selection: model.styleBinding(\.camera.shape, key: "camShape"), label: \.label)
                LabeledSlider(label: "Size", value: model.styleBinding(\.camera.size, key: "camSize"), range: 0.1...0.5,
                              format: { "\(Int($0 * 100))%" })
                Text("Position").font(.system(size: 12))
                positionGrid
                ToggleRow(label: "Mirror", isOn: model.styleBinding(\.camera.mirror, key: "camMirror"))
                ToggleRow(label: "Shrink while zoomed", isOn: model.styleBinding(\.camera.shrinkOnZoom, key: "camShrink"))
                ToggleRow(label: "Fade out when the cursor goes behind it", isOn: model.styleBinding(\.cameraAvoidCursor, key: "camAvoid"))
                ToggleRow(label: "Border", isOn: model.styleBinding(\.camera.border, key: "camBorder"))
            }
        }
        if model.doc.info.hasWebcam {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Layouts")
                Text("Show the camera full screen for an intro or outro, or hide it for part of the video.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button { model.addEffect(.cameraFull) } label: { Label("Full screen", systemImage: EffectKind.cameraFull.icon) }
                        .buttonStyle(SecondaryButtonStyle())
                    Button { model.addEffect(.cameraHidden) } label: { Label("Hide", systemImage: EffectKind.cameraHidden.icon) }
                        .buttonStyle(SecondaryButtonStyle())
                }
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
                                .fill(selected ? Theme.accent.opacity(0.3) : Theme.fill.opacity(0.06))
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

// MARK: - Effect

private struct EffectDetail: View {
    @ObservedObject var model: EditorModel
    let effect: EffectSegment

    /// `coalesce` merges rapid changes (sliders, typing) into one undo step; discrete taps pass false.
    private func binding<T>(_ kp: WritableKeyPath<EffectSegment, T>, key: String, coalesce: Bool = true) -> Binding<T> {
        Binding(get: { effect[keyPath: kp] },
                set: { v in model.updateEffect(effect.id, coalesce: coalesce ? "\(key)-\(effect.id)" : nil) { $0[keyPath: kp] = v } })
    }

    var body: some View {
        VStack(spacing: 0) {
            DetailHeader(title: effect.kind.label, icon: effect.kind.icon, color: TimelineView.effectColor(effect.kind)) { model.selection = .none }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch effect.kind {
                    case .blur:
                        RegionPicker(model: model, effect: effect, tint: TimelineView.effectColor(.blur))
                        PillPicker(options: [false, true], selection: binding(\.pixelate, key: "pix"), label: { $0 ? "Pixelate" : "Blur" })
                        LabeledSlider(label: "Strength", value: binding(\.intensity, key: "int"), range: 0.1...1,
                                      format: { "\(Int($0 * 100))%" })
                        note("Hide passwords, emails or customer data. The blur follows the zoom.")
                    case .spotlight:
                        RegionPicker(model: model, effect: effect, tint: TimelineView.effectColor(.spotlight))
                        LabeledSlider(label: "Dim the rest", value: binding(\.intensity, key: "int"), range: 0.1...0.9,
                                      format: { "\(Int($0 * 100))%" })
                        note("Darkens everything except the highlighted area to draw attention to it.")
                    case .text:
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Text").font(.system(size: 12))
                            TextField("Title", text: binding(\.text, key: "text"), axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(1...4)
                            TextField("Subtitle (optional)", text: binding(\.subtitle, key: "subtitle"), axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(1...3)
                        }
                        TitleStyleEditor(style: binding(\.titleStyle, key: "tstyle", coalesce: false))
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Position").font(.system(size: 12))
                            PillPicker(options: TextPlacement.allCases, selection: binding(\.placement, key: "place"), label: \.label)
                        }
                        LabeledSlider(label: "Size", value: binding(\.textSize, key: "tsize"), range: 0.5...2,
                                      format: { String(format: "%.1f×", $0) })
                    case .slide:
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Text").font(.system(size: 12))
                            TextField("Title", text: binding(\.text, key: "text"), axis: .vertical)
                                .textFieldStyle(.roundedBorder).lineLimit(1...4)
                            TextField("Subtitle (optional)", text: binding(\.subtitle, key: "subtitle"), axis: .vertical)
                                .textFieldStyle(.roundedBorder).lineLimit(1...3)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Background").font(.system(size: 12))
                            PillPicker(options: SlideBackground.allCases, selection: binding(\.slideBackground, key: "sbg", coalesce: false), label: \.label)
                            if effect.slideBackground == .color {
                                SwatchRow(colors: TitleStyle.palette, selection: effect.titleStyle.cardColor, allowsAuto: false) { c in
                                    if let c { model.updateEffect(effect.id) { $0.titleStyle.cardColor = c } }
                                }
                            }
                        }
                        LabeledSlider(label: "Size", value: binding(\.textSize, key: "tsize"), range: 0.5...2,
                                      format: { String(format: "%.1f×", $0) })
                        TitleStyleEditor(style: binding(\.titleStyle, key: "tstyle", coalesce: false), showsCard: false)
                        note("A full-screen card for intros, outros and new sections. Intro and outro slides hold the first or last frame still, so they add time instead of covering your recording.")
                    case .image:
                        ImageOverlayThumb(model: model, file: effect.imageFile)
                        Button {
                            if let f = model.chooseOverlayImage() { model.updateEffect(effect.id) { $0.imageFile = f } }
                        } label: { Label("Replace Image…", systemImage: "photo.on.rectangle") .frame(maxWidth: .infinity) }
                            .buttonStyle(SecondaryButtonStyle())
                        LabeledSlider(label: "Size", value: binding(\.imageWidth, key: "iw"), range: 0.05...1,
                                      format: { "\(Int($0 * 100))%" })
                        LabeledSlider(label: "Corners", value: binding(\.imageCorner, key: "ic"), range: 0...60,
                                      format: { "\(Int($0))" })
                        ToggleRow(label: "Shadow", isOn: binding(\.imageShadow, key: "ish"))
                        note("A logo, screenshot or sticker over the video. Drag it on the video to place it; drag the corner to resize.")
                    case .annotation:
                        RegionPicker(model: model, effect: effect, tint: TimelineView.effectColor(.annotation))
                        PillPicker(options: AnnotationShape.allCases, selection: binding(\.shape, key: "shape"), label: \.label, icon: { $0.icon })
                        if effect.shape == .arrow {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Points").font(.system(size: 12))
                                HStack(spacing: 4) {
                                    ForEach(ArrowDirection.allCases) { d in
                                        Button { model.updateEffect(effect.id) { $0.arrowDirection = d } } label: {
                                            Image(systemName: d.icon).font(.system(size: 12, weight: .semibold))
                                                .frame(width: 30, height: 28)
                                                .background(RoundedRectangle(cornerRadius: 7).fill(Theme.fill.opacity(effect.arrowDirection == d ? 0.14 : 0.05)))
                                                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(effect.arrowDirection == d ? Theme.accent : .clear, lineWidth: 1.5))
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Arrow points \(d.rawValue)")
                                    }
                                }
                            }
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Color").font(.system(size: 12))
                            SwatchRow(colors: TitleStyle.palette, selection: effect.strokeColor, allowsAuto: false) { c in
                                if let c { model.updateEffect(effect.id) { $0.strokeColor = c } }
                            }
                        }
                        LabeledSlider(label: "Thickness", value: binding(\.strokeWidth, key: "sw"), range: 2...18,
                                      format: { "\(Int($0))" })
                        note("Point at a button or circle what matters. It follows the zoom, like blur.")
                    case .cameraMove:
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Move to").font(.system(size: 12))
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                                ForEach([CameraCorner.topLeft, .topRight, .bottomLeft, .bottomRight]) { c in
                                    Button { model.updateEffect(effect.id) { $0.cameraCorner = c } } label: {
                                        ZStack(alignment: c == .topLeft ? .topLeading : c == .topRight ? .topTrailing : c == .bottomLeft ? .bottomLeading : .bottomTrailing) {
                                            RoundedRectangle(cornerRadius: 6).fill(Theme.fill.opacity(effect.cameraCorner == c ? 0.14 : 0.05))
                                            Circle().fill(effect.cameraCorner == c ? Theme.accent : Theme.textDim).frame(width: 12, height: 12).padding(6)
                                        }
                                        .frame(height: 44)
                                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(effect.cameraCorner == c ? Theme.accent : .clear, lineWidth: 1.5))
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(c.rawValue)
                                }
                            }
                        }
                        LabeledSlider(label: "Size", value: binding(\.cameraSize, key: "cs"), range: 0.12...0.6,
                                      format: { "\(Int($0 * 100))%" })
                        note("The camera glides to this corner and size for this part, then back. Handy when it covers something.")
                    case .hideCursor:
                        note("The cursor and click effects fade out for this part of the video.")
                    case .cameraFull:
                        note("The camera grows to fill the frame, which works well for intros and outros. It returns to the bubble when this ends.")
                    case .cameraHidden:
                        note("The camera fades out for this part of the video.")
                    }

                    if effect.kind == .blur {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.shield").foregroundStyle(.orange)
                            Text("Make sure the blur covers the whole part of the timeline where the sensitive data is visible.")
                                .font(.system(size: 11.5)).foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 9).fill(Color.orange.opacity(0.1)))
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.orange.opacity(0.3)))
                    }
                    if effect.kind.hasRegion || effect.kind == .text {
                        Text(effect.kind == .text ? "Tip: drag the title on the video to place it anywhere."
                                                  : "Tip: move and resize the area right on the video (pause first).")
                            .font(.system(size: 11)).foregroundStyle(Theme.textDim)
                    }
                    WideButton(title: "Focus the timeline on the \(effect.kind.label.lowercased()) start", icon: "arrow.right.to.line") {
                        model.seek(source: effect.start + min(0.3, effect.duration / 2))
                    }
                    Divider().padding(.vertical, 2)
                    VStack(alignment: .leading, spacing: 4) {
                        ToggleRow(label: "Disable", isOn: binding(\.disabled, key: "disabled"))
                        Text("When disabled, the \(effect.kind.label.lowercased()) isn't shown, but it stays on the timeline.")
                            .font(.system(size: 11)).foregroundStyle(Theme.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack {
                        Text("Starts \(formatTime(effect.start, fraction: true))")
                        Spacer()
                        Text("Lasts \(String(format: "%.1fs", effect.duration))")
                    }
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Theme.textDim)
                    WideButton(title: "Duplicate", icon: "plus.square.on.square") { model.duplicateEffect(effect.id) }
                    Divider().padding(.vertical, 2)
                    WideButton(title: "Remove \(effect.kind.label.lowercased())", icon: "trash", destructive: true) { model.deleteSelection() }
                }
                .padding(16)
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(Theme.textDim).fixedSize(horizontal: false, vertical: true)
    }
}

/// A frame of the recording with the effect's area: drag inside to move it, drag a handle to resize it.
private struct RegionPicker: View {
    @ObservedObject var model: EditorModel
    let effect: EffectSegment
    let tint: Color
    @State private var frame: CGImage?

    var body: some View {
        let aspect = CGFloat(model.doc.info.pixelWidth) / CGFloat(max(1, model.doc.info.pixelHeight))
        VStack(alignment: .leading, spacing: 6) {
            Text("Area").font(.system(size: 12))
            RectEditor(rect: Binding(get: { effect.region }, set: { r in
                model.updateEffect(effect.id, coalesce: "region-\(effect.id)") {
                    $0.x = Double(r.minX); $0.y = Double(r.minY); $0.w = Double(r.width); $0.h = Double(r.height)
                }
            }), ratio: nil, image: frame, imageAspect: aspect)
            .aspectRatio(aspect, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.border))
            .task(id: effect.id) { frame = await model.rawFrame(at: effect.start + min(0.5, effect.duration / 2)) }
            Text("Drag inside to move, drag a handle to resize.")
                .font(.system(size: 11)).foregroundStyle(Theme.textDim)
        }
    }
}

// MARK: - Captions

private struct CaptionsTab: View {
    @ObservedObject var model: EditorModel
    @State private var locale = Transcriber.defaultLocale()
    @State private var working = false
    @State private var progress = 0.0
    @State private var status = ""
    @State private var error: String?

    private var hasAudio: Bool { model.doc.info.hasMic || model.doc.info.hasSystemAudio }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Captions")
            if !hasAudio {
                Text("This recording has no audio to transcribe. Turn on the microphone to narrate your next recording.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Transcribe your narration into captions on your Mac. Audio never leaves your computer when the language supports on-device recognition.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
                Picker("Language", selection: $locale) {
                    ForEach(Transcriber.supportedLocales, id: \.identifier) { l in
                        Text(Transcriber.name(for: l)).tag(l)
                    }
                }
                .font(.system(size: 12))
                .disabled(working)
                if working {
                    ProgressView(value: progress).tint(Theme.accent)
                    HStack {
                        Text("\(status) \(Int(progress * 100))%").font(.system(size: 11)).foregroundStyle(Theme.textDim)
                        Spacer()
                        Button("Cancel") { model.captionTask?.cancel() }.buttonStyle(SecondaryButtonStyle())
                    }
                } else {
                    Button {
                        generate()
                    } label: {
                        Label(model.doc.captions.isEmpty ? "Generate Captions" : "Regenerate Captions", systemImage: "waveform")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11)).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }

        if !model.doc.captions.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Display")
                ToggleRow(label: "Show captions in video", isOn: model.styleBinding(\.showCaptions, key: "showCap"))
                LabeledSlider(label: "Size", value: model.styleBinding(\.captionSize, key: "capSize"), range: 0.6...2,
                              format: { String(format: "%.1f×", $0) })
                HStack {
                    Button { exportSRT() } label: { Label("Export .srt", systemImage: "square.and.arrow.up") }
                        .buttonStyle(SecondaryButtonStyle())
                    Spacer()
                    Button(role: .destructive) { model.setCaptions([]) } label: { Label("Remove all", systemImage: "trash") }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "\(model.doc.captions.count) lines")
                ForEach(model.doc.captions.sorted(by: { $0.start < $1.start })) { cue in
                    CaptionRow(model: model, cue: cue)
                }
            }
        }
    }

    private func generate() {
        error = nil
        working = true
        progress = 0
        status = "Preparing audio…"
        let folder = model.folder, info = model.doc.info, loc = locale
        model.captionTask?.cancel()
        let model = self.model
        model.captionTask = Task {
            do {
                let cues = try await Transcriber.transcribe(folder: folder, info: info, locale: loc) { p, s in
                    DispatchQueue.main.async { progress = p; status = s }
                }
                guard !Task.isCancelled, !model.isTrashed else { return }
                model.setCaptions(cues)
            } catch is CancellationError {
            } catch {
                self.error = error.localizedDescription
            }
            working = false
        }
    }

    private func exportSRT() {
        let panel = SavePanels.make(name: model.doc.name, ext: "srt", types: [UTType(filenameExtension: "srt") ?? .plainText])
        guard let url = SavePanels.run(panel) else { return }
        try? model.srt().write(to: url, atomically: true, encoding: .utf8)
    }
}

private struct CaptionRow: View {
    @ObservedObject var model: EditorModel
    let cue: CaptionCue
    @State private var text = ""

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button { model.seek(source: cue.start) } label: {
                Text(formatTime(cue.start, fraction: true))
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(Theme.accent)
                    .frame(width: 44, alignment: .leading)
            }
            .buttonStyle(.plain)
            .help("Go to this line")
            TextField("", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))
                .lineLimit(1...3)
                .onSubmit { commit() }
                .onChange(of: text) { _, _ in commit() }
            Button { model.cutCaption(cue.id) } label: { Image(systemName: "scissors").font(.system(size: 9.5)) }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textDim)
                .help("Cut this line out of the video (edit by transcript)")
                .accessibilityLabel("Cut this line from the video")
            Button { model.deleteCaption(cue.id) } label: { Image(systemName: "xmark").font(.system(size: 9)) }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textFaint)
                .help("Delete line")
        }
        .padding(.vertical, 4)
        .onAppear { text = cue.text }
        .onChange(of: cue.text) { _, v in if v != text { text = v } }
    }

    private func commit() {
        if text != cue.text { model.updateCaption(cue.id, text: text) }
    }
}

/// A full-width inspector button, like "Remove zoom".
private struct WideButton: View {
    let title: String
    let icon: String
    var destructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 12.5, weight: .medium))
                .frame(maxWidth: .infinity).frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 9).fill(destructive ? Color.red.opacity(0.1) : Theme.fill.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(destructive ? Color.red.opacity(0.25) : Theme.border))
                .foregroundStyle(destructive ? Color.red : Theme.text)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A small preview of an image overlay's picture.
private struct ImageOverlayThumb: View {
    let model: EditorModel
    let file: String
    var body: some View {
        let url = model.folder.appendingPathComponent("overlays", isDirectory: true).appendingPathComponent(file)
        Group {
            if let img = NSImage(contentsOf: url) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
            } else {
                Label("Image missing", systemImage: "photo").foregroundStyle(Theme.textDim)
            }
        }
        .frame(maxWidth: .infinity).frame(height: 110)
        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.fill.opacity(0.05)))
    }
}

// MARK: - Chapters

/// Named moments in the video, copied as a YouTube chapter list.
private struct ChaptersTab: View {
    @ObservedObject var model: EditorModel
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Chapters")
            Text("Mark where each part of your video starts. Paste the list into a YouTube description to get chapters.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.textDim).fixedSize(horizontal: false, vertical: true)
            Button { model.addChapter(at: model.sourceTime) } label: {
                Label("Add Chapter at Playhead", systemImage: "plus").frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
            if model.doc.chapters.isEmpty && !model.doc.flags.isEmpty {
                Button {
                    for (i, f) in model.doc.flags.sorted().enumerated() { model.addChapter(at: f, title: "Chapter \(i + 1)") }
                } label: {
                    Label("Use the \(model.doc.flags.count) flag\(model.doc.flags.count == 1 ? "" : "s") you marked while recording", systemImage: "flag")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            ForEach(model.doc.chapters.sorted { $0.time < $1.time }) { ch in
                ChapterRow(model: model, chapter: ch)
            }
            if !model.doc.chapters.isEmpty {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.youTubeChapters(), forType: .string)
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy YouTube Chapters", systemImage: copied ? "checkmark" : "doc.on.doc").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                Text(model.youTubeChapters())
                    .font(.system(size: 11).monospaced()).foregroundStyle(Theme.textDim)
                    .textSelection(.enabled)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.fill.opacity(0.05)))
            }
        }
        .onChange(of: model.doc.chapters) { _, _ in copied = false }
    }
}

private struct ChapterRow: View {
    @ObservedObject var model: EditorModel
    let chapter: Chapter
    @State private var title = ""

    var body: some View {
        HStack(spacing: 8) {
            Button { model.seek(source: chapter.time) } label: {
                Text(formatTime(model.editMap.compTime(source: chapter.time), fraction: false))
                    .font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.accent).frame(width: 40, alignment: .leading)
            }
            .buttonStyle(.plain)
            .help("Go to this chapter")
            TextField("Chapter title", text: $title)
                .textFieldStyle(.roundedBorder)
                .onChange(of: title) { _, v in if v != chapter.title { model.updateChapter(chapter.id, title: v) } }
            Button { model.deleteChapter(chapter.id) } label: { Image(systemName: "xmark").font(.system(size: 9)) }
                .buttonStyle(.plain).foregroundStyle(Theme.textFaint)
                .accessibilityLabel("Delete chapter")
        }
        .onAppear { title = chapter.title }
    }
}
