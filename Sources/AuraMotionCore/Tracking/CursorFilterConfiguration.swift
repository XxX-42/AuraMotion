import Foundation

/// Effective 1€ parameters for one cursor motion phase.
public struct CursorFilterConfiguration: Sendable, Equatable {
    public let minCutoff: Double
    public let beta: Double
    public let dCutoff: Double

    public init(minCutoff: Double, beta: Double, dCutoff: Double) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.dCutoff = dCutoff
    }

    /// Resolves persisted settings into safe runtime values.
    ///
    /// The optimized-filter switch gates pointer precision/custom tuning. Drag
    /// tuning is an independent switch: when enabled, the configured drag values
    /// can tune drag motion even while optimized pointer filtering is disabled.
    public static func resolve(
        settings: CursorExperimentSettings,
        profile: CalibrationProfile,
        phase: CursorMotionPhase
    ) -> Self {
        let settings = settings.normalized()
        let baseline = calibratedBaseline(profile: profile)

        if phase == .drag, settings.separateDragTuningEnabled {
            if settings.optimizedOneEuroEnabled, settings.filterPreset == .precision {
                return Self(minCutoff: 1.1, beta: 0.018, dCutoff: 1.0)
            }

            // A separately enabled drag filter is an explicit override, including
            // when the pointer filter remains on its calibrated baseline.
            return Self(
                minCutoff: bounded(settings.dragMinCutoff, range: 0.1...10, fallback: 1.1),
                beta: bounded(settings.dragBeta, range: 0...0.1, fallback: 0.018),
                dCutoff: bounded(settings.derivativeCutoff, range: 0.1...10, fallback: 1.0)
            )
        }

        guard settings.optimizedOneEuroEnabled else { return baseline }
        switch settings.filterPreset {
        case .legacy:
            return baseline
        case .precision:
            return Self(minCutoff: 0.5, beta: 0.015, dCutoff: 1.0)
        case .custom:
            return Self(
                minCutoff: bounded(settings.pointerMinCutoff, range: 0.1...10, fallback: 0.5),
                beta: bounded(settings.pointerBeta, range: 0...0.1, fallback: 0.015),
                dCutoff: bounded(settings.derivativeCutoff, range: 0.1...10, fallback: 1.0)
            )
        }
    }

    private static func calibratedBaseline(profile: CalibrationProfile) -> Self {
        Self(
            minCutoff: bounded(profile.cursorMinCutoff ?? 0.85, range: 0.5...1.5, fallback: 0.85),
            beta: bounded(profile.cursorMotionBeta ?? 0.008, range: 0.004...0.025, fallback: 0.008),
            dCutoff: 1.0
        )
    }

    private static func bounded(_ value: Double, range: ClosedRange<Double>, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(range.upperBound, max(range.lowerBound, value))
    }
}
