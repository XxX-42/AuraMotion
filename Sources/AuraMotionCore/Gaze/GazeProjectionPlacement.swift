import Foundation
import CoreGraphics

/// Converts a Quartz global gaze position into an AppKit panel frame.
public enum GazeProjectionPlacement {
    public static func panelFrame(point: CGPoint, quartzDisplay: CGRect, appKitDisplay: CGRect, size: CGFloat) -> CGRect? {
        guard point.x.isFinite, point.y.isFinite, size.isFinite, size > 0,
              quartzDisplay.width > 0, quartzDisplay.height > 0,
              quartzDisplay.contains(point) else { return nil }
        let x = appKitDisplay.minX + point.x - quartzDisplay.minX
        let y = appKitDisplay.maxY - (point.y - quartzDisplay.minY)
        return CGRect(x: x - size / 2, y: y - size / 2, width: size, height: size)
    }
}
