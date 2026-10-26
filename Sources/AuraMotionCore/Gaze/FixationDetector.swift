import Foundation
import CoreGraphics

public enum FixationState: Sendable, Equatable {
    case unavailable
    case candidate(CGPoint)
    case focused(CGPoint)
}

/// Spatial dwell with entry/exit hysteresis. Inputs must be ordered host times.
public struct FixationDetector: Sendable {
    public var dwell: TimeInterval = 0.125
    public var entryRadius: CGFloat = 45
    public var exitRadius: CGFloat = 70
    public var minimumQuality: Float = 0.5
    public var maximumGap: TimeInterval = 0.2
    private var anchor: CGPoint?
    private var started: TimeInterval?
    private var lastTime: TimeInterval?
    private var focused = false
    public init() {}
    public mutating func reset() { anchor = nil; started = nil; lastTime = nil; focused = false }
    public mutating func update(_ gaze: GazeEstimate?) -> FixationState {
        guard let gaze, gaze.timestamp.isFinite, gaze.confidence >= minimumQuality,
              gaze.screenPoint.x.isFinite, gaze.screenPoint.y.isFinite else { reset(); return .unavailable }
        if let lastTime, gaze.timestamp <= lastTime || gaze.timestamp - lastTime > maximumGap { reset() }
        lastTime = gaze.timestamp
        guard let current = anchor, let start = started else {
            anchor = gaze.screenPoint; started = gaze.timestamp
            return .candidate(gaze.screenPoint)
        }
        let distance = hypot(gaze.screenPoint.x - current.x, gaze.screenPoint.y - current.y)
        if distance > (focused ? exitRadius : entryRadius) {
            anchor = gaze.screenPoint; started = gaze.timestamp; focused = false
            return .candidate(gaze.screenPoint)
        }
        if gaze.timestamp - start >= dwell { focused = true }
        return focused ? .focused(current) : .candidate(current)
    }
}
