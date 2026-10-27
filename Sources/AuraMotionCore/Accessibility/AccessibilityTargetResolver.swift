#if DEBUG
import Foundation
import ApplicationServices
import CoreGraphics
import QuartzCore

/// Bounded point queries on a dedicated queue. No AX tree traversal or mouse synthesis.
public final class AccessibilityTargetResolver: @unchecked Sendable {
    public static let shared = AccessibilityTargetResolver()
    public static let notification = Notification.Name("AuraMotionSemanticTarget")
    private struct Identity: Equatable {
        let element: AXUIElement
        static func == (lhs: Identity, rhs: Identity) -> Bool { CFEqual(lhs.element, rhs.element) }
    }
    private struct Target { let element: AXUIElement; let snapshot: AccessibilityTargetSnapshot; let score: Double; let gaze: CGPoint; let time: TimeInterval }
    private let queue = DispatchQueue(label: "com.auramotion.semantic-ax", qos: .userInitiated)
    private let lock = NSLock()
    private var enabled = false, resolving = false, suspended = false, generation: UInt64 = 0
    private var excludedFrames: [CGRect] = []
    private var lastQuery: TimeInterval = 0
    private var lastLoggedState = ""
    private var focus: Target?, locked: Target?, lastVisible: Target?
    private var stabilizer = SemanticTargetStabilizer<Identity>()
    private var latestGaze: CGPoint?
    private var latestGazeTime: TimeInterval = 0
    private var wasOutsideRetention = false
    private var contactInputLostAt: TimeInterval?
    private var latch = SemanticPinchLatch<Identity>()
    private var contact: Bool { latch.isContactActive }
    private var suppressUntilRelease = false
    private let config = AccessibilityTargetScoringConfiguration()
    private let roles = Set(["AXButton", "AXLink", "AXCheckBox", "AXTextField", "AXSlider", "AXMenuItem"])
    private let pressRoles = Set(["AXButton", "AXLink", "AXCheckBox", "AXMenuItem"])
    public var isEnabled: Bool { lock.lock(); defer { lock.unlock() }; return enabled }
    public var shouldConsumePinch: Bool { lock.lock(); defer { lock.unlock() }; return enabled || suppressUntilRelease }
    public func setEnabled(_ value: Bool) {
        lock.lock(); if !value && contact { suppressUntilRelease = true }; enabled = value; generation &+= 1; focus = nil; locked = nil; lastVisible = nil; stabilizer.reset(); if !suppressUntilRelease { latch.end() } else { latch.invalidate() }; lock.unlock()
        publish(nil, state: value ? (AXIsProcessTrusted() ? "等待注视" : "Permission Missing") : "OFF")
    }
    /// Exclude this app's interactive windows from system hit testing: macOS
    /// may otherwise re-enter our own SwiftUI accessibility tree off-main.
    public func setExcludedFrames(_ frames: [CGRect]) {
        lock.lock(); excludedFrames = frames; lock.unlock()
    }
    public func setSuspended(_ value: Bool) {
        lock.lock(); suspended = value; generation &+= 1
        if value { focus = nil; locked = nil; lastVisible = nil; latestGaze = nil; stabilizer.reset(); latch.invalidate() }
        lock.unlock()
        if value { publish(nil, state: "校准窗口开启") }
    }
    /// Resolve a fresh, smoothed gaze point before stabilizing target identity.
    public func update(_ gazePoint: CGPoint?, timestamp: TimeInterval, diagnosticReason: String? = nil) {
        lock.lock()
        guard enabled && !suspended else { lock.unlock(); return }
        guard AXIsProcessTrusted() else { focus = nil; locked = nil; lastVisible = nil; stabilizer.reset(); latch.invalidate(); lock.unlock(); publish(nil, state: "Permission Missing"); return }
        let now = CACurrentMediaTime()
        guard let gaze = gazePoint, gaze.x.isFinite, gaze.y.isFinite, timestamp.isFinite,
              now >= timestamp, now - timestamp < 0.4 else {
            latestGaze = nil; generation &+= 1
            if contact {
                if contactInputLostAt == nil { contactInputLostAt = now }
                if let lost = contactInputLostAt, now - lost >= 0.25 { locked = nil; latch.invalidate(); generation &+= 1 }
                let keep = locked; lock.unlock(); publish(keep, state: keep == nil ? "注视失效" : "locked"); return
            }
            let state = stabilizer.observeGaze(valid: false, inRetention: false, now: now)
            let target = apply(state: state, best: nil)
            lock.unlock(); publish(target.0, state: target.1); return
        }
        latestGaze = gaze; latestGazeTime = timestamp; contactInputLostAt = nil
        if contact { lock.unlock(); return }
        let inRetention = focus.map { AccessibilityTargetScorer.visualRetentionFrame($0.snapshot.frame, config: config).contains(gaze) } ?? false
        let inAcquire = focus.map { AccessibilityTargetScorer.effectiveFrame($0.snapshot.frame, config: config).contains(gaze) } ?? false
        let outside = focus != nil && !inRetention
        if outside && !wasOutsideRetention { generation &+= 1 }
        wasOutsideRetention = outside
        let before = stabilizer.state
        let gazeState = stabilizer.observeGaze(valid: true, inRetention: inRetention, inAcquire: inAcquire, now: now)
        let changed = before != gazeState
        let visual = apply(state: gazeState, best: nil)
        guard !resolving, now - lastQuery >= 0.1 else {
            lock.unlock(); if changed { publish(visual.0, state: visual.1) }; return
        }
        resolving = true; lastQuery = now; let token = generation; let previous = focus ?? lastVisible; let previousIsFocused = focus != nil; let excluded = excludedFrames; lock.unlock()
        if changed { publish(visual.0, state: visual.1) }
        queue.async { [self] in
            let candidates = discover(gaze: gaze, now: timestamp, previous: previous, previousIsFocused: previousIsFocused, excluded: excluded, token: token)
            lock.lock(); resolving = false
            guard enabled, !suspended, !contact, generation == token, AXIsProcessTrusted(),
                  CACurrentMediaTime() - timestamp < 0.4,
                  let currentGaze = latestGaze, CACurrentMediaTime() - latestGazeTime < 0.4 else { lock.unlock(); return }
            // Re-score against the latest gaze, not the older query frame.
            let rescored: [Target] = candidates.compactMap { candidate in
                let current = focus.map { CFEqual($0.element, candidate.element) } ?? false
                guard let score = AccessibilityTargetScorer.score(candidate.snapshot, gaze: currentGaze, current: current, config: config) else { return nil }
                return Target(element: candidate.element, snapshot: candidate.snapshot, score: score, gaze: currentGaze, time: latestGazeTime)
            }
            var best = rescored.max { $0.score < $1.score }
            if let previous = focus, let old = rescored.first(where: { CFEqual($0.element, previous.element) }), let candidate = best,
               !CFEqual(candidate.element, old.element), candidate.score <= old.score + config.switchThreshold { best = old }
            let inside = focus.map { AccessibilityTargetScorer.visualRetentionFrame($0.snapshot.frame, config: config).contains(currentGaze) } ?? false
            let state = stabilizer.observeBest(best.map { Identity(element: $0.element) }, inRetention: inside, now: CACurrentMediaTime())
            let visual = apply(state: state, best: best)
            lock.unlock(); publish(visual.0, state: visual.1)
        }
    }
    /// Must be called under lock. A retained identity is never actionable.
    private func apply(state: SemanticTargetStabilizer<Identity>.State, best: Target?) -> (Target?, String) {
        switch state {
        case .unavailable:
            focus = nil; lastVisible = nil; return (nil, "无目标")
        case .candidate(let identity):
            focus = nil
            if let best, CFEqual(best.element, identity.element) { lastVisible = best }
            guard let candidate = lastVisible, CFEqual(candidate.element, identity.element),
                  let gaze = latestGaze,
                  AccessibilityTargetScorer.effectiveFrame(candidate.snapshot.frame, config: config).contains(gaze) else {
                lastVisible = nil; stabilizer.reset(); return (nil, "无目标")
            }
            return (candidate, "candidate")
        case .retained(let identity):
            guard let current = focus, CFEqual(current.element, identity.element) else { focus = nil; return (nil, "无目标") }
            return (current, "retained · 等待重新确认")
        case .focused(let identity):
            if let best, CFEqual(best.element, identity.element) { focus = best; lastVisible = best }
            guard let current = focus, CFEqual(current.element, identity.element) else { return (nil, "无目标") }
            return (current, "focused")
        }
    }
    public func beginPinch() {
        lock.lock(); guard enabled, !contact else { lock.unlock(); return }
        if case .focused = stabilizer.state, let f = focus, CACurrentMediaTime() - f.time < 0.4, AXIsProcessTrusted() { locked = f } else { locked = nil }
        latch.begin(locked.map { Identity(element: $0.element) })
        let selected = locked; lock.unlock(); publish(selected, state: selected == nil ? "pinch 无目标" : "locked")
    }
    public func endPinch() {
        lock.lock(); guard contact else { lock.unlock(); return }
        latch.end(); contactInputLostAt = nil; locked = nil; focus = nil; lastVisible = nil; latestGaze = nil; wasOutsideRetention = false; stabilizer.reset(); suppressUntilRelease = false; lock.unlock()
        publish(nil, state: "捏合结束")
    }
    /// Called only for a confirmed pinch; semantic mode never falls back to mouse click.
    public func confirmPinch(allowed: @escaping @Sendable () -> Bool) {
        lock.lock(); guard enabled, contact else { lock.unlock(); return }
        guard let identity = latch.takeAction(), let target = locked,
              CFEqual(identity.element, target.element) else {
            lock.unlock(); publish(nil, state: "无可执行 AXPress"); return
        }
        let token = generation; lock.unlock()
        guard AXIsProcessTrusted() else {
            lock.lock(); locked = nil; latch.invalidate(); lock.unlock()
            publish(nil, state: "Permission Missing"); return
        }
        guard allowed(), target.snapshot.supportsPress, pressRoles.contains(target.snapshot.role) else {
            publish(target, state: "locked · 无可执行 AXPress"); return
        }
        let confirmedAt = CACurrentMediaTime()
        queue.async { [self] in
            lock.lock(); let valid = enabled && generation == token; lock.unlock()
            guard valid, allowed(), CACurrentMediaTime() - confirmedAt < 0.8, AXIsProcessTrusted(),
                  let current = snapshot(target.element), current.supportsPress,
                  current.role == target.snapshot.role, current.frame == target.snapshot.frame else { publish(nil, state: "目标失效"); return }
            let result = AXUIElementPerformAction(target.element, kAXPressAction as CFString)
            lock.lock()
            let stillLocked = enabled && contact && locked.map { CFEqual($0.element, target.element) } == true
            lock.unlock()
            let message = result == .success ? "AXPress 成功" : "AXPress 失败 (\(result.rawValue))"
            publish(stillLocked ? target : nil, state: stillLocked ? "locked · \(message)" : message)
        }
    }
    private func discover(gaze: CGPoint, now: TimeInterval, previous: Target?, previousIsFocused: Bool, excluded: [CGRect], token: UInt64) -> [Target] {
        // Recheck the known element at its actual center when it remains
        // eligible. Hit-testing that point still verifies it is frontmost.
        let recheckFrame = previous.flatMap { target in
            AccessibilityTargetScorer.score(target.snapshot, gaze: gaze, current: previousIsFocused, config: config) == nil ? nil : target.snapshot.frame
        }
        let points = AccessibilityTargetSampling.points(gaze: gaze, recheckFrame: recheckFrame)
        let system = AXUIElementCreateSystemWide(); AXUIElementSetMessagingTimeout(system, 0.12); var results: [Target] = []
        for point in points {
            lock.lock(); let active = enabled && !suspended && generation == token; lock.unlock()
            guard active else { break }
            guard !excluded.contains(where: { $0.contains(point) }) else { continue }
            var element: AXUIElement?
            guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &element) == .success, let hit = element else { continue }
            // One parent lookup handles text nested inside a native button/link;
            // never recurse or enumerate children.
            var candidate = hit
            var value = snapshot(hit)
            if value == nil {
                var parent: CFTypeRef?
                if AXUIElementCopyAttributeValue(hit, kAXParentAttribute as CFString, &parent) == .success,
                   let parent, CFGetTypeID(parent) == AXUIElementGetTypeID() {
                    candidate = parent as! AXUIElement; value = snapshot(candidate)
                }
            }
            guard !results.contains(where: { CFEqual($0.element, candidate) }), let value,
                  let score = AccessibilityTargetScorer.score(value, gaze: gaze, current: previousIsFocused && (previous.map { CFEqual($0.element, candidate) } ?? false), config: config) else { continue }
            results.append(Target(element: candidate, snapshot: value, score: score, gaze: gaze, time: now))
        }
        return results
    }
    private func snapshot(_ element: AXUIElement) -> AccessibilityTargetSnapshot? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid != getpid() else { return nil }
        AXUIElementSetMessagingTimeout(element, 0.12)
        func attribute(_ key: CFString) -> CFTypeRef? { var value: CFTypeRef?; return AXUIElementCopyAttributeValue(element, key, &value) == .success ? value : nil }
        guard let role = attribute(kAXRoleAttribute as CFString) as? String, roles.contains(role),
              let p = attribute(kAXPositionAttribute as CFString), CFGetTypeID(p) == AXValueGetTypeID(),
              let s = attribute(kAXSizeAttribute as CFString), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &origin), AXValueGetValue(s as! AXValue, .cgSize, &size),
              origin.x.isFinite, origin.y.isFinite, size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else { return nil }
        let screen = CGDisplayBounds(CGMainDisplayID())
        guard size.width < screen.width * 0.75, size.height < screen.height * 0.75 else { return nil }
        if let enabledValue = attribute(kAXEnabledAttribute as CFString) as? Bool, !enabledValue { return nil }
        var actions: CFArray?; let supports = AXUIElementCopyActionNames(element, &actions) == .success && ((actions as? [String]) ?? []).contains(kAXPressAction as String)
        return AccessibilityTargetSnapshot(role: role, frame: CGRect(origin: origin, size: size), title: attribute(kAXTitleAttribute as CFString) as? String, supportsPress: supports)
    }
    private func publish(_ target: Target?, state: String) {
        // Local debug transition log only: no titles, target IDs, gaze
        // coordinates, screenshots, or camera frames are persisted.
        lock.lock(); let changed = lastLoggedState != state; lastLoggedState = state; lock.unlock()
        if changed { NSLog("AX targeting state: %@ (target %@)", state, target == nil ? "absent" : "present") }
        var info: [String: Any] = ["state": state]
        if let target { info["target"] = target.snapshot; info["score"] = target.score; info["gaze"] = target.gaze; info["distance"] = AccessibilityTargetScorer.frameDistance(target.snapshot.frame, point: target.gaze) }
        DispatchQueue.main.async { NotificationCenter.default.post(name: Self.notification, object: nil, userInfo: info) }
    }
}
#endif
