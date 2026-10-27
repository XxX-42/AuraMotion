import Foundation
import CoreGraphics

/// A direction-only experimental mapping; it does not establish a physical ray.
public struct HeadBoundaryCalibration: Codable, Equatable, Sendable {
    public enum Edge: String, CaseIterable, Sendable { case left, right, top, bottom }
    public var left: Float?
    public var right: Float?
    public var top: Float?
    public var bottom: Float?
    public init() {}

    public func value(for edge: Edge) -> Float? {
        switch edge { case .left: left; case .right: right; case .top: top; case .bottom: bottom }
    }
    /// Returns false without changing an existing sample when opposing directions are indistinguishable.
    public mutating func record(_ edge: Edge, yaw: Float, pitch: Float) -> Bool {
        let value = (edge == .left || edge == .right) ? yaw : pitch
        guard value.isFinite else { return false }
        let opposite: Float?
        switch edge { case .left: opposite = right; case .right: opposite = left; case .top: opposite = bottom; case .bottom: opposite = top }
        guard opposite.map({ abs($0 - value) >= 0.02 }) ?? true else { return false }
        switch edge { case .left: left = value; case .right: right = value; case .top: top = value; case .bottom: bottom = value }
        return true
    }
    /// Uncalibrated axes retain the existing approximation until both edges are recorded.
    public func project(pose: HeadPose, mirrored: Bool, display: CGRect) -> CGPoint? {
        guard var point = HeadDirectionProjection.approximate(pose: pose, mirrored: mirrored, display: display) else { return nil }
        if let left, let right, abs(right - left) >= 0.02 {
            point.x = display.minX + CGFloat((pose.yaw - left) / (right - left)) * display.width
        }
        if let top, let bottom, abs(bottom - top) >= 0.02 {
            point.y = display.minY + CGFloat((pose.pitch - top) / (bottom - top)) * display.height
        }
        guard point.x.isFinite, point.y.isFinite else { return nil }
        return point
    }
}
