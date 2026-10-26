import Foundation

public enum CursorExperimentPreset: String, Codable, Sendable, CaseIterable { case baseline, optimized, custom }
public enum PointerAnchorStrategy: String, Codable, Sendable, CaseIterable { case legacyTipFusion, indexMCP, palmCentroid, palmMCPFusion }
public enum CursorMappingMode: String, Codable, Sendable, CaseIterable { case absoluteLegacy, relativeRebased }
public enum CursorFilterPreset: String, Codable, Sendable, CaseIterable { case legacy, precision, custom }
public enum CursorMotionPhase: String, Codable, Sendable { case pointer, drag, frozen }

/// One configuration carried by AppSettings; disabled modules must use the original path.
/// Defaults deliberately preserve the upstream baseline. Confinement is the existing interaction queue.
public struct CursorExperimentSettings: Codable, Sendable, Equatable {
    public var preset: CursorExperimentPreset = .baseline
    public var stableAnchorEnabled = false
    public var relativeMappingEnabled = false
    public var adaptiveDeadzoneEnabled = false
    public var lowSpeedQuantizationEnabled = false
    public var velocityGainEnabled = false
    public var separateDragTuningEnabled = false
    public var optimizedOneEuroEnabled = false
    public var visionROIEnabled = false
    public var mediaPipeBenchmarkEnabled = false
    public var anchorStrategy: PointerAnchorStrategy = .palmMCPFusion
    public var mappingMode: CursorMappingMode = .relativeRebased
    public var filterPreset: CursorFilterPreset = .precision
    public var pointerMinCutoff: Double = 0.50
    public var pointerBeta: Double = 0.015
    public var dragMinCutoff: Double = 1.1
    public var dragBeta: Double = 0.018
    public var derivativeCutoff: Double = 1.0
    public var restDeadzone: Double = 4.0
    public var movingDeadzone: Double = 0.25
    public var deadzoneVelocity: Double = 90
    public var quantizationSpeedThreshold: Double = 60
    public var precisionGain: Double = 0.4
    public var normalGain: Double = 1.0
    public var fastGain: Double = 1.7
    public var gainPrecisionSpeed: Double = 60
    public var gainNormalSpeed: Double = 300
    public var gainFastSpeed: Double = 900
    public var roiScale: Double = 1.8
    public var roiMinimumSize: Double = 0.35

    public init() {}

    public var effectiveAnchorStrategy: PointerAnchorStrategy { stableAnchorEnabled ? anchorStrategy : .legacyTipFusion }
    public var effectiveMappingMode: CursorMappingMode { relativeMappingEnabled ? mappingMode : .absoluteLegacy }
    public var hasCursorExperiments: Bool {
        stableAnchorEnabled || relativeMappingEnabled || adaptiveDeadzoneEnabled || lowSpeedQuantizationEnabled || velocityGainEnabled || separateDragTuningEnabled || optimizedOneEuroEnabled
    }

    public mutating func applyPreset(_ value: CursorExperimentPreset) {
        preset = value
        guard value != .custom else { return }
        let enabled = value == .optimized
        stableAnchorEnabled = enabled
        relativeMappingEnabled = enabled
        adaptiveDeadzoneEnabled = enabled
        lowSpeedQuantizationEnabled = enabled
        velocityGainEnabled = enabled
        separateDragTuningEnabled = enabled
        optimizedOneEuroEnabled = enabled
        // Vision ROI needs independent measured opt-in; MediaPipe never runs by default.
        visionROIEnabled = false
        mediaPipeBenchmarkEnabled = false
    }

    public func normalized() -> Self {
        var result = self
        func clamp(_ value: Double, _ low: Double, _ high: Double, _ fallback: Double) -> Double {
            value.isFinite ? min(high, max(low, value)) : fallback
        }
        result.pointerMinCutoff = clamp(pointerMinCutoff, 0.1, 10, 0.5)
        result.pointerBeta = clamp(pointerBeta, 0, 0.1, 0.015)
        result.dragMinCutoff = clamp(dragMinCutoff, 0.1, 10, 1.1)
        result.dragBeta = clamp(dragBeta, 0, 0.1, 0.018)
        result.derivativeCutoff = clamp(derivativeCutoff, 0.1, 10, 1)
        result.restDeadzone = clamp(restDeadzone, 0, 12, 4)
        result.movingDeadzone = clamp(movingDeadzone, 0, result.restDeadzone, 0.25)
        result.deadzoneVelocity = clamp(deadzoneVelocity, 1, 3000, 90)
        result.quantizationSpeedThreshold = clamp(quantizationSpeedThreshold, 0, 1000, 60)
        result.precisionGain = clamp(precisionGain, 0.05, 3, 0.4)
        result.normalGain = clamp(normalGain, result.precisionGain, 4, 1)
        result.fastGain = clamp(fastGain, result.normalGain, 6, 1.7)
        result.gainPrecisionSpeed = clamp(gainPrecisionSpeed, 1, 1000, 60)
        result.gainNormalSpeed = clamp(gainNormalSpeed, result.gainPrecisionSpeed + 1, 5000, 300)
        result.gainFastSpeed = clamp(gainFastSpeed, result.gainNormalSpeed + 1, 10000, 900)
        result.roiScale = clamp(roiScale, 1.1, 4, 1.8)
        result.roiMinimumSize = clamp(roiMinimumSize, 0.1, 1, 0.35)
        return result
    }
}

/// Small value snapshot shared by live diagnostics and deterministic replay.
public struct CursorMotionDiagnostics: Sendable {
    public var timestamp: Double = 0
    public var rawAnchor: CGPoint = .zero
    public var filtered: CGPoint = .zero
    public var cursor: CGPoint = .zero
    public var speed: Double = 0
    public var deadzone: Double = 0
    public var gain: Double = 1
    public var phase: CursorMotionPhase = .frozen
    public init() {}
}
