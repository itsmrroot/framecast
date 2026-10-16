import Foundation
import CoreImage
import Vision

/// Separates the person from the background in webcam frames (for background blur / removal).
/// Each frame is segmented on its own: preview, export and thumbnails render different frames at the
/// same time, so a shared stateful sequence would mix their masks.
final class PersonSegmenter: @unchecked Sendable {
    /// Returns a mask (white = person) scaled to the image's extent, or nil if segmentation failed.
    func mask(for image: CIImage) -> CIImage? {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        let input = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        do {
            try VNImageRequestHandler(ciImage: input).perform([request])
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
