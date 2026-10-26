import Foundation
import CoreGraphics

/// Reprojects absolute hand motion onto a cursor anchor without changing the
/// legacy absolute CoordinateMapper. The first hand sample after every rebase
/// only establishes the hand anchor, so resuming control cannot teleport the
/// visible pointer.
public struct RelativePointerMapping: Sendable {
    public private(set) var handAnchor: CGPoint?
    public private(set) var cursorAnchor: CGPoint?
    public private(set) var lastHandDelta: CGPoint = .zero
    public private(set) var lastCursorDelta: CGPoint = .zero
    public private(set) var isFrozen = true

    private var lastMappedCursor: CGPoint?

    public init() {}

    /// Stops applying hand movement and remembers the last visible cursor point.
    public mutating func freeze(at cursorPosition: CGPoint?) {
        if let cursorPosition, cursorPosition.x.isFinite, cursorPosition.y.isFinite {
            cursorAnchor = cursorPosition
            lastMappedCursor = cursorPosition
        }
        handAnchor = nil
        lastHandDelta = .zero
        lastCursorDelta = .zero
        isFrozen = true
    }

    /// Begins a new hand-to-cursor mapping at the next hand sample.
    public mutating func rebase(to cursorPosition: CGPoint?) {
        if let cursorPosition, cursorPosition.x.isFinite, cursorPosition.y.isFinite {
            cursorAnchor = cursorPosition
            lastMappedCursor = cursorPosition
        }
        handAnchor = nil
        lastHandDelta = .zero
        lastCursorDelta = .zero
        isFrozen = false
    }

    public mutating func reset() {
        handAnchor = nil
        cursorAnchor = nil
        lastMappedCursor = nil
        lastHandDelta = .zero
        lastCursorDelta = .zero
        isFrozen = true
    }

    /// Maps a Quartz-space hand target to a cursor position. Deltas are clamped
    /// to the configured display bounds while the hand anchor remains stable.
    public mutating func map(
        target: CGPoint,
        currentCursor: CGPoint?,
        displayBounds: CGRect
    ) -> CGPoint? {
        guard target.x.isFinite, target.y.isFinite else { return nil }

        if isFrozen {
            return cursorAnchor ?? currentCursor
        }

        guard let handAnchor else {
            self.handAnchor = target
            let initialCursor = valid(currentCursor) ?? cursorAnchor ?? target
            cursorAnchor = clamp(initialCursor, to: displayBounds)
            lastMappedCursor = cursorAnchor
            lastHandDelta = .zero
            lastCursorDelta = .zero
            return cursorAnchor
        }

        let handDelta = CGPoint(x: target.x - handAnchor.x, y: target.y - handAnchor.y)
        let anchor = valid(cursorAnchor) ?? valid(currentCursor) ?? target
        let mapped = clamp(CGPoint(x: anchor.x + handDelta.x, y: anchor.y + handDelta.y), to: displayBounds)
        let previous = lastMappedCursor ?? anchor
        lastHandDelta = handDelta
        lastCursorDelta = CGPoint(x: mapped.x - previous.x, y: mapped.y - previous.y)
        lastMappedCursor = mapped
        return mapped
    }

    private func valid(_ point: CGPoint?) -> CGPoint? {
        guard let point, point.x.isFinite, point.y.isFinite else { return nil }
        return point
    }

    private func clamp(_ point: CGPoint, to bounds: CGRect) -> CGPoint {
        let x = min(max(point.x, bounds.minX), bounds.maxX)
        let y = min(max(point.y, bounds.minY), bounds.maxY)
        return CGPoint(x: x, y: y)
    }
}

/// Translation used only while switching from a rebased experiment mapping
/// back to the upstream absolute mapping. It preserves cursor continuity while
/// the baseline filter and deadzone resume unchanged.
struct CursorMappingTransitionBias: Sendable {
    private(set) var translation: CGPoint?

    var isActive: Bool { translation != nil }

    mutating func align(cursorPosition: CGPoint?, absoluteTarget: CGPoint?) {
        guard let cursor = valid(cursorPosition), let target = valid(absoluteTarget) else { return }
        translation = CGPoint(x: cursor.x - target.x, y: cursor.y - target.y)
    }

    mutating func clear() {
        translation = nil
    }

    func apply(to point: CGPoint) -> CGPoint {
        guard let translation else { return point }
        return CGPoint(x: point.x + translation.x, y: point.y + translation.y)
    }

    private func valid(_ point: CGPoint?) -> CGPoint? {
        guard let point, point.x.isFinite, point.y.isFinite else { return nil }
        return point
    }
}
