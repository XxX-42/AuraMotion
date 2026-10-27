import Foundation
import CoreGraphics

/// One-euro filter for debug gaze in display-normalized coordinates. Its output
/// feeds the marker and semantic targeting; calibration and hand pointer stay unchanged.
public struct DebugGazeStabilizer {
    private var point: CGPoint?
    private var previousInput: CGPoint?
    private var velocity = CGPoint.zero
    private var timestamp: TimeInterval?
    // Webcam noise can look like fast movement, so avoid amplifying its velocity.
    private let minCutoff: Double = 0.8
    private let speedGain: Double = 0.6
    private let velocityCutoff: Double = 1.0
    private let maxGap: TimeInterval = 0.5

    public init() {}

    public mutating func reset() {
        point = nil; previousInput = nil; velocity = .zero; timestamp = nil
    }

    public mutating func update(_ input: CGPoint, timestamp time: TimeInterval) -> CGPoint? {
        guard input.x.isFinite, input.y.isFinite, time.isFinite else { reset(); return nil }
        guard let lastTime = timestamp, let previous = previousInput, let filtered = point else {
            timestamp = time; previousInput = input; point = input; return input
        }
        let dt = time - lastTime
        guard dt > 0, dt <= maxGap else {
            reset(); timestamp = time; previousInput = input; point = input; return input
        }
        func alpha(_ cutoff: Double) -> Double {
            let tau = 1 / (2 * Double.pi * cutoff)
            return dt / (dt + tau)
        }
        let speedAlpha = alpha(velocityCutoff)
        let rawVelocity = CGPoint(x: (input.x - previous.x) / dt, y: (input.y - previous.y) / dt)
        velocity.x += speedAlpha * (rawVelocity.x - velocity.x)
        velocity.y += speedAlpha * (rawVelocity.y - velocity.y)
        let gain = alpha(minCutoff + speedGain * hypot(velocity.x, velocity.y))
        let result = CGPoint(x: filtered.x + gain * (input.x - filtered.x),
                             y: filtered.y + gain * (input.y - filtered.y))
        timestamp = time; previousInput = input; point = result
        return result
    }
}
