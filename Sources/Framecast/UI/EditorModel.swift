import Foundation
import AVFoundation
import CoreImage
import AppKit
import Combine
import SwiftUI

@MainActor
final class EditorModel: ObservableObject {
    enum Selection: Equatable { case none, zoom(UUID), clip(UUID), effect(UUID) }
    enum EditScope { case timeline, render, meta }

    fileprivate struct Snapshot: Equatable {
        var name: String
        var clips: [Clip]
        var zooms: [ZoomSegment]
        var style: Style
        var effects: [EffectSegment]
        var captions: [CaptionCue]
    }

    let folder: URL
    @Published private(set) var doc: ProjectDocument
    let cursorTrack: CursorTrack
    let cursorImages: [String: CIImage]
    let keys: [KeyEvent]

    @Published private(set) var isReady = false
    @Published private(set) var loadError: String?
    @Published private(set) var compTime: Double = 0
    @Published private(set) var isPlaying = false
    @Published var selection: Selection = .none
    @Published private(set) var editMap: EditMap
    @Published private(set) var filmstrip: [CGImage] = []
    /// Audio loudness over source time (0…1 per bin), for the timeline waveform.
    @Published private(set) var waveform: [Float] = []
    /// Blade tool: clicking the clip lane cuts there.
    @Published var bladeMode = false
    /// An effect being dragged on the preview: the overlay draws it live, so the renderer leaves it out.
    @Published var hiddenEffect: UUID? { didSet { if hiddenEffect != oldValue { scheduleRenderRefresh() } } }
    @Published var loopPlayback = false
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published private(set) var outputAspect: CGFloat = 16.0 / 9.0
    /// Playback speed of the preview (negative plays backward), driven by J / K / L.
    @Published private(set) var playbackRate: Float = 1
    /// Full renders the preview at 1920 px; half at 960 px for slower Macs.
    @Published var previewQuality = PreviewQuality.full { didSet { scheduleRenderRefresh() } }

    let player = AVPlayer()
    private(set) var assets: ProjectAssets?
    private(set) var built: BuiltComposition?
    /// The render model the preview is currently showing (for on-preview editing).
    private(set) var renderModel: RenderModel?
    private var cursorPathCache: (key: String, path: CursorPath)?
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private var lastCoalesceKey: String?
    private var lastEditTime = Date.distantPast
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var saveWork: DispatchWorkItem?
    private var renderRefreshPending = false
    private var isSeeking = false
    private var pendingSeek: Double?

    var sourceDuration: Double { max(doc.info.duration, 0.01) }
    var sourceTime: Double { editMap.sourceTime(comp: compTime) }
    var duration: Double { editMap.duration }

