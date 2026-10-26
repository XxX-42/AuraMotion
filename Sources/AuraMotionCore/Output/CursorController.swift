import Foundation
import CoreGraphics


/// Coordinates 1€ filter smoothing, coordinate mapping, and display boundary clamping.
public final class CursorController: @unchecked Sendable {
    private let filter = OneEuroFilter2D(minCutoff: 0.85, beta: 0.008, dCutoff: 1.0)
    private var lastRaw: CGPoint?
    private var pendingJump: CGPoint?
    private var lastOutput: CGPoint?
    private var lastBaselineAbsoluteTarget: CGPoint?
    private var transitionBias = CursorMappingTransitionBias()
    private var pendingTransitionRebase = false
    private var pendingResumeMoveOverride: CGPoint?
    private var lastTimestamp: TimeInterval?
    private var lastTrackingID: Int?
    private var isAwaitingAnchorRebase = false
    public var mapper: CoordinateMapper
    private let handFusion = HandCursorFusion()
    private let baselineFusion = HandCursorFusion()
    private let dynamics = CursorDynamicsController(settings: .init())
    private var relativeMapping = RelativePointerMapping()
    private var relativeDisplayBounds: [CGRect] = []
    private var experimentSettings = CursorExperimentSettings()
    private var interactionState: GestureState = .idle
    private var motionPhase: CursorMotionPhase = .frozen

    public private(set) var lastDiagnostics = CursorMotionDiagnostics()
    public private(set) var hasValidAnchorForLastSample = false

    /// Most recent cursor target emitted by the mapping pipeline, used only as
    /// a fallback when Quartz cannot report the actual pointer location.
    public var lastOutputLocation: CGPoint? { lastOutput }

    /// Consumed by AppEnvironment on the first pointer move after a frozen
    /// state, so a same-frame FSM emit cannot use the pre-rebase target.
    public func consumeResumeMoveOverride() -> CGPoint? {
        defer { pendingResumeMoveOverride = nil }
        return pendingResumeMoveOverride
    }

    /// Numeric filter tuning changes preserve filter history. Rebase for changes
    /// that select a different anchor, coordinate system, preset, or feature policy.
    public func requiresRebase(for settings: CursorExperimentSettings) -> Bool {
        let old = experimentSettings
        let new = settings.normalized()
        guard old != new else { return false }
        return old.hasCursorExperiments != new.hasCursorExperiments ||
            old.relativeMappingEnabled != new.relativeMappingEnabled ||
            old.effectiveMappingMode != new.effectiveMappingMode ||
            old.stableAnchorEnabled != new.stableAnchorEnabled ||
            old.effectiveAnchorStrategy != new.effectiveAnchorStrategy ||
            old.adaptiveDeadzoneEnabled != new.adaptiveDeadzoneEnabled ||
            old.lowSpeedQuantizationEnabled != new.lowSpeedQuantizationEnabled ||
            old.velocityGainEnabled != new.velocityGainEnabled ||
            old.separateDragTuningEnabled != new.separateDragTuningEnabled ||
            old.optimizedOneEuroEnabled != new.optimizedOneEuroEnabled
    }

    public init(profile: CalibrationProfile) {
        self.mapper = CoordinateMapper(profile: profile)
        self.relativeDisplayBounds = Self.activeDisplayBounds(fallback: profile.displayBounds)
        applyTuning(profile)
    }

    public func reset() {
        let preserveTransitionCursor = transitionBias.isActive
        let preservedCursor = (experimentSettings.hasCursorExperiments || preserveTransitionCursor) ? lastOutput : nil
        filter.reset()
        handFusion.reset()
        baselineFusion.reset()
        lastRaw = nil
        pendingJump = nil
        lastOutput = preservedCursor
        lastTimestamp = nil
        lastTrackingID = nil
        isAwaitingAnchorRebase = false
        hasValidAnchorForLastSample = false
        if transitionBias.isActive { pendingTransitionRebase = true }

        if experimentSettings.hasCursorExperiments {
            if motionPhase == .frozen {
                relativeMapping.freeze(at: preservedCursor)
            } else if experimentSettings.effectiveMappingMode == .relativeRebased {
                relativeMapping.rebase(to: preservedCursor)
            } else {
                relativeMapping.reset()
            }
            dynamics.reset(at: preservedCursor)
        }
    }

