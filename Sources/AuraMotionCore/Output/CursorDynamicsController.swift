import Foundation
import CoreGraphics

/// The output of the optional cursor dynamics stage.
public struct CursorDynamicsResult: Sendable, Equatable {
    public let point: CGPoint
    public let speed: Double
    public let deadzone: Double
    public let gain: Double

    public init(point: CGPoint, speed: Double, deadzone: Double, gain: Double) {
        self.point = point
        self.speed = speed
        self.deadzone = deadzone
        self.gain = gain
    }
}

/// Applies optional deadzone, low-speed quantization, and velocity gain to absolute
/// screen-space targets. This is a deterministic math stage; callers own scheduling
/// and should confine an instance to their existing interaction queue.
public final class CursorDynamicsController {
    private static let maximumSampleGap = 0.25
    private static let maximumReportedSpeed = 10_000.0

    private var settings: CursorExperimentSettings
    private var outputPoint: CGPoint?
    private var lastTarget: CGPoint?
    private var lastTimestamp: Double?
    /// Motion that has passed through the gain stage but is still inside the deadzone.
    private var accumulatedMotion = CGPoint.zero
    private var lastPhase: CursorMotionPhase?
    private var lastResult: CursorDynamicsResult?

    public init(settings: CursorExperimentSettings = .init()) {
        self.settings = settings.normalized()
    }

    /// Reconfigures the math stage without changing its currently visible point.
    public func configure(_ settings: CursorExperimentSettings) {
        self.settings = settings.normalized()
        if let visiblePoint = lastResult?.point {
            outputPoint = visiblePoint
        }
        accumulatedMotion = .zero
    }

    /// Clears motion history and optionally seeds the visible position.
    public func reset(at point: CGPoint? = nil) {
        let seed: CGPoint?
        if let point, Self.isFinite(point) {
            seed = point
        } else {
            seed = nil
        }
        outputPoint = seed
        lastTarget = seed
        lastTimestamp = nil
        accumulatedMotion = .zero
        lastPhase = nil
        lastResult = seed.map {
            CursorDynamicsResult(point: $0, speed: 0, deadzone: 0, gain: 1)
        }
    }

    /// Processes an absolute mapped screen-space target. Invalid or stale samples
    /// return the last valid result; a long gap reanchors input while holding output.
    public func process(
        target: CGPoint,
        timestamp: Double,
        phase: CursorMotionPhase
    ) -> CursorDynamicsResult? {
        guard Self.isFinite(target), timestamp.isFinite else { return lastResult }

        guard let currentOutput = outputPoint else {
            outputPoint = target
            lastTarget = target
            lastTimestamp = timestamp
            lastPhase = phase
            let result = makeResult(point: target, speed: 0, phase: phase)
            lastResult = result
            return result
        }

        guard let previousTarget = lastTarget, let previousTimestamp = lastTimestamp else {
            // `reset(at:)` seeds the visible point but has no clock sample yet. The
            // first input establishes a fresh target origin without moving the cursor.
            lastTarget = target
            lastTimestamp = timestamp
            lastPhase = phase
            accumulatedMotion = .zero
            let point = lastResult?.point ?? currentOutput
            let result = makeResult(point: point, speed: 0, phase: phase, preservePoint: true)
            lastResult = result
            return result
        }

        let elapsed = timestamp - previousTimestamp
        guard elapsed.isFinite, elapsed > 0 else { return lastResult }

        let dx = Double(target.x - previousTarget.x)
        let dy = Double(target.y - previousTarget.y)
        guard dx.isFinite, dy.isFinite else { return lastResult }

        // Phase changes rebase from the last displayed point. This prevents a
        // quantization or deadzone tuning change from exposing hidden fractional motion.
        if let previousPhase = lastPhase, previousPhase != phase,
           let visiblePoint = lastResult?.point {
            outputPoint = visiblePoint
            accumulatedMotion = .zero
        }

        if phase == .frozen {
            outputPoint = lastResult?.point ?? currentOutput
            lastTarget = target
            lastTimestamp = timestamp
            accumulatedMotion = .zero
            lastPhase = phase
            let result = CursorDynamicsResult(
                point: outputPoint ?? currentOutput,
                speed: 0,
                deadzone: 0,
                gain: 1
            )
            lastResult = result
            return result
        }

        if elapsed > Self.maximumSampleGap {
            // Do not turn an occlusion/re-enable jump into an enormous velocity.
            lastTarget = target
            lastTimestamp = timestamp
            accumulatedMotion = .zero
            lastPhase = phase
            let result = makeResult(point: outputPoint ?? currentOutput, speed: 0, phase: phase)
            lastResult = result
            return result
        }

        let distance = hypot(dx, dy)
        guard distance.isFinite else { return lastResult }
        let speed = min(Self.maximumReportedSpeed, distance / elapsed)
        let gain = gain(for: speed)
        let scaledDX = dx * gain
        let scaledDY = dy * gain
        guard scaledDX.isFinite, scaledDY.isFinite else {
            reanchorInput(to: target, timestamp: timestamp, phase: phase)
            return lastResult
        }

        let pendingX = Double(accumulatedMotion.x) + scaledDX
        let pendingY = Double(accumulatedMotion.y) + scaledDY
        guard pendingX.isFinite, pendingY.isFinite else {
            reanchorInput(to: target, timestamp: timestamp, phase: phase)
            return lastResult
        }

        let pendingDistance = hypot(pendingX, pendingY)
        let deadzone = deadzone(for: speed, phase: phase)
        var nextOutput = outputPoint ?? currentOutput

        if pendingDistance.isFinite, pendingDistance > deadzone {
            let releasedDistance = pendingDistance - deadzone
            let unitX = pendingX / pendingDistance
            let unitY = pendingY / pendingDistance
            let outputX = Double(nextOutput.x) + unitX * releasedDistance
            let outputY = Double(nextOutput.y) + unitY * releasedDistance
            guard outputX.isFinite, outputY.isFinite else {
                reanchorInput(to: target, timestamp: timestamp, phase: phase)
                return lastResult
            }
            nextOutput = CGPoint(x: outputX, y: outputY)
            accumulatedMotion = CGPoint(x: unitX * deadzone, y: unitY * deadzone)
        } else {
            accumulatedMotion = CGPoint(x: pendingX, y: pendingY)
        }

        guard Self.isFinite(nextOutput), Self.isFinite(accumulatedMotion) else {
            reanchorInput(to: target, timestamp: timestamp, phase: phase)
            return lastResult
        }

        outputPoint = nextOutput
        lastTarget = target
        lastTimestamp = timestamp
        lastPhase = phase

        let result = makeResult(point: nextOutput, speed: speed, phase: phase)
        lastResult = result
        return result
    }