    init(folder: URL) throws {
        self.folder = folder
        let doc = try ProjectIO.load(folder: folder)
        self.doc = doc
        let track = ProjectIO.loadCursor(folder: folder)
        cursorTrack = track
        cursorImages = CursorArt.loadImages(folder: folder, track: track)
        keys = ProjectIO.loadKeys(folder: folder)
        editMap = EditMap(clips: doc.clips)
        outputAspect = doc.style.aspect.value(source: CGSize(width: doc.info.pixelWidth, height: doc.info.pixelHeight), padding: doc.style.padding)

        player.actionAtItemEnd = .pause
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 60), queue: .main) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self, !self.isSeeking else { return }
                self.compTime = t.seconds
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, self.loopPlayback, (note.object as? AVPlayerItem) === self.player.currentItem else { return }
                self.seek(comp: 0)
                self.player.rate = max(self.playbackRate, 1)
            }
        }
        statusObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] p, _ in
            let playing = p.timeControlStatus != .paused
            DispatchQueue.main.async { self?.isPlaying = playing }
        }

        Task { await load() }
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }

    private func load() async {
        do {
            let assets = try await ProjectAssets.load(folder: folder, info: doc.info)
            self.assets = assets
            // Keep the document in sync with the real file length.
            if abs(assets.screenDuration - doc.info.duration) > 0.05 {
                doc.info.duration = assets.screenDuration
                if doc.clips.count == 1, let c = doc.clips.first, c.start == 0 {
                    doc.clips[0].end = min(c.end, assets.screenDuration)
                }
                let d = assets.screenDuration
                doc.clips = doc.clips.map { var c = $0; c.end = min(c.end, d); return c }.filter { $0.duration > 0.05 }
                if doc.clips.isEmpty { doc.clips = [Clip(start: 0, end: d)] }
                doc.zooms = doc.zooms.map { var z = $0; z.end = min(z.end, d); return z }.filter { $0.duration > 0.3 }
                doc.effects = doc.effects.map { var e = $0; e.end = min(e.end, d); return e }.filter { $0.duration > 0.2 }
                doc.captions = doc.captions.filter { $0.start < d }.map { var c = $0; c.end = min(c.end, d); return c }
            }
            rebuildComposition()
            isReady = true
            await generateFilmstrip()
            waveform = await Self.loadWaveform(assets: assets, duration: sourceDuration)
        } catch {
            loadError = error.localizedDescription
        }
    }

    // MARK: - Editing

    private var snapshot: Snapshot { Snapshot(doc) }

    func edit(_ scope: EditScope, coalesce key: String? = nil, _ change: (inout ProjectDocument) -> Void) {
        let before = snapshot
        var d = doc
        change(&d)
        let after = Snapshot(d)
        guard after != before else { return }
        let now = Date()
        let coalescing = key != nil && key == lastCoalesceKey && now.timeIntervalSince(lastEditTime) < 1.5
        if !coalescing {
            undoStack.append(before)
            if undoStack.count > 200 { undoStack.removeFirst() }
            redoStack.removeAll()
        }
        lastCoalesceKey = key
        lastEditTime = now
        doc = d
        apply(scope)
        updateUndoState()
        scheduleSave()
    }

    func styleBinding<T>(_ kp: WritableKeyPath<Style, T>, key: String) -> Binding<T> {
        Binding(get: { self.doc.style[keyPath: kp] },
                set: { v in self.edit(.render, coalesce: key) { $0.style[keyPath: kp] = v } })
    }

    func undo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(snapshot)
        restore(prev)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(snapshot)
        restore(next)
    }

    private func restore(_ s: Snapshot) {
        let timelineChanged = s.clips != doc.clips
        doc.name = s.name
        doc.clips = s.clips
        doc.zooms = s.zooms
        doc.style = s.style
        doc.effects = s.effects
        doc.captions = s.captions
        lastCoalesceKey = nil
        if case .zoom(let id) = selection, !doc.zooms.contains(where: { $0.id == id }) { selection = .none }
        if case .clip(let id) = selection, !doc.clips.contains(where: { $0.id == id }) { selection = .none }
        if case .effect(let id) = selection, !doc.effects.contains(where: { $0.id == id }) { selection = .none }
        apply(timelineChanged ? .timeline : .render)
        updateUndoState()
        scheduleSave()
    }

    private func updateUndoState() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    private func apply(_ scope: EditScope) {
        switch scope {
        case .timeline: rebuildComposition()
        case .render: scheduleRenderRefresh()
        case .meta: break
        }
    }

    private func scheduleSave() {
        guard AppSettings.shared.autosave else { return }
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            ProjectIO.save(self.doc, folder: self.folder)
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    func saveNow() {
        saveWork?.cancel()
        ProjectIO.save(doc, folder: folder)
    }

    // MARK: - Rendering pipeline

    private func cursorPath() -> CursorPath? {
        guard !cursorTrack.isEmpty else { return nil }
        let st = doc.style
        let crop = (st.crop?.isFull ?? true) ? CropRect.full : st.crop!
        // Source times for "stop at the end" and "loop", which are measured on the edited video.
        let freeze = st.cursorStopAtEnd > 0.01 ? editMap.sourceTime(comp: max(0, editMap.duration - st.cursorStopAtEnd)) : nil
        let firstSource = editMap.segments.first?.srcStart ?? 0
        let loop = st.loopCursor && editMap.duration > 2
            ? (home: firstSource, from: editMap.sourceTime(comp: editMap.duration - 1.2),
               until: editMap.sourceTime(comp: max(0, editMap.duration - 0.1)))
            : nil
        let key = "\(st.cursorSmoothing)-\(st.hideIdleCursor)-\(doc.info.duration)-\(crop)-\(st.removeCursorShakes)-\(st.cursorShakeThreshold)-\(String(describing: freeze))-\(String(describing: loop))"
        if let c = cursorPathCache, c.key == key { return c.path }
        let p = CursorPath(track: cursorTrack.cropped(crop), duration: doc.info.duration + 1,
                           smoothing: st.cursorSmoothing, hideWhenIdle: st.hideIdleCursor,
                           shakeThreshold: st.removeCursorShakes ? st.cursorShakeThreshold : nil,
                           freezeFrom: freeze, loop: loop)
        cursorPathCache = (key, p)
        return p
    }

    func makeRenderModel(for built: BuiltComposition) -> RenderModel {
        RenderModel(style: doc.style, info: doc.info, editMap: editMap, zooms: doc.zooms,
                    cursorPath: cursorPath(), cursorTrack: cursorTrack, cursorImages: cursorImages,
                    screenTrackID: built.screenTrackID, webcamTrackID: doc.style.camera.visible ? built.webcamTrackID : nil,
                    effects: hiddenEffect.map { id in doc.effects.filter { $0.id != id } } ?? doc.effects,
                    captions: doc.captions, keys: keys)
    }

    private func previewVideoComposition(_ model: RenderModel, built: BuiltComposition) -> AVVideoComposition {
        let size = model.outputSize(longSide: previewQuality.longSide)
        return CompositionBuilder.videoComposition(model: model, renderSize: size, fps: 60, duration: built.duration)
    }

    private func rebuildComposition() {
        guard let assets else { return }
        let keepSource = sourceTime
        editMap = EditMap(clips: doc.clips)
        let built = CompositionBuilder.build(assets: assets, editMap: editMap, style: doc.style)
        self.built = built
        let model = makeRenderModel(for: built)
        renderModel = model
        outputAspect = model.aspect
        let item = AVPlayerItem(asset: built.composition)
        item.videoComposition = previewVideoComposition(model, built: built)
        item.audioMix = built.audioMix
        item.audioTimePitchAlgorithm = .spectral
        player.replaceCurrentItem(with: item)
        seek(comp: editMap.compTime(source: keepSource))
    }

    private func scheduleRenderRefresh() {
        guard !renderRefreshPending else { return }
        renderRefreshPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.renderRefreshPending = false
            self.refreshRender()
        }
    }

    private var renderNudge = false

    private func refreshRender() {
        guard let built, let item = player.currentItem else { return }
        let model = makeRenderModel(for: built)
        renderModel = model
        outputAspect = model.aspect
        item.videoComposition = previewVideoComposition(model, built: built)
        item.audioMix = CompositionBuilder.audioMix(for: built.composition, style: doc.style)
        if !isPlaying {
            // A seek to the exact same time can reuse the old frame, so nudge it to force a fresh render.
            renderNudge.toggle()
            player.seek(to: CMTime(sec: compTime + (renderNudge ? 0.0005 : 0)), toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    // MARK: - Playback

    func togglePlay() {
        if isPlaying {
            player.pause()
        } else {
            if compTime >= duration - 0.05 { seek(comp: 0) }
            if playbackRate <= 0 { playbackRate = 1 }
            player.rate = playbackRate
        }
    }

    /// L: play forward, faster each press. J: play backward, faster each press. K: stop and reset.
    func shuttle(_ direction: Int) {
        if direction == 0 {
            player.pause()
            playbackRate = 1
            return
        }
        var rate = playbackRate
        if direction > 0 {
            rate = (!isPlaying || rate < 0) ? 1 : min(8, rate * 2)
            if compTime >= duration - 0.05 { seek(comp: 0) }
        } else {
            guard player.currentItem?.canPlayReverse == true else { NSSound.beep(); return }
            rate = (!isPlaying || rate > 0) ? -1 : max(-8, rate * 2)
            if compTime < 0.05 { seek(comp: duration) }
        }
        playbackRate = rate
        player.rate = rate
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        if isPlaying { player.rate = rate }
    }

    func seek(comp: Double) {
        let t = clamp(comp, 0, max(0, duration))
        compTime = t
        if isSeeking {
            pendingSeek = t
            return
        }
        isSeeking = true
        player.seek(to: CMTime(sec: t), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isSeeking = false
                if let p = self.pendingSeek {
                    self.pendingSeek = nil
                    self.seek(comp: p)
                }
            }
        }
    }

    func seek(source: Double) {
        seek(comp: editMap.compTime(source: source))
    }

    func step(frames: Int) {
        player.pause()
        seek(comp: compTime + Double(frames) / 60)
    }

    // MARK: - Timeline operations

    func splitAtPlayhead() {
        let t = sourceTime
        guard let idx = doc.clips.firstIndex(where: { t > $0.start + 0.1 && t < $0.end - 0.1 }) else { return }
        edit(.timeline) { d in
            let c = d.clips[idx]
            var a = c, b = c
            a.end = t
            b.id = UUID()
            b.start = t
            d.clips.replaceSubrange(idx...idx, with: [a, b])
        }
        if let b = doc.clips.first(where: { abs($0.start - t) < 0.0001 }) { selection = .clip(b.id) }
    }

    /// X: removes the part of the current clip before the playhead (back to the previous cut).
    func removeSliceBefore() {
        let t = sourceTime
        guard let c = doc.clips.first(where: { t > $0.start + 0.05 && t <= $0.end }) else { NSSound.beep(); return }
        if t >= c.end - 0.05 {
            guard doc.clips.count > 1 else { NSSound.beep(); return }
            edit(.timeline) { $0.clips.removeAll { $0.id == c.id } }
        } else {
            edit(.timeline) { d in
                if let i = d.clips.firstIndex(where: { $0.id == c.id }) { d.clips[i].start = t }
            }
        }
    }

    func deleteSelection() {
        switch selection {
        case .zoom(let id):
            edit(.render) { $0.zooms.removeAll { $0.id == id } }
            selection = .none
        case .clip(let id):
            guard doc.clips.count > 1 else { NSSound.beep(); return }
            edit(.timeline) { $0.clips.removeAll { $0.id == id } }
            selection = .none
        case .effect(let id):
            edit(.render) { $0.effects.removeAll { $0.id == id } }
            selection = .none
        case .none:
            break
        }
    }

    func setClip(_ id: UUID, start: Double? = nil, end: Double? = nil, speed: Double? = nil) {
        edit(.timeline, coalesce: speed != nil ? "speed-\(id)" : nil) { d in
            guard let i = d.clips.firstIndex(where: { $0.id == id }) else { return }
            if let start { d.clips[i].start = start }
            if let end { d.clips[i].end = end }
            if let speed { d.clips[i].speed = speed }
        }
    }

    /// Allowed range for a clip's edges (between its neighbours).
    func clipBounds(_ id: UUID) -> ClosedRange<Double> {
        let sorted = doc.clips.sorted { $0.start < $1.start }
        guard let i = sorted.firstIndex(where: { $0.id == id }) else { return 0...sourceDuration }
        let lo = i > 0 ? sorted[i - 1].end : 0
        let hi = i + 1 < sorted.count ? sorted[i + 1].start : sourceDuration
        return lo...hi
    }

    /// Adds a zoom over a dragged range.
    func addZoom(from a: Double, to b: Double) {
        let start = max(0, min(a, b)), end = min(sourceDuration, max(a, b))
        guard end - start >= 0.4 else { addZoom(at: start); return }
        if doc.zooms.contains(where: { $0.start < end && start < $0.end }) { NSSound.beep(); return }
        let z = ZoomSegment(start: start, end: end, scale: doc.style.defaultZoomScale, mode: .followCursor, isAuto: false)
        edit(.render) { $0.zooms.append(z) }
        selection = .zoom(z.id)
    }

    func addZoom(at source: Double) {
        let sorted = doc.zooms.sorted { $0.start < $1.start }
        if sorted.contains(where: { source >= $0.start && source <= $0.end }) { return }
        let next = sorted.first { $0.start > source }?.start ?? sourceDuration
        let start = max(0, source)
        let end = min(start + 3, next - 0.05, sourceDuration)
        guard end - start >= 0.6 else { NSSound.beep(); return }
        let z = ZoomSegment(start: start, end: end, scale: doc.style.defaultZoomScale, mode: .followCursor,
                            focusX: 0.5, focusY: 0.5, isAuto: false)
        edit(.render) { $0.zooms.append(z) }
        selection = .zoom(z.id)
    }

    func updateZoom(_ id: UUID, coalesce: String? = nil, _ change: (inout ZoomSegment) -> Void) {
        edit(.render, coalesce: coalesce) { d in
            guard let i = d.zooms.firstIndex(where: { $0.id == id }) else { return }
            change(&d.zooms[i])
            d.zooms[i].isAuto = false
        }
    }

    func zoomBounds(_ id: UUID) -> ClosedRange<Double> {
        let sorted = doc.zooms.sorted { $0.start < $1.start }
        guard let i = sorted.firstIndex(where: { $0.id == id }) else { return 0...sourceDuration }
        let lo = i > 0 ? sorted[i - 1].end : 0
        let hi = i + 1 < sorted.count ? sorted[i + 1].start : sourceDuration
        return lo...hi
    }

    func regenerateAutoZooms() {
        let generated = ZoomGenerator.generate(from: cursorTrack.clicks, duration: sourceDuration, scale: doc.style.defaultZoomScale)
        edit(.render) { d in
            let manual = d.zooms.filter { !$0.isAuto }
            let auto = generated.filter { g in !manual.contains { $0.start < g.end && g.start < $0.end } }
            d.zooms = manual + auto
        }
        selection = .none
    }

    func removeAllZooms() {
        edit(.render) { $0.zooms.removeAll() }
        selection = .none
    }

    // MARK: Effects

    func addEffect(_ kind: EffectKind, at source: Double? = nil) {
        let start = clamp(source ?? sourceTime, 0, max(0, sourceDuration - 0.5))
        let length = kind == .text ? 3.0 : (kind.needsCamera ? 4.0 : 3.0)
        var e = EffectSegment(kind: kind, start: start, end: min(sourceDuration, start + length))
        if kind == .text, doc.effects.filter({ $0.kind == .text }).isEmpty { e.text = doc.name }
        // New titles match the look of the last one, so a video's titles stay consistent.
        if kind == .text, let last = doc.effects.last(where: { $0.kind == .text }) { e.titleStyle = last.titleStyle }
        edit(.render) { $0.effects.append(e) }
        selection = .effect(e.id)
    }

    func updateEffect(_ id: UUID, coalesce: String? = nil, _ change: (inout EffectSegment) -> Void) {
        edit(.render, coalesce: coalesce) { d in
            guard let i = d.effects.firstIndex(where: { $0.id == id }) else { return }
            change(&d.effects[i])
        }
    }

    func duplicateEffect(_ id: UUID) {
        guard var e = doc.effects.first(where: { $0.id == id }) else { return }
        e.id = UUID()
        let len = e.duration
        e.start = min(e.end, max(0, sourceDuration - len))
        e.end = min(sourceDuration, e.start + len)
        edit(.render) { $0.effects.append(e) }
        selection = .effect(e.id)
    }

    var selectedEffect: EffectSegment? {
        if case .effect(let id) = selection { return doc.effects.first { $0.id == id } }
        return nil
    }

    // MARK: Smart speed

    enum SmartSpeed { case idle, typing }

    /// Finds quiet stretches (no cursor movement, clicks or keys) or bursts of typing.
    func smartRanges(_ kind: SmartSpeed) -> [(Double, Double)] {
        switch kind {
        case .idle: return ActivityAnalyzer.idleRanges(cursor: cursorTrack, keys: keys, duration: sourceDuration)
        case .typing: return ActivityAnalyzer.typingRanges(keys: keys)
        }
    }

    /// Applies a speed to the given source ranges, or cuts them when `speed` is nil.
    @discardableResult
    func applySmartSpeed(_ kind: SmartSpeed, speed: Double?) -> Int {
        let ranges = smartRanges(kind)
        guard !ranges.isEmpty else { NSSound.beep(); return 0 }
        edit(.timeline) { d in
            d.clips = ClipOps.apply(ranges, to: d.clips, speed: speed)
        }
        selection = .none
        return ranges.count
    }

    func applySpeedToAll(_ speed: Double) {
        edit(.timeline) { d in d.clips = d.clips.map { var c = $0; c.speed = speed; return c } }
    }

    /// The split tool: cuts straight down through the clip, zooms and effects at a source time.
    func cut(at t: Double) {
        let minPiece = 0.15
        let hitsClip = doc.clips.contains { t > $0.start + minPiece && t < $0.end - minPiece }
        let hitsZoom = doc.zooms.contains { t > $0.start + minPiece && t < $0.end - minPiece }
        let hitsEffect = doc.effects.contains { t > $0.start + minPiece && t < $0.end - minPiece }
        guard hitsClip || hitsZoom || hitsEffect else { NSSound.beep(); return }
        edit(.timeline) { d in
            if let i = d.clips.firstIndex(where: { t > $0.start + minPiece && t < $0.end - minPiece }) {
                var a = d.clips[i], b = a
                a.end = t; b.id = UUID(); b.start = t
                d.clips.replaceSubrange(i...i, with: [a, b])
            }
            if let i = d.zooms.firstIndex(where: { t > $0.start + minPiece && t < $0.end - minPiece }) {
                var a = d.zooms[i], b = a
                a.end = t; a.isAuto = false
                b.id = UUID(); b.start = t; b.isAuto = false
                d.zooms.replaceSubrange(i...i, with: [a, b])
            }
            for i in d.effects.indices.reversed() where t > d.effects[i].start + minPiece && t < d.effects[i].end - minPiece {
                var a = d.effects[i], b = a
                a.end = t; b.id = UUID(); b.start = t
                d.effects.replaceSubrange(i...i, with: [a, b])
            }
        }
        selection = .none
    }

    /// Splits the clip under a source time (the blade tool).
    func split(at t: Double) {
        guard let idx = doc.clips.firstIndex(where: { t > $0.start + 0.1 && t < $0.end - 0.1 }) else { NSSound.beep(); return }
        edit(.timeline) { d in
            let c = d.clips[idx]
            var a = c, b = c
            a.end = t
            b.id = UUID()
            b.start = t
            d.clips.replaceSubrange(idx...idx, with: [a, b])
        }
    }

    func resetSpeeds() {
        edit(.timeline) { d in d.clips = d.clips.map { var c = $0; c.speed = 1; return c } }
    }

    // MARK: Captions

    func setCaptions(_ cues: [CaptionCue]) {
        edit(.render) { $0.captions = cues }
    }

    func updateCaption(_ id: UUID, text: String) {
        edit(.render, coalesce: "cap-\(id)") { d in
            guard let i = d.captions.firstIndex(where: { $0.id == id }) else { return }
            d.captions[i].text = text
        }
    }

    func deleteCaption(_ id: UUID) {
        edit(.render) { $0.captions.removeAll { $0.id == id } }
    }

    /// Captions mapped to the edited timeline, as SubRip text.
    func srt() -> String {
        var out = ""
        var n = 1
        for cue in doc.captions.sorted(by: { $0.start < $1.start }) {
            guard let (a, b) = compRange(source: cue.start, cue.end) else { continue }
            out += "\(n)\n\(srtTime(a)) --> \(srtTime(b))\n\(cue.text)\n\n"
            n += 1
        }
        return out
    }

    /// The edited-timeline range covered by a source range (nil if it was cut entirely).
    private func compRange(source a: Double, _ b: Double) -> (Double, Double)? {
        var lo: Double?, hi: Double?
        for seg in editMap.segments {
            let s = max(a, seg.srcStart), e = min(b, seg.srcEnd)
            guard e - s > 0.05 else { continue }
            let cs = seg.compStart + (s - seg.srcStart) / seg.speed
            let ce = seg.compStart + (e - seg.srcStart) / seg.speed
            lo = min(lo ?? cs, cs)
            hi = max(hi ?? ce, ce)
        }
        guard let lo, let hi else { return nil }
        return (lo, hi)
    }

    private func srtTime(_ t: Double) -> String {
        let ms = Int((max(0, t) * 1000).rounded())
        return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, (ms / 60_000) % 60, (ms / 1000) % 60, ms % 1000)
    }

    /// The project's note (not part of undo; saved with the project).
    func setNotes(_ text: String) {
        guard text != doc.notes else { return }
        doc.notes = text
        scheduleSave()
    }

    func rename(_ name: String) {
        edit(.meta, coalesce: "rename") { $0.name = name }
    }

    func applyPreset(_ style: Style) {
        edit(.render) { $0.style = style }
    }

    var selectedZoom: ZoomSegment? {
        if case .zoom(let id) = selection { return doc.zooms.first { $0.id == id } }
        return nil
    }

    var selectedClip: Clip? {
        if case .clip(let id) = selection { return doc.clips.first { $0.id == id } }
        return nil
    }

    // MARK: - Images

    private func generateFilmstrip() async {
        guard let assets else { return }
        let gen = AVAssetImageGenerator(asset: assets.screenAsset)
        gen.maximumSize = CGSize(width: 320, height: 320)
        gen.requestedTimeToleranceBefore = CMTime(sec: 0.5)
        gen.requestedTimeToleranceAfter = CMTime(sec: 0.5)
        let count = 30
        var images: [CGImage] = []
        for i in 0..<count {
            let t = CMTime(sec: sourceDuration * (Double(i) + 0.5) / Double(count))
            if let img = try? await gen.image(at: t).image { images.append(img) }
        }
        filmstrip = images
    }

    /// Peak loudness of system audio and microphone, mixed, in ~1500 bins across the recording.
    nonisolated static func loadWaveform(assets: ProjectAssets, duration: Double) async -> [Float] {
        let bins = 1500
        var peaks = [Float](repeating: 0, count: bins)
        let sources: [(AVAsset, AVAssetTrack)] = [
            assets.systemAudio.map { (assets.screenAsset as AVAsset, $0) },
            assets.mic.flatMap { t in assets.micAsset.map { ($0 as AVAsset, t) } },
        ].compactMap { $0 }
        guard !sources.isEmpty, duration > 0 else { return [] }
        for (asset, track) in sources {
            guard let reader = try? AVAssetReader(asset: asset) else { continue }
            let out = AVAssetReaderTrackOutput(track: track, outputSettings: [
                // 8 kHz mono float is plenty for a waveform (lower rates aren't accepted and raise an exception).
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 8000, AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false,
            ])
            guard reader.canAdd(out) else { continue }
            reader.add(out)
            guard reader.startReading() else { continue }
            while let sb = out.copyNextSampleBuffer(), let block = sb.dataBuffer {
                let start = sb.presentationTimeStamp.seconds
                var length = 0
                var ptr: UnsafeMutablePointer<CChar>?
                guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length,
                                                  dataPointerOut: &ptr) == noErr, let ptr else { continue }
                let count = length / MemoryLayout<Float>.size
                ptr.withMemoryRebound(to: Float.self, capacity: count) { samples in
                    for i in stride(from: 0, to: count, by: 8) {
                        let t = start + Double(i) / 8000
                        let b = Int(t / duration * Double(bins))
                        guard b >= 0 && b < bins else { continue }
                        peaks[b] = max(peaks[b], abs(samples[i]))
                    }
                }
            }
        }
        let top = max(peaks.max() ?? 0, 0.0001)
        return peaks.map { min(1, sqrt($0 / top)) }
    }

    func rawFrame(at source: Double, maxSize: CGFloat = 800) async -> CGImage? {
        guard let assets else { return nil }
        let gen = AVAssetImageGenerator(asset: assets.screenAsset)
        gen.maximumSize = CGSize(width: maxSize, height: maxSize)
        gen.requestedTimeToleranceBefore = CMTime(sec: 0.1)
        gen.requestedTimeToleranceAfter = CMTime(sec: 0.1)
        return try? await gen.image(at: CMTime(sec: source)).image
    }

    /// Writes a styled thumbnail for the library.
    func writeThumbnail() async {
        guard let assets else { return }
        let built = CompositionBuilder.build(assets: assets, editMap: editMap, style: doc.style)
        let model = makeRenderModel(for: built)
        let gen = AVAssetImageGenerator(asset: built.composition)
        gen.videoComposition = CompositionBuilder.videoComposition(model: model, renderSize: model.outputSize(longSide: 640), fps: 30, duration: built.duration)
        gen.maximumSize = CGSize(width: 640, height: 640)
        let t = CMTime(sec: min(1.0, duration / 3))
        if let img = try? await gen.image(at: t).image {
            Thumbnailer.writeJPEG(img, to: folder.appendingPathComponent(ProjectFiles.thumbnail))
        }
    }

    /// Renders the current frame at full quality.
    func currentFrameImage(shortSide: Int = 1440) async -> CGImage? {
        guard let assets else { return nil }
        let built = CompositionBuilder.build(assets: assets, editMap: editMap, style: doc.style)
        let model = makeRenderModel(for: built)
        let size = model.outputSize(shortSide: shortSide)
        let gen = AVAssetImageGenerator(asset: built.composition)
        gen.videoComposition = CompositionBuilder.videoComposition(model: model, renderSize: size, fps: 60, duration: built.duration)
        gen.maximumSize = size
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = .zero
        return try? await gen.image(at: CMTime(sec: min(compTime, max(0, duration - 0.02)))).image
    }

    func exportJob() -> ExportJob? {
        guard let assets else { return nil }
        let built = CompositionBuilder.build(assets: assets, editMap: editMap, style: doc.style)
        return ExportJob(built: built, model: makeRenderModel(for: built))
    }

    private(set) var isTrashed = false
    /// Running caption transcription, cancelled when the window closes.
    var captionTask: Task<Void, Never>?

    func close() {
        player.pause()
        captionTask?.cancel()
        captionTask = nil
        guard !isTrashed else { return }
        saveNow()
        if AppSettings.shared.useLastProjectStyle { PresetStore.shared.setDefault(doc.style) }
    }

    /// Moves the project to the Trash (the window closes).
    /// Returns false (and keeps everything) if the project couldn't be moved to the Trash.
    @discardableResult
    func moveToTrash() -> Bool {
        player.pause()
        do {
            try FileManager.default.trashItem(at: folder, resultingItemURL: nil)
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn't move the project to the Trash"
            alert.runModal()
            return false
        }
        saveWork?.cancel()
        isTrashed = true
        ProjectLibrary.shared.reload()
        return true
    }

    /// Picks up a name changed outside the editor (e.g. renamed from the library).
    func adoptName(_ name: String) {
        doc.name = name
    }
}

private extension EditorModel.Snapshot {
    init(_ d: ProjectDocument) {
        self.init(name: d.name, clips: d.clips, zooms: d.zooms, style: d.style, effects: d.effects, captions: d.captions)
    }
}

/// How sharp the editor preview renders; lower is faster for long 4K projects. Export is always full quality.
enum PreviewQuality: String, CaseIterable, Identifiable {
    case full, half, quarter
    var id: String { rawValue }
    var longSide: Int {
        switch self { case .full: return 1920; case .half: return 960; case .quarter: return 480 }
    }
    var short: String { rawValue.capitalized }
    var label: String {
        switch self { case .full: return "Full"; case .half: return "Half (faster)"; case .quarter: return "Quarter (fastest)" }
    }
    var next: PreviewQuality {
        switch self { case .full: return .half; case .half: return .quarter; case .quarter: return .full }
    }
}
