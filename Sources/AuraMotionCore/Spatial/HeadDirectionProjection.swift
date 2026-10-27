import CoreGraphics
import Foundation

/// Debug visualization only: assumes a frontal camera and estimated field of view.
/// This is not a calibrated physical head ray or a measurement of gaze.
public enum HeadDirectionProjection {
    public static func approximate(pose: HeadPose, mirrored: Bool, display: CGRect) -> CGPoint? {
        guard let center = HeadReferenceProjector.debugApproximation(pose: pose, isMirrored: mirrored, displayBounds: display),
              pose.yaw.isFinite, pose.pitch.isFinite, abs(pose.yaw) < 1.2, abs(pose.pitch) < 1.2 else { return nil }
        let horizontal = CGFloat(tan(Double(pose.yaw))) * (mirrored ? -1 : 1)
        let vertical = CGFloat(tan(Double(pose.pitch)))
        return CGPoint(x: center.x - horizontal * display.width, y: center.y + vertical * display.height)
    }
}
