import Foundation
import CoreGraphics

public struct AccessibilityTargetSnapshot: Sendable, Equatable {
    public let role: String
    public let frame: CGRect
    public let title: String?
    public let supportsPress: Bool
    public init(role: String, frame: CGRect, title: String?, supportsPress: Bool) {
        self.role = role; self.frame = frame; self.title = title; self.supportsPress = supportsPress
    }
}
public struct AccessibilityTargetScoringConfiguration: Sendable {
    public var horizontalPadding: CGFloat = 40
    public var verticalPadding: CGFloat = 30
    public var insideExpandedBonus: Double = 100
    public var insideFrameBonus: Double = 50
    public var centerDistanceWeight: Double = 0.12
    public var frameDistanceWeight: Double = 1
    public var roleBonus: Double = 5
    public var currentFocusBonus: Double = 15
    public var switchThreshold: Double = 8
    public init() {}
}
public enum AccessibilityTargetScorer {
    public static func effectiveFrame(_ frame: CGRect, config: AccessibilityTargetScoringConfiguration = .init()) -> CGRect {
        frame.insetBy(dx: -config.horizontalPadding, dy: -config.verticalPadding)
    }
    public static func frameDistance(_ frame: CGRect, point: CGPoint) -> CGFloat {
        let x = max(frame.minX - point.x, 0, point.x - frame.maxX)
        let y = max(frame.minY - point.y, 0, point.y - frame.maxY)
        return hypot(x, y)
    }
    public static func score(_ target: AccessibilityTargetSnapshot, gaze: CGPoint, current: Bool, config: AccessibilityTargetScoringConfiguration = .init()) -> Double? {
        let frame = target.frame
        guard effectiveFrame(frame, config: config).contains(gaze) else { return nil }
        let center = hypot(gaze.x - frame.midX, gaze.y - frame.midY)
        let priority = ["AXButton", "AXLink", "AXCheckBox", "AXMenuItem"].contains(target.role) ? config.roleBonus : 0
        return config.insideExpandedBonus + (frame.contains(gaze) ? config.insideFrameBonus : 0)
            - config.frameDistanceWeight * Double(frameDistance(frame, point: gaze))
            - config.centerDistanceWeight * Double(center) + priority + (current ? config.currentFocusBonus : 0)
    }
}
