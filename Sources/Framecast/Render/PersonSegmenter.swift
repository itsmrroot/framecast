import Foundation
import CoreImage
import Vision

/// Separates the person from the background in webcam frames (for background blur / removal).
final class PersonSegmenter: @unchecked Sendable {
    private let lock = NSLock()
    private let request: VNGeneratePersonSegmentationRequest = {
        let r = VNGeneratePersonSegmentationRequest()
        r.qualityLevel = .balanced
        r.outputPixelFormat = kCVPixelFormatType_OneComponent8
        return r
    }()
    private let handler = VNSequenceRequestHandler()

    /// Returns a mask (white = person) scaled to the image's extent, or nil if segmentation failed.
    func mask(for image: CIImage) -> CIImage? {
        lock.lock()
        defer { lock.unlock() }
        let input = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        do {
            try handler.perform([request], on: input)
        } catch {
            return nil
        }
        guard let buffer = request.results?.first?.pixelBuffer else { return nil }
        let mask = CIImage(cvPixelBuffer: buffer)
        let sx = image.extent.width / mask.extent.width
        let sy = image.extent.height / mask.extent.height
        return mask
            .transformed(by: CGAffineTransform(scaleX: sx, y: sy))
            .transformed(by: CGAffineTransform(translationX: image.extent.minX, y: image.extent.minY))
    }
}
