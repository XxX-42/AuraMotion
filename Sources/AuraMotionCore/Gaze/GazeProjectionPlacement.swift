import Foundation
import CoreGraphics

/// Converts a Quartz global gaze position into an AppKit panel frame.
public enum GazeProjectionPlacement {
    /// Clamp a finite normalized display point without inventing a gaze value.
    public static func clampedNormalized(_ point: CGPoint) -> CGPoint? {
        guard point.x.isFinite, point.y.isFinite else { return nil }
        return CGPoint(x: max(0, min(1, point.x)), y: max(0, min(1, point.y)))
    }
    public static func panelFrame(point: CGPoint, quartzDisplay: CGRect, appKitDisplay: CGRect, size: CGFloat) -> CGRect? {
        guard point.x.isFinite, point.y.isFinite, size.isFinite, size > 0,
              quartzDisplay.width > 0, quartzDisplay.height > 0,
              appKitDisplay.width >= size, appKitDisplay.height >= size else { return nil }
        let x = appKitDisplay.minX + point.x - quartzDisplay.minX
        let y = appKitDisplay.maxY - (point.y - quartzDisplay.minY)
        let left = max(appKitDisplay.minX, min(appKitDisplay.maxX - size, x - size / 2))
        let bottom = max(appKitDisplay.minY, min(appKitDisplay.maxY - size, y - size / 2))
        return CGRect(x: left, y: bottom, width: size, height: size)
    }
}

/// Retains only the last visible marker when tracking is temporarily absent.
/// The retained location is visual-only and never participates in AX targeting.
public struct GazeProjectionVisibility {
    private var last: CGPoint?
    public init() {}
    public mutating func update(_ point: CGPoint?, enabled: Bool) -> (point: CGPoint?, stale: Bool) {
        guard enabled else { last = nil; return (nil, false) }
        if let point, point.x.isFinite, point.y.isFinite { last = point; return (point, false) }
        return (last, last != nil)
    }
}
