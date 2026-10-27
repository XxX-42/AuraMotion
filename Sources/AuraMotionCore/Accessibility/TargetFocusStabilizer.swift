import Foundation

/// Debounces semantic target identity, independent of the gaze point's motion.
/// A candidate is not actionable until repeated observations span `dwell`.
public struct TargetFocusStabilizer<ID: Equatable> {
    public enum State: Equatable { case unavailable, candidate(ID), focused(ID) }
    public let dwell: TimeInterval
    public let maximumGap: TimeInterval
    private var candidate: ID?
    private var started: TimeInterval?
    private var last: TimeInterval?
    public init(dwell: TimeInterval = 0.125, maximumGap: TimeInterval = 0.35) {
        self.dwell = dwell; self.maximumGap = maximumGap
    }
    public mutating func reset() { candidate = nil; started = nil; last = nil }
    /// A missed query never yields an actionable focus. Keep identity/dwell
    /// only briefly so a single dropped result does not restart it.
    public mutating func temporarilyMissing(timestamp: TimeInterval, grace: TimeInterval = 0.2) -> State {
        guard let last, let candidate, timestamp.isFinite, timestamp >= last,
              timestamp - last <= grace else { reset(); return .unavailable }
        return .candidate(candidate)
    }
    public mutating func update(_ id: ID?, timestamp: TimeInterval) -> State {
        guard let id, timestamp.isFinite else { reset(); return .unavailable }
        if let last, timestamp <= last || timestamp - last > maximumGap { reset() }
        if candidate != id || started == nil { candidate = id; started = timestamp }
        last = timestamp
        guard let started, timestamp - started >= dwell else { return .candidate(id) }
        return .focused(id)
    }
}