    private func reanchorInput(to target: CGPoint, timestamp: Double, phase: CursorMotionPhase) {
        lastTarget = target
        lastTimestamp = timestamp
        lastPhase = phase
        accumulatedMotion = .zero
    }

    private func makeResult(
        point: CGPoint,
        speed: Double,
        phase: CursorMotionPhase,
        preservePoint: Bool = false
    ) -> CursorDynamicsResult {
        let deadzone = deadzone(for: speed, phase: phase)
        let gain = phase == .frozen ? 1 : gain(for: speed)
        let visiblePoint = preservePoint ? point : quantized(point, speed: speed, phase: phase)
        return CursorDynamicsResult(point: visiblePoint, speed: speed, deadzone: deadzone, gain: gain)
    }

    private func deadzone(for speed: Double, phase: CursorMotionPhase) -> Double {
        guard settings.adaptiveDeadzoneEnabled, phase != .frozen else { return 0 }

        let normalizedSpeed = min(1, max(0, speed / settings.deadzoneVelocity))
        // Smoothstep avoids a sharp radius change while retaining the configured
        // 4 px resting zone and 0.25 px moving floor by default.
        let easedSpeed = normalizedSpeed * normalizedSpeed * (3 - 2 * normalizedSpeed)
        let pointerRadius = settings.restDeadzone
            + (settings.movingDeadzone - settings.restDeadzone) * easedSpeed

        if phase == .drag, settings.separateDragTuningEnabled {
            return settings.movingDeadzone
                + (pointerRadius - settings.movingDeadzone) * 0.35
        }
        return pointerRadius
    }

    private func gain(for speed: Double) -> Double {
        guard settings.velocityGainEnabled else { return 1 }

        if speed <= settings.gainPrecisionSpeed { return settings.precisionGain }
        if speed <= settings.gainNormalSpeed {
            return interpolate(
                speed,
                from: settings.gainPrecisionSpeed,
                to: settings.gainNormalSpeed,
                start: settings.precisionGain,
                end: settings.normalGain
            )
        }
        if speed <= settings.gainFastSpeed {
            return interpolate(
                speed,
                from: settings.gainNormalSpeed,
                to: settings.gainFastSpeed,
                start: settings.normalGain,
                end: settings.fastGain
            )
        }
        return settings.fastGain
    }

    private func interpolate(_ value: Double, from startValue: Double, to endValue: Double, start: Double, end: Double) -> Double {
        let fraction = min(1, max(0, (value - startValue) / (endValue - startValue)))
        return start + (end - start) * fraction
    }

    private func quantized(_ point: CGPoint, speed: Double, phase: CursorMotionPhase) -> CGPoint {
        guard settings.lowSpeedQuantizationEnabled,
              !(phase == .drag && settings.separateDragTuningEnabled),
              speed < settings.quantizationSpeedThreshold else {
            return point
        }
        return CGPoint(
            x: point.x.rounded(.toNearestOrAwayFromZero),
            y: point.y.rounded(.toNearestOrAwayFromZero)
        )
    }

    private static func isFinite(_ point: CGPoint) -> Bool {
        point.x.isFinite && point.y.isFinite
    }
}
