import CoreGraphics
import Foundation

/// Pure geometry helpers for hand-pose regions of interest.
public enum VisionROI {
    public static let fullFrame = CGRect(x: 0, y: 0, width: 1, height: 1)

    /// Builds a normalized rectangle around already full-image landmark coordinates.
    /// Vision returns `VNRecognizedPoint.location` in normalized coordinates for the
    /// input image, even when request.regionOfInterest narrows the search region.
    public static func expanded(
        around bounds: CGRect,
        scale: Double,
        minimumSize: Double
    ) -> CGRect {
        guard isFinite(bounds), bounds.width >= 0, bounds.height >= 0 else {
            return fullFrame
        }

        let safeScale = scale.isFinite ? max(1, scale) : 1.8
        let safeMinimum = minimumSize.isFinite ? min(1, max(0.01, minimumSize)) : 0.35
        let width = min(1, max(safeMinimum, bounds.width * safeScale))
        let height = min(1, max(safeMinimum, bounds.height * safeScale))
        let centerX = min(1, max(0, bounds.midX))
        let centerY = min(1, max(0, bounds.midY))
        let originX = min(max(0, centerX - width / 2), 1 - width)
        let originY = min(max(0, centerY - height / 2), 1 - height)

        return CGRect(x: originX, y: originY, width: width, height: height)
    }

    /// Returns the full-image normalized bounds of the recognized hand landmarks.
    public static func bounds(of sample: HandSample, isMirrored: Bool = false) -> CGRect? {
        let points = sample.joints.values.compactMap { joint -> CGPoint? in
            guard joint.confidence.isFinite, joint.confidence > 0,
                  joint.position.x.isFinite, joint.position.y.isFinite else {
                return nil
            }
            return CGPoint(
                x: min(1, max(0, isMirrored ? 1 - joint.position.x : joint.position.x)),
                y: min(1, max(0, joint.position.y))
            )
        }

        guard let first = points.first else { return nil }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func isFinite(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite
            && rect.width.isFinite && rect.height.isFinite
    }
}