    public func updateProfile(_ profile: CalibrationProfile) {
        self.mapper = CoordinateMapper(profile: profile)
        relativeDisplayBounds = Self.activeDisplayBounds(fallback: profile.displayBounds)
        applyTuning(profile)
        reset()
    }

    /// Installs cursor experiments without changing the legacy absolute path when
    /// all experiment flags are disabled. Callers serialize this on interactionQueue.
    public func reconfigure(_ settings: CursorExperimentSettings, cursorPosition: CGPoint? = nil) {
        let normalized = settings.normalized()
        let cursor = valid(cursorPosition) ?? lastOutput
        let previousSettings = experimentSettings
        let shouldRebase = requiresRebase(for: normalized)
        if normalized.relativeMappingEnabled {
            relativeDisplayBounds = Self.activeDisplayBounds(fallback: mapper.profile.displayBounds)
        }

        if normalized.effectiveMappingMode == .relativeRebased {
            transitionBias.clear()
            pendingTransitionRebase = false
        } else {
            let mappingChanged = previousSettings.relativeMappingEnabled != normalized.relativeMappingEnabled
            let anchorChanged = previousSettings.stableAnchorEnabled != normalized.stableAnchorEnabled
            let switchedToBaseline = previousSettings.hasCursorExperiments && !normalized.hasCursorExperiments
            if mappingChanged || anchorChanged || switchedToBaseline {
                let newAbsoluteTarget = normalized.stableAnchorEnabled && lastDiagnostics.timestamp > 0
                    ? lastDiagnostics.rawAnchor
                    : lastBaselineAbsoluteTarget
                transitionBias.align(cursorPosition: cursor, absoluteTarget: newAbsoluteTarget)
                pendingTransitionRebase = cursor != nil
            }
        }

        experimentSettings = normalized
        handFusion.configure(strategy: normalized.effectiveAnchorStrategy)
        dynamics.configure(normalized)
        if shouldRebase {
            filter.reset()
            lastRaw = nil
            pendingJump = nil
            lastTimestamp = nil
            pendingResumeMoveOverride = nil
        }

        if normalized.hasCursorExperiments {
            if shouldRebase {
                lastOutput = cursor
                motionPhase = phase(for: interactionState)
                if normalized.effectiveMappingMode == .relativeRebased {
                    if motionPhase == .frozen {
                        relativeMapping.freeze(at: cursor)
                    } else {
                        relativeMapping.rebase(to: cursor)
                    }
                } else {
                    relativeMapping.reset()
                }
                dynamics.reset(at: cursor)
                lastDiagnostics = CursorMotionDiagnostics()
                lastDiagnostics.cursor = cursor ?? .zero
                lastDiagnostics.phase = motionPhase
            }
            applyExperimentTuning()
        } else {
            if shouldRebase {
                reset()
                relativeMapping.reset()
                motionPhase = phase(for: interactionState)
                lastDiagnostics = CursorMotionDiagnostics()
                if transitionBias.isActive { lastOutput = cursor }
            }
            applyTuning(mapper.profile)
        }
    }

    /// Tracks the FSM mode so relative mapping can hold position while gestures
    /// own the cursor (scroll, clutch, pinch arm, pause, loss, and swipe).
    public func setInteractionState(_ state: GestureState, currentCursor: CGPoint? = nil) {
        let previousPhase = motionPhase
        interactionState = state
        let nextPhase = phase(for: state)
        motionPhase = nextPhase
        guard previousPhase != nextPhase else { return }

        let cursor = valid(currentCursor) ?? lastOutput
        if !experimentSettings.hasCursorExperiments {
            guard transitionBias.isActive else { return }
            rebaseTransitionMapping(
                to: cursor,
                resumesPointer: previousPhase == .frozen && nextPhase == .pointer
            )
            return
        }

        applyExperimentTuning()
        if nextPhase == .frozen {
            freeze(at: cursor)
        } else {
            // This also handles pointer <-> drag tuning changes. The hand anchor
            // is reseeded by the next sample while the visible point is retained.
            rebase(to: cursor)
            motionPhase = nextPhase
        }
    }

