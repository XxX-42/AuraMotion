import Foundation

/// Maintains identity independently of the gaze pixel. Retained identities are
/// display-only until the same target is confirmed by a fresh AX query.
public struct SemanticTargetStabilizer<ID: Equatable> {
    public enum State: Equatable { case unavailable, candidate(ID), retained(ID), focused(ID) }
    public var acquireDwell: TimeInterval = 0.125
    public var switchDwell: TimeInterval = 0.150
    public var exitDwell: TimeInterval = 0.250
    public var maximumObservationGap: TimeInterval = 0.350
    public var confirmationFreshness: TimeInterval = 0.400
    private var current: ID?
    private var pending: ID?
    private var pendingSince: TimeInterval?
    private var pendingLast: TimeInterval?
    private var outsideSince: TimeInterval?
    private var lastConfirmation: TimeInterval?
    private var actionReady = false
    private var wasInAcquire = true
    public init() {}
    public mutating func reset() { current = nil; pending = nil; pendingSince = nil; pendingLast = nil; outsideSince = nil; lastConfirmation = nil; actionReady = false; wasInAcquire = true }
    private mutating func clearPending() { pending = nil; pendingSince = nil; pendingLast = nil }
    private mutating func observePending(_ id: ID, now: TimeInterval, dwell: TimeInterval) -> Bool {
        if pending != id || pendingLast == nil || now < pendingLast! || now - pendingLast! > maximumObservationGap {
            pending = id; pendingSince = now
        }
        pendingLast = now
        return now - (pendingSince ?? now) >= dwell
    }
    private mutating func expire(now: TimeInterval) {
        if let outsideSince, now - outsideSince >= exitDwell { reset(); return }
        if let lastConfirmation, now - lastConfirmation >= confirmationFreshness { reset(); return }
    }
    /// Called for each latest gaze observation, including missing/stale input.
    @discardableResult public mutating func observeGaze(valid: Bool, inRetention: Bool, inAcquire: Bool = true, now: TimeInterval) -> State {
        guard now.isFinite else { reset(); return .unavailable }
        if current != nil {
            if !valid || !inRetention {
                actionReady = false
                if outsideSince == nil { outsideSince = now }
            } else {
                outsideSince = nil
                // Crossing the acquisition boundary retains identity but
                // requires an AX confirmation at the new gaze location.
                if !inAcquire && wasInAcquire { actionReady = false }
                wasInAcquire = inAcquire
            }
        } else if !valid { clearPending() }
        expire(now: now)
        return state
    }
    /// Called only after a completed, fresh AX discovery. A missing/competing
    /// result makes the retained target non-actionable immediately.
    @discardableResult public mutating func observeBest(_ best: ID?, inRetention: Bool, now: TimeInterval) -> State {
        guard now.isFinite else { reset(); return .unavailable }
        expire(now: now)
        guard let best else { actionReady = false; clearPending(); return state }
        if let current {
            if current == best && inRetention {
                actionReady = true; lastConfirmation = now; clearPending(); return state
            }
            actionReady = false
            if current != best && observePending(best, now: now, dwell: switchDwell) {
                self.current = best; lastConfirmation = now; actionReady = true; outsideSince = nil; wasInAcquire = true; clearPending()
            }
            return state
        }
        if observePending(best, now: now, dwell: acquireDwell) {
            current = best; lastConfirmation = now; actionReady = true; outsideSince = nil; wasInAcquire = true; clearPending()
        }
        return state
    }
    public var state: State {
        if let current { return actionReady ? .focused(current) : .retained(current) }
        if let pending { return .candidate(pending) }
        return .unavailable
    }
}
