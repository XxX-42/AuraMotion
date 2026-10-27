import CoreGraphics

/// Visual placement only; never changes the gaze point sent to AX selection.
public enum GazeProjectionLink {
    public static func position(gaze: CGPoint?, candidate: AccessibilityTargetSnapshot?, isCandidate: Bool, enabled: Bool) -> CGPoint? {
        guard enabled else { return nil }
        if isCandidate, let target = candidate {
            let frame = target.frame
            guard !frame.isNull, !frame.isInfinite, frame.width > 0, frame.height > 0,
                  frame.midX.isFinite, frame.midY.isFinite else { return gaze }
            return CGPoint(x: frame.midX, y: frame.midY)
        }
        return gaze
    }
}