    /// Freezes cursor output at the actual visible location until an explicit rebase.
    public func freeze(at cursorPosition: CGPoint?) {
        guard experimentSettings.hasCursorExperiments else { return }
        hasValidAnchorForLastSample = false
        let cursor = valid(cursorPosition) ?? lastOutput
        motionPhase = .frozen
        relativeMapping.freeze(at: cursor)
        filter.reset()
        lastRaw = nil
        pendingJump = nil
        if let cursor { lastOutput = cursor }
        dynamics.reset(at: cursor)
        lastDiagnostics.cursor = cursor ?? lastOutput ?? .zero
        lastDiagnostics.phase = .frozen
    }

    /// Starts a fresh hand anchor at the next frame while preserving the visible cursor.
    public func rebase(to cursorPosition: CGPoint?) {
        guard experimentSettings.hasCursorExperiments else { return }
        hasValidAnchorForLastSample = false
        let cursor = valid(cursorPosition) ?? lastOutput
        motionPhase = phase(for: interactionState)
        filter.reset()
        lastRaw = nil
        pendingJump = nil
        if let cursor { lastOutput = cursor }

        if experimentSettings.effectiveMappingMode == .relativeRebased {
            if phase(for: interactionState) == .frozen {
                relativeMapping.freeze(at: cursor)
            } else {
                relativeMapping.rebase(to: cursor)
            }
        } else {
            relativeMapping.reset()
        }
        dynamics.reset(at: cursor)
        applyExperimentTuning()
        lastDiagnostics.cursor = cursor ?? lastOutput ?? .zero
        lastDiagnostics.phase = motionPhase
    }

    /// Holds the current output while an external Vision configuration changes.
    /// Baseline uses a one-frame transition bias after the switch; its steady-state
    /// mapping and filter math remain unchanged.
    public func freezeForVisionReconfiguration(at cursorPosition: CGPoint?) {
        hasValidAnchorForLastSample = false
        if experimentSettings.hasCursorExperiments {
            freeze(at: cursorPosition)
            return
        }
        let cursor = valid(cursorPosition) ?? lastOutput
        if let cursor { lastOutput = cursor }
        filter.reset()
        lastRaw = nil
        pendingJump = nil
        lastTimestamp = nil
        pendingTransitionRebase = cursor != nil
    }

    /// Rebinds to the physical cursor after the Vision worker has installed the
    /// replacement provider and the previous tracking identity has been cleared.
    public func rebaseAfterVisionReconfiguration(to cursorPosition: CGPoint?) {
        hasValidAnchorForLastSample = false
        if experimentSettings.hasCursorExperiments {
            rebase(to: cursorPosition)
            return
        }
        let cursor = valid(cursorPosition) ?? lastOutput
        if let cursor { lastOutput = cursor }
        filter.reset()
        lastRaw = nil
        pendingJump = nil
        lastTimestamp = nil
        pendingTransitionRebase = cursor != nil
    }

    public var cursorExperimentStatus: String {
        guard experimentSettings.hasCursorExperiments else { return "Baseline" }
        return "anchor=\(experimentSettings.effectiveAnchorStrategy.rawValue);mapping=\(experimentSettings.effectiveMappingMode.rawValue);filter=\(experimentSettings.filterPreset.rawValue)"
    }

    private func applyTuning(_ profile: CalibrationProfile) {
        let configuration = CursorFilterConfiguration.resolve(
            settings: CursorExperimentSettings(),
            profile: profile,
            phase: .pointer
        )
        filter.configure(
            minCutoff: configuration.minCutoff,
            beta: configuration.beta,
            dCutoff: configuration.dCutoff
        )
    }

    private func applyExperimentTuning() {
        let configuration = CursorFilterConfiguration.resolve(
            settings: experimentSettings,
            profile: mapper.profile,
            phase: motionPhase
        )
        filter.configure(
            minCutoff: configuration.minCutoff,
            beta: configuration.beta,
            dCutoff: configuration.dCutoff
        )
    }

