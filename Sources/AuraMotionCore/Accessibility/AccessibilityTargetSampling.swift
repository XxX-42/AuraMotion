import CoreGraphics

/// Bounded hit-test positions; one extra point rechecks a known candidate.
public enum AccessibilityTargetSampling {
    public static func points(gaze: CGPoint, recheckFrame: CGRect?) -> [CGPoint] {
        let offsets: [(CGFloat, CGFloat)] = [(0,0),(40,0),(-40,0),(0,40),(0,-40),(55,55),(55,-55),(-55,55),(-55,-55),(90,0),(-90,0),(0,90),(0,-90)]
        var points = offsets.map { CGPoint(x: gaze.x + $0.0, y: gaze.y + $0.1) }
        if let frame = recheckFrame, !frame.isNull, !frame.isInfinite, frame.width > 0, frame.height > 0,
           frame.midX.isFinite, frame.midY.isFinite {
            let center = CGPoint(x: frame.midX, y: frame.midY)
            if !points.contains(center) { points.append(center) }
        }
        return points
    }
}
