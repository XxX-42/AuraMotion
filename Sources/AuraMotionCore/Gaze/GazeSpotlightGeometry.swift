import CoreGraphics

/// Debug-only spotlight presentation constants, in AppKit points.
public enum ScreenQuadrant: String, Sendable, Equatable {
    case topLeft, topRight, bottomLeft, bottomRight
    public var isLeft: Bool { self == .topLeft || self == .bottomLeft }
    public var isTop: Bool { self == .topLeft || self == .topRight }
}

public enum GazeSpotlightGeometry {
    public static let radius: CGFloat = 500
    public static let highlightOpacity: CGFloat = 0.05
    public static let dimOpacity: CGFloat = 0.20

    /// With four equal rectangular quadrants, reflecting any point across a
    /// midpoint places it at least as close to a circle center on that side.
    /// Thus the quadrant containing the center always has maximal circle
    /// intersection area, including when the circle is clipped by the screen.
    /// On an exact midpoint tie, retain the previous side to avoid flicker.
    public static func largestOverlapQuadrant(center: CGPoint, screen: CGRect, previous: ScreenQuadrant? = nil) -> ScreenQuadrant? {
        guard center.x.isFinite, center.y.isFinite, screen.width.isFinite, screen.height.isFinite,
              screen.minX.isFinite, screen.minY.isFinite, screen.width > 0, screen.height > 0,
              center.x >= screen.minX, center.x <= screen.maxX,
              center.y >= screen.minY, center.y <= screen.maxY else { return nil }
        let left = center.x == screen.midX ? (previous?.isLeft ?? true) : center.x < screen.midX
        let top = center.y == screen.midY ? (previous?.isTop ?? true) : center.y > screen.midY
        switch (left, top) {
        case (true, true): return .topLeft
        case (false, true): return .topRight
        case (true, false): return .bottomLeft
        case (false, false): return .bottomRight
        }
    }
    public static func quadrantRect(_ quadrant: ScreenQuadrant, screen: CGRect) -> CGRect {
        CGRect(x: quadrant.isLeft ? screen.minX : screen.midX,
               y: quadrant.isTop ? screen.midY : screen.minY,
               width: screen.width / 2, height: screen.height / 2)
    }
    public static func circle(center: CGPoint) -> CGRect? {
        guard center.x.isFinite, center.y.isFinite else { return nil }
        return CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }
}