    public func processHand(_ sample: HandSample) -> CGPoint? {
        // Reset before fusion, so a long capture gap cannot discard a fresh anchor.
        if let time = lastTimestamp, sample.hostTimestamp - time > 0.25 { reset() }
        if experimentSettings.hasCursorExperiments,
           let lastTrackingID,
           lastTrackingID != sample.trackingID {
            isAwaitingAnchorRebase = true
        }
        lastTrackingID = sample.trackingID
        if experimentSettings.hasCursorExperiments && experimentSettings.stableAnchorEnabled {
            if let legacyAnchor = baselineFusion.update(sample) {
                lastBaselineAbsoluteTarget = mapper.mapToQuartzGlobal(visionPoint: legacyAnchor)
            }
        }
        let pointerAnchor = handFusion.update(sample)
        if experimentSettings.hasCursorExperiments && pointerAnchor == nil {
            isAwaitingAnchorRebase = true
        }
        return processIndexTip(normalizedPoint: pointerAnchor, timestamp: sample.hostTimestamp)
    }

    /// Maps normalized index-finger tip and applies 1€ adaptive filtering.
    public func processIndexTip(normalizedPoint: CGPoint?, timestamp: TimeInterval) -> CGPoint? {
        hasValidAnchorForLastSample = normalizedPoint.map {
            $0.x.isFinite && $0.y.isFinite && timestamp.isFinite
        } ?? false
        guard experimentSettings.hasCursorExperiments else {
            return processBaselineIndexTip(normalizedPoint: normalizedPoint, timestamp: timestamp)
        }

        if let normalizedPoint, normalizedPoint.x.isFinite, normalizedPoint.y.isFinite,
           !experimentSettings.stableAnchorEnabled {
            lastBaselineAbsoluteTarget = mapper.mapToQuartzGlobal(visionPoint: normalizedPoint)
        }
        return processExperimentalIndexTip(normalizedPoint: normalizedPoint, timestamp: timestamp)
    }

    private func processBaselineIndexTip(normalizedPoint: CGPoint?, timestamp: TimeInterval) -> CGPoint? {
        guard let rawPt = normalizedPoint else {
            // A single missing landmark should not discard the stabilizer.
            return lastOutput
        }
        guard rawPt.x.isFinite, rawPt.y.isFinite, timestamp.isFinite else { return lastOutput }
        if let previous = lastTimestamp {
            guard timestamp > previous else { return lastOutput }
            if timestamp - previous > 0.25 { reset() }
        }

        // 1. Map to Quartz global coordinates
        let absoluteMapped = mapper.mapToQuartzGlobal(visionPoint: rawPt)
        lastBaselineAbsoluteTarget = absoluteMapped
        if pendingTransitionRebase, let cursor = lastOutput {
            transitionBias.align(cursorPosition: cursor, absoluteTarget: absoluteMapped)
            pendingTransitionRebase = false
        }
        let mapped = applyTransitionBias(to: absoluteMapped)
        lastTimestamp = timestamp

        // One-frame landmark mistakes can look like very fast intentional motion
        // to an adaptive filter. Require a second nearby observation for big jumps.
        let bounds = mapper.profile.displayBounds
        let jumpThreshold = max(80, hypot(bounds.width, bounds.height) * 0.04)
        if let previous = lastRaw, hypot(mapped.x - previous.x, mapped.y - previous.y) > jumpThreshold {
            if let pending = pendingJump, hypot(mapped.x - pending.x, mapped.y - pending.y) <= jumpThreshold {
                pendingJump = nil
            } else {
                pendingJump = mapped
                lastDiagnostics.timestamp = timestamp
                lastDiagnostics.rawAnchor = absoluteMapped
                lastDiagnostics.cursor = lastOutput ?? .zero
                lastDiagnostics.phase = motionPhase
                return lastOutput
            }
        } else { pendingJump = nil }
        lastRaw = mapped

        // 2. Smooth with 1€ filter
        let smoothed = filter.filter(point: mapped, timestamp: timestamp)
        let previousOutput = lastOutput
        let sampleDuration = timestamp - (lastDiagnostics.timestamp > 0 ? lastDiagnostics.timestamp : timestamp)
        let speed = sampleDuration > 0 && sampleDuration.isFinite
            ? Double(hypot(smoothed.x - (previousOutput?.x ?? smoothed.x), smoothed.y - (previousOutput?.y ?? smoothed.y))) / sampleDuration
            : 0

        // A soft radial dead zone arrests resting tremor without rounding slow
        // motion into whole-pixel jumps. Deliberate movement accumulates naturally.
        if let previous = lastOutput {
            let dx = smoothed.x - previous.x
            let dy = smoothed.y - previous.y
            let distance = hypot(dx, dy)
            let radius = min(4, max(0.5, mapper.profile.cursorRestRadius ?? 1.25))
            if distance <= radius {
                lastDiagnostics.timestamp = timestamp
                lastDiagnostics.rawAnchor = absoluteMapped
                lastDiagnostics.filtered = smoothed
                lastDiagnostics.cursor = previous
                lastDiagnostics.speed = speed
                lastDiagnostics.deadzone = radius
                lastDiagnostics.gain = 1
                lastDiagnostics.phase = motionPhase
                return previous
            }
            let fraction = (distance - radius) / distance
            let result = CGPoint(x: previous.x + dx * fraction, y: previous.y + dy * fraction)
            lastOutput = result
            lastDiagnostics.timestamp = timestamp
            lastDiagnostics.rawAnchor = absoluteMapped
            lastDiagnostics.filtered = smoothed
            lastDiagnostics.cursor = result
            lastDiagnostics.speed = speed
            lastDiagnostics.deadzone = radius
            lastDiagnostics.gain = 1
            lastDiagnostics.phase = motionPhase
            return result
        }
        lastOutput = smoothed
        lastDiagnostics.timestamp = timestamp
        lastDiagnostics.rawAnchor = absoluteMapped
        lastDiagnostics.filtered = smoothed
        lastDiagnostics.cursor = smoothed
        lastDiagnostics.speed = 0
        lastDiagnostics.deadzone = min(4, max(0.5, mapper.profile.cursorRestRadius ?? 1.25))
        lastDiagnostics.gain = 1
        lastDiagnostics.phase = motionPhase
        return smoothed
    }

