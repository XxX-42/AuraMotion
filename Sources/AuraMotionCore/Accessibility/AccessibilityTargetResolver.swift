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
    private var focus: Target?, locked: Target?, lastVisible: Target?
    private var stabilizer = TargetFocusStabilizer<Identity>()
    private var contact = false, acted = false, suppressUntilRelease = false
    private let config = AccessibilityTargetScoringConfiguration()
    private let roles = Set(["AXButton", "AXLink", "AXCheckBox", "AXTextField", "AXSlider", "AXMenuItem"])
    private let pressRoles = Set(["AXButton", "AXLink", "AXCheckBox", "AXMenuItem"])
    public var isEnabled: Bool { lock.lock(); defer { lock.unlock() }; return enabled }
    public var shouldConsumePinch: Bool { lock.lock(); defer { lock.unlock() }; return enabled || suppressUntilRelease }
    public func setEnabled(_ value: Bool) {
        lock.lock(); if !value && contact { suppressUntilRelease = true }; enabled = value; generation &+= 1; focus = nil; locked = nil; lastVisible = nil; stabilizer.reset(); if !suppressUntilRelease { contact = false }; acted = false; lock.unlock()
        publish(nil, state: value ? (AXIsProcessTrusted() ? "等待注视" : "Permission Missing") : "OFF")
    }
    /// Exclude this app's interactive windows from system hit testing: macOS
    /// may otherwise re-enter our own SwiftUI accessibility tree off-main.
    public func setExcludedFrames(_ frames: [CGRect]) {
        lock.lock(); excludedFrames = frames; lock.unlock()
    }
    public func setSuspended(_ value: Bool) {
        lock.lock(); suspended = value; generation &+= 1
        if value { focus = nil; locked = nil; lastVisible = nil; stabilizer.reset() }
        lock.unlock()
        if value { publish(nil, state: "校准窗口开启") }
    }
    /// Resolve a fresh, smoothed gaze point before stabilizing target identity.
    public func update(_ gazePoint: CGPoint?, timestamp: TimeInterval) {
        lock.lock()
        guard enabled && !suspended else { lock.unlock(); return }
        guard AXIsProcessTrusted() else { focus = nil; locked = nil; lastVisible = nil; stabilizer.reset(); lock.unlock(); publish(nil, state: "Permission Missing"); return }
        guard let gaze = gazePoint, gaze.x.isFinite, gaze.y.isFinite, timestamp.isFinite,
              CACurrentMediaTime() >= timestamp, CACurrentMediaTime() - timestamp < 0.4 else {
            if contact { let keep = locked; lock.unlock(); publish(keep, state: "locked"); return }
            focus = nil; generation &+= 1
            let now = CACurrentMediaTime()
            let preserved: Target?
            if case .candidate = stabilizer.temporarilyMissing(timestamp: now), let visible = lastVisible,
               now >= visible.time, now - visible.time <= 0.2 { preserved = visible }
            else { lastVisible = nil; preserved = nil }
            lock.unlock(); publish(preserved, state: preserved == nil ? "等待有效注视" : "candidate · 短暂保留"); return
        }
        // Never allow a fresh pinch to use a previously focused control when
        // the latest gaze has already left its expanded hit area.
        var invalidated = false
        if !contact, let current = focus, !AccessibilityTargetScorer.effectiveFrame(current.snapshot.frame, config: config).contains(gaze) {
            focus = nil; lastVisible = nil; stabilizer.reset(); generation &+= 1; invalidated = true
        }
        guard !contact, !resolving, CACurrentMediaTime() - lastQuery >= 0.1 else {
            lock.unlock(); if invalidated { publish(nil, state: "等待目标") }; return
        }
        resolving = true; lastQuery = CACurrentMediaTime(); let token = generation; let previous = focus ?? lastVisible; let excluded = excludedFrames; lock.unlock()
        if invalidated { publish(nil, state: "等待目标") }
        queue.async { [self] in
            let candidates = discover(gaze: gaze, now: timestamp, previous: previous, excluded: excluded, token: token)
            lock.lock(); resolving = false
            guard enabled, !suspended, !contact, generation == token, AXIsProcessTrusted(), CACurrentMediaTime() - timestamp < 0.4 else { lock.unlock(); return }
            var best = candidates.max { $0.score < $1.score }
            if let previous, let old = candidates.first(where: { CFEqual($0.element, previous.element) }), let candidate = best,
               !CFEqual(candidate.element, old.element), candidate.score <= old.score + config.switchThreshold { best = old }
            if let best {
                lastVisible = best
                let state = stabilizer.update(Identity(element: best.element), timestamp: timestamp)
                switch state { case .focused: focus = best; default: focus = nil }
                let label: String
                switch state { case .unavailable: label = "无目标"; case .candidate: label = "candidate"; case .focused: label = "focused" }
                lock.unlock(); publish(best, state: label)
            } else {
                focus = nil
                let kept: Target?
                if case .candidate = stabilizer.temporarilyMissing(timestamp: timestamp), let previous,
                   timestamp >= previous.time, timestamp - previous.time <= 0.2,
                   AccessibilityTargetScorer.effectiveFrame(previous.snapshot.frame, config: config).contains(gaze) {
                    kept = previous
                } else { lastVisible = nil; kept = nil }
                lock.unlock(); publish(kept, state: kept == nil ? "无目标" : "candidate · 短暂保留")
            }
        }
    }
    public func beginPinch() {
        lock.lock(); guard enabled, !contact else { lock.unlock(); return }
        contact = true; acted = false
        if let f = focus, CACurrentMediaTime() - f.time < 0.4, AXIsProcessTrusted() { locked = f } else { locked = nil }
        let selected = locked; lock.unlock(); publish(selected, state: selected == nil ? "pinch 无目标" : "locked")
    }
    public func endPinch() {
        lock.lock(); guard contact else { lock.unlock(); return }
        contact = false; locked = nil; focus = nil; lastVisible = nil; stabilizer.reset(); acted = false; suppressUntilRelease = false; lock.unlock()
        publish(nil, state: "等待目标")
    }
    /// Called only for a confirmed pinch; semantic mode never falls back to mouse click.
    public func confirmPinch(allowed: @escaping @Sendable () -> Bool) {
        lock.lock(); guard enabled, contact, !acted else { lock.unlock(); return }
        acted = true; let target = locked; let token = generation; lock.unlock()
        guard allowed(), let target, target.snapshot.supportsPress, pressRoles.contains(target.snapshot.role), AXIsProcessTrusted() else { publish(target, state: "无可执行 AXPress"); return }
        let confirmedAt = CACurrentMediaTime()
        queue.async { [self] in
            lock.lock(); let valid = enabled && generation == token; lock.unlock()
            guard valid, allowed(), CACurrentMediaTime() - confirmedAt < 0.8, AXIsProcessTrusted(),
                  let current = snapshot(target.element), current.supportsPress,
                  current.role == target.snapshot.role, current.frame == target.snapshot.frame else { publish(nil, state: "目标失效"); return }
            let result = AXUIElementPerformAction(target.element, kAXPressAction as CFString)
            publish(target, state: result == .success ? "AXPress 成功" : "AXPress 失败 (\(result.rawValue))")
        }
    }
    private func discover(gaze: CGPoint, now: TimeInterval, previous: Target?, excluded: [CGRect], token: UInt64) -> [Target] {
        let offsets: [(CGFloat,CGFloat)] = [(0,0),(40,0),(-40,0),(0,40),(0,-40),(55,55),(55,-55),(-55,55),(-55,-55),(90,0),(-90,0),(0,90),(0,-90)]
        let system = AXUIElementCreateSystemWide(); AXUIElementSetMessagingTimeout(system, 0.12); var results: [Target] = []
        for (x,y) in offsets {
            lock.lock(); let active = enabled && !suspended && generation == token; lock.unlock()
            guard active else { break }
            let point = CGPoint(x: gaze.x + x, y: gaze.y + y)
            guard !excluded.contains(where: { $0.contains(point) }) else { continue }
            var element: AXUIElement?
            guard AXUIElementCopyElementAtPosition(system, Float(gaze.x+x), Float(gaze.y+y), &element) == .success, let hit = element else { continue }
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
                  let score = AccessibilityTargetScorer.score(value, gaze: gaze, current: previous.map { CFEqual($0.element, candidate) } ?? false, config: config) else { continue }
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
        var info: [String: Any] = ["state": state]
        if let target { info["target"] = target.snapshot; info["score"] = target.score; info["gaze"] = target.gaze; info["distance"] = AccessibilityTargetScorer.frameDistance(target.snapshot.frame, point: target.gaze) }
        DispatchQueue.main.async { NotificationCenter.default.post(name: Self.notification, object: nil, userInfo: info) }
    }
}
#endif
