import CoreGraphics

/// Debug-only spotlight presentation constants, in AppKit points.
public enum GazeSpotlightGeometry {
    public static let radius: CGFloat = 500
    public static let highlightOpacity: CGFloat = 0.05
    public static let dimOpacity: CGFloat = 0.20

    public static func circle(center: CGPoint) -> CGRect? {
        guard center.x.isFinite, center.y.isFinite else { return nil }
        return CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }
}