    private func processExperimentalIndexTip(normalizedPoint: CGPoint?, timestamp: TimeInterval) -> CGPoint? {
        guard let rawPt = normalizedPoint else {
            isAwaitingAnchorRebase = true
            updateFrozenDiagnostics(timestamp: timestamp)
            return lastOutput
        }
        guard rawPt.x.isFinite, rawPt.y.isFinite, timestamp.isFinite else { return lastOutput }
        if let previous = lastTimestamp {
            guard timestamp > previous else { return lastOutput }
            if timestamp - previous > 0.25 { reset() }
        }

        if isAwaitingAnchorRebase {
            isAwaitingAnchorRebase = false
            rebase(to: lastOutput)
        }

        let absoluteMapped = mapper.mapToQuartzGlobal(visionPoint: rawPt)
        if pendingTransitionRebase, experimentSettings.effectiveMappingMode != .relativeRebased,
           let cursor = lastOutput {
            transitionBias.align(cursorPosition: cursor, absoluteTarget: absoluteMapped)
            pendingTransitionRebase = false
        }
        let mapped = applyTransitionBias(to: absoluteMapped)
        lastTimestamp = timestamp
        lastDiagnostics.timestamp = timestamp
        lastDiagnostics.rawAnchor = absoluteMapped

        let bounds = mapper.profile.displayBounds
        let relativeBounds = relativeDisplayBounds.isEmpty ? [bounds] : relativeDisplayBounds
        let jumpThreshold = max(80, hypot(bounds.width, bounds.height) * 0.04)
        if let previous = lastRaw, hypot(mapped.x - previous.x, mapped.y - previous.y) > jumpThreshold {
            if let pending = pendingJump, hypot(mapped.x - pending.x, mapped.y - pending.y) <= jumpThreshold {
                pendingJump = nil
            } else {
                pendingJump = mapped
                updateFrozenDiagnostics(timestamp: timestamp)
                return lastOutput
            }
        } else {
            pendingJump = nil
        }
        lastRaw = mapped

        let target = experimentSettings.effectiveMappingMode == .relativeRebased
            ? (relativeMapping.map(
                target: mapped,
                currentCursor: lastOutput,
                displayBounds: relativeBounds
            ) ?? lastOutput ?? mapped)
            : mapped
        let filtered = filter.filter(point: target, timestamp: timestamp)
        lastDiagnostics.filtered = filtered

        var dynamicsTarget = filtered
        if !experimentSettings.adaptiveDeadzoneEnabled {
            dynamicsTarget = applyLegacyDeadzone(to: filtered)
        }

        let result = dynamics.process(target: dynamicsTarget, timestamp: timestamp, phase: motionPhase)
        guard let result else { return lastOutput }
        let boundedPoint = experimentSettings.effectiveMappingMode == .relativeRebased
            ? clamp(result.point, to: relativeBounds)
            : clamp(result.point, to: bounds)
        if boundedPoint != result.point { dynamics.reset(at: boundedPoint) }
        lastOutput = boundedPoint
        lastDiagnostics.cursor = boundedPoint
        lastDiagnostics.speed = result.speed
        lastDiagnostics.deadzone = result.deadzone
        lastDiagnostics.gain = result.gain
        lastDiagnostics.phase = motionPhase
        return boundedPoint
    }

