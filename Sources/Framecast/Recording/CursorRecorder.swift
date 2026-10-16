import Foundation
import AppKit
import CoreMedia

/// Records cursor position, clicks and cursor shape changes as data, so the cursor can be
/// smoothed, resized and restyled after recording.
final class CursorRecorder: @unchecked Sendable {
    private let clock: RecordingClock
    /// Captured area in global display coordinates (points, top-left origin).
    private let captureRect: CGRect
    private let cursorsDir: URL
    private let queue = DispatchQueue(label: "framecast.cursor", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var shapeTimer: Timer?
    private let lock = NSLock()

    private var track = CursorTrack()
    private var lastPoint: CGPoint?
    private var lastButtons = 0
    private var knownShapes: [String: String] = [:] // image hash -> id
    private var currentShape: String?
    private let arrowHash: String?

    init(clock: RecordingClock, captureRect: CGRect, folder: URL) {
        self.clock = clock
        self.captureRect = captureRect
        cursorsDir = folder.appendingPathComponent(ProjectFiles.cursors, isDirectory: true)
        try? FileManager.default.createDirectory(at: cursorsDir, withIntermediateDirectories: true)
        arrowHash = NSCursor.arrow.image.tiffRepresentation?.fnv1a
    }

    func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: .milliseconds(8), leeway: .milliseconds(1))
        t.setEventHandler { [weak self] in self?.poll() }
        t.resume()
        timer = t

        DispatchQueue.main.async { [self] in
            pollShape()
            let st = Timer(timeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in self?.pollShape() }
            RunLoop.main.add(st, forMode: .common)
            shapeTimer = st
        }
    }

    func stop() -> CursorTrack {
        timer?.cancel()
        timer = nil
        DispatchQueue.main.async { [self] in
            shapeTimer?.invalidate()
            shapeTimer = nil
        }
        return lock.withLock { track }
    }

    private func normalized(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - captureRect.minX) / max(captureRect.width, 1),
                y: (p.y - captureRect.minY) / max(captureRect.height, 1))
    }

    private func poll() {
        guard let t = clock.recordingTime(hostTime: RecordingClock.hostNow),
              let location = CGEvent(source: nil)?.location else { return }
        let p = normalized(location)
        let buttons = NSEvent.pressedMouseButtons

        lock.withLock {
            if lastPoint == nil || abs(lastPoint!.x - p.x) > 0.00001 || abs(lastPoint!.y - p.y) > 0.00001 {
                track.samples.append(CursorSample(t: t, x: p.x, y: p.y))
                lastPoint = p
            }
            for button in 0..<2 {
                let mask = 1 << button
                if buttons & mask != 0 && lastButtons & mask == 0 {
                    track.clicks.append(ClickEvent(t: t, x: p.x, y: p.y, button: button))
                }
            }
            lastButtons = buttons
        }
    }

    /// Runs on the main thread.
    private func pollShape() {
        guard let t = clock.recordingTime(hostTime: RecordingClock.hostNow) else { return }
        guard let cursor = NSCursor.currentSystem else { return }
        let image = cursor.image
        guard let tiff = image.tiffRepresentation else { return }
        let hash = tiff.fnv1a + "-\(Int(cursor.hotSpot.x))x\(Int(cursor.hotSpot.y))"

        let id: String
        if let known = knownShapes[hash] {
            id = known
        } else {
            id = "c\(knownShapes.count)"
            knownShapes[hash] = id
            saveImage(image, id: id)
            let info = CursorShapeInfo(id: id, hotX: cursor.hotSpot.x, hotY: cursor.hotSpot.y,
                                       width: image.size.width, height: image.size.height,
                                       isArrow: tiff.fnv1a == arrowHash)
            lock.withLock { track.shapeInfo[id] = info }
        }
        if id != currentShape {
            currentShape = id
            lock.withLock { track.shapes.append(CursorShapeChange(t: t, id: id)) }
        }
    }

    private func saveImage(_ image: NSImage, id: String) {
        let scale: CGFloat = 4
        let w = Int(image.size.width * scale), h = Int(image.size.height * scale)
        guard w > 0, h > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: cursorsDir.appendingPathComponent("\(id).png"))
        }
    }
}