    private func applyLegacyDeadzone(to filtered: CGPoint) -> CGPoint {
        guard let previous = lastOutput else {
            return filtered
        }

        let dx = filtered.x - previous.x
        let dy = filtered.y - previous.y
        let distance = hypot(dx, dy)
        let radius = min(4, max(0.5, mapper.profile.cursorRestRadius ?? 1.25))
        guard distance > radius else { return previous }
        let fraction = (distance - radius) / distance
        return CGPoint(x: previous.x + dx * fraction, y: previous.y + dy * fraction)
    }

    private func applyTransitionBias(to point: CGPoint) -> CGPoint {
        transitionBias.apply(to: point)
    }

    private func rebaseTransitionMapping(to cursor: CGPoint?, resumesPointer: Bool) {
        guard let cursor else { return }
        transitionBias.align(cursorPosition: cursor, absoluteTarget: lastBaselineAbsoluteTarget)
        pendingTransitionRebase = true
        lastOutput = cursor
        filter.reset()
        lastRaw = nil
        pendingJump = nil
        lastTimestamp = nil
        relativeMapping.reset()
        applyTuning(mapper.profile)
        pendingResumeMoveOverride = resumesPointer ? cursor : nil
    }

    private func clamp(_ point: CGPoint, to bounds: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
    }

    private func clamp(_ point: CGPoint, to bounds: [CGRect]) -> CGPoint {
        let validBounds = bounds.filter {
            $0.origin.x.isFinite && $0.origin.y.isFinite
                && $0.width.isFinite && $0.height.isFinite
                && $0.width > 0 && $0.height > 0
        }
        guard !validBounds.isEmpty else { return point }
        if validBounds.contains(where: { $0.contains(point) }) { return point }
        return validBounds.map { rect -> (point: CGPoint, distanceSquared: CGFloat) in
            let candidate = CGPoint(
                x: min(max(point.x, rect.minX), rect.maxX),
                y: min(max(point.y, rect.minY), rect.maxY)
            )
            let dx = candidate.x - point.x
            let dy = candidate.y - point.y
            return (candidate, dx * dx + dy * dy)
        }.min { $0.distanceSquared < $1.distanceSquared }?.point ?? point
    }

    private static func activeDisplayBounds(fallback: CGRect) -> [CGRect] {
        var displayCount: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &displayCount) == .success, displayCount > 0 else {
            return [fallback]
        }
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        let result = displayIDs.withUnsafeMutableBufferPointer { buffer in
            CGGetActiveDisplayList(displayCount, buffer.baseAddress, &displayCount)
        }
        guard result == .success else { return [fallback] }
        let bounds = displayIDs.prefix(Int(displayCount)).map(CGDisplayBounds).filter {
            $0.origin.x.isFinite && $0.origin.y.isFinite
                && $0.width.isFinite && $0.height.isFinite
                && $0.width > 0 && $0.height > 0
        }
        return bounds.isEmpty ? [fallback] : bounds
    }

    private func updateFrozenDiagnostics(timestamp: TimeInterval) {
        guard experimentSettings.hasCursorExperiments else { return }
        lastDiagnostics.timestamp = timestamp
        lastDiagnostics.cursor = lastOutput ?? .zero
        lastDiagnostics.phase = motionPhase
        if motionPhase == .frozen {
            lastDiagnostics.speed = 0
            lastDiagnostics.deadzone = 0
            lastDiagnostics.gain = 1
        }
    }

    private func phase(for state: GestureState) -> CursorMotionPhase {
        switch state {
        case .pointer: return .pointer
        case .dragging: return .drag
        default: return .frozen
        }
    }

    private func valid(_ point: CGPoint?) -> CGPoint? {
        guard let point, point.x.isFinite, point.y.isFinite else { return nil }
        return point
    }
}
