import CoreGraphics
import Foundation

public enum CursorExperimentReplayMode: String, Codable, Sendable, CaseIterable {
    case baseline
    case stableRelativeOnly
    case filterDragQuantization
    case adaptive
    case optimized
    case fullSeven
}

public struct CursorExperimentReplayRow: Codable, Sendable, Equatable {
    /// Original monotonic host-time timestamp in seconds.
    public let timestamp: Double
    public let source: CursorExperimentSource
    public let rawAnchor: CGPoint?
    public let filtered: CGPoint?
    public let cursor: CGPoint?
    public let speed: Double?
    public let deadzone: Double?
    public let gain: Double?
    public let state: GestureState?
    public let motionPhase: CursorMotionPhase?
    public let target: CGPoint?
    public let targetPhase: CursorExperimentTaskPhase?
    public let targetEvent: CursorExperimentTaskEvent?
    public let inferenceDurationMilliseconds: Double?
    public let mailboxWaitMilliseconds: Double?

    public init(
        timestamp: Double,
        source: CursorExperimentSource,
        rawAnchor: CGPoint?,
        filtered: CGPoint?,
        cursor: CGPoint?,
        speed: Double?,
        deadzone: Double?,
        gain: Double?,
        state: GestureState?,
        motionPhase: CursorMotionPhase?,
        target: CGPoint?,
        targetPhase: CursorExperimentTaskPhase?,
        targetEvent: CursorExperimentTaskEvent?,
        inferenceDurationMilliseconds: Double?,
        mailboxWaitMilliseconds: Double?
    ) {
        self.timestamp = timestamp
        self.source = source
        self.rawAnchor = rawAnchor
        self.filtered = filtered
        self.cursor = cursor
        self.speed = speed
        self.deadzone = deadzone
        self.gain = gain
        self.state = state
        self.motionPhase = motionPhase
        self.target = target
        self.targetPhase = targetPhase
        self.targetEvent = targetEvent
        self.inferenceDurationMilliseconds = inferenceDurationMilliseconds
        self.mailboxWaitMilliseconds = mailboxWaitMilliseconds
    }
}

/// A measured value or an explicit reason that a value could not be measured.
/// Missing or unlabelled data is represented as null, never as numeric zero.
public struct CursorExperimentMetricValue: Codable, Sendable, Equatable {
    public let value: Double?
    public let unit: String
    public let unavailableReason: String?

    public init(value: Double?, unit: String, unavailableReason: String? = nil) {
        self.value = value.flatMap { $0.isFinite ? $0 : nil }
        self.unit = unit
        if self.value == nil {
            self.unavailableReason = unavailableReason ?? "No valid observations were available."
        } else {
            self.unavailableReason = nil
        }
    }

    public static func unavailable(_ reason: String, unit: String) -> Self {
        Self(value: nil, unit: unit, unavailableReason: reason)
    }
}

public struct CursorExperimentAxisStatistics: Codable, Sendable, Equatable {
    public let observationCount: Int
    public let unit: String
    public let sigmaX: CursorExperimentMetricValue
    public let sigmaY: CursorExperimentMetricValue
    public let rmsStepDisplacement: CursorExperimentMetricValue
    public let p95StepDisplacement: CursorExperimentMetricValue
    public let maximumStepDisplacement: CursorExperimentMetricValue

    public init(
        observationCount: Int,
        unit: String,
        sigmaX: CursorExperimentMetricValue,
        sigmaY: CursorExperimentMetricValue,
        rmsStepDisplacement: CursorExperimentMetricValue,
        p95StepDisplacement: CursorExperimentMetricValue,
        maximumStepDisplacement: CursorExperimentMetricValue
    ) {
        self.observationCount = observationCount
        self.unit = unit
        self.sigmaX = sigmaX
        self.sigmaY = sigmaY
        self.rmsStepDisplacement = rmsStepDisplacement
        self.p95StepDisplacement = p95StepDisplacement
        self.maximumStepDisplacement = maximumStepDisplacement
    }
}

public struct CursorExperimentJointStatistics: Codable, Sendable, Equatable {
    /// Descriptive statistics over every valid point; movement is not called jitter.
    public let allObservations: CursorExperimentAxisStatistics
    /// Populated only for frames explicitly annotated as stationary.
    public let stationaryObservations: CursorExperimentAxisStatistics
}

public struct CursorExperimentTargetMetrics: Codable, Sendable, Equatable {
    public let targetErrorRMSPoints: CursorExperimentMetricValue
    public let overshootP10Points: CursorExperimentMetricValue
    public let overshootP50Points: CursorExperimentMetricValue
    public let overshootP90Points: CursorExperimentMetricValue
    public let slowMoveLagP95Points: CursorExperimentMetricValue
    public let fastMoveCompletionP95Milliseconds: CursorExperimentMetricValue
    public let cursorErrorAtClickP95Points: CursorExperimentMetricValue
    public let dragCursorContinuityRatio: CursorExperimentMetricValue
    public let dragMaximumStepPoints: CursorExperimentMetricValue
}

public struct CursorExperimentReplaySummary: Codable, Sendable, Equatable {
    public let frameCount: Int
    public let sampleCount: Int
    public let assumedPointerStateFrames: Int
    /// Number of transitions into `.trackingLost` in the captured interaction state.
    public let trackingLossTransitionCount: Int
    public let effectiveFPS: CursorExperimentMetricValue
    public let inferenceP50Milliseconds: CursorExperimentMetricValue
    public let inferenceP95Milliseconds: CursorExperimentMetricValue
    public let inferenceP99Milliseconds: CursorExperimentMetricValue
    public let mailboxWaitP50Milliseconds: CursorExperimentMetricValue
    public let mailboxWaitP95Milliseconds: CursorExperimentMetricValue
    public let mailboxWaitP99Milliseconds: CursorExperimentMetricValue
    public let observedMailboxDroppedFrames: Int?
    public let mailboxDropsUnavailableReason: String?
    public let framesDroppedAtRecorderCapacity: Int
    public let framesRejectedForSourceMismatch: Int
    public let roiFullFrameCount: Int?
    public let roiFallbackCount: Int?
    public let roiUnavailableReason: String?
    public let jointStatistics: [String: CursorExperimentJointStatistics]
    public let targetMetrics: CursorExperimentTargetMetrics
    public let cpuPercent: CursorExperimentMetricValue
    public let residentMemoryBytes: CursorExperimentMetricValue
    public let calibrationProfileIsRecorded: Bool
    public let initialCursorWasAssumed: Bool
    public let interpretationNote: String
}

public struct CursorExperimentReplayRun: Codable, Sendable, Equatable {
    public let mode: CursorExperimentReplayMode
    public let settings: CursorExperimentSettings
    public let rows: [CursorExperimentReplayRow]
    public let summary: CursorExperimentReplaySummary

    public init(
        mode: CursorExperimentReplayMode,
        settings: CursorExperimentSettings,
        rows: [CursorExperimentReplayRow],
        summary: CursorExperimentReplaySummary
    ) {
        self.mode = mode
        self.settings = settings
        self.rows = rows
        self.summary = summary
    }
}

public struct CursorExperimentReplayReport: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let sessionID: String
    public let source: CursorExperimentSource
    public let calibrationProfile: CalibrationProfile
    public let runs: [CursorExperimentReplayRun]

    public init(
        schemaVersion: Int = CursorExperimentRecording.currentSchemaVersion,
        sessionID: String,
        source: CursorExperimentSource,
        calibrationProfile: CalibrationProfile,
        runs: [CursorExperimentReplayRun]
    ) {
        self.schemaVersion = schemaVersion
        self.sessionID = sessionID
        self.source = source
        self.calibrationProfile = calibrationProfile
        self.runs = runs
    }
}

public enum CursorExperimentReplayError: Error, LocalizedError, Equatable {
    case unsupportedSchema(Int)
    case emptyRecording
    case legacySourceRequired
    case sourceMismatch

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version): return "Unsupported cursor recording schema version \(version)."
        case .emptyRecording: return "The cursor recording has no frames to replay."
        case .legacySourceRequired: return "This legacy session has no source label. Pass --source camera or --source synthetic explicitly."
        case .sourceMismatch: return "The requested source does not match the source saved in the recording."
        }
    }
}

/// Runs the same recorded HandSample sequence through the existing production controller.
public enum CursorExperimentReplayEvaluator {
    private static let jointNames: [HandJointName] = [.indexTip, .indexMCP, .middleMCP, .wrist]

    public static func evaluate(_ recording: CursorExperimentRecording) throws -> CursorExperimentReplayReport {
        guard recording.schemaVersion == CursorExperimentRecording.currentSchemaVersion else {
            throw CursorExperimentReplayError.unsupportedSchema(recording.schemaVersion)
        }
        guard !recording.frames.isEmpty else { throw CursorExperimentReplayError.emptyRecording }

        let baseline = evaluate(recording, mode: .baseline)
        let optimized = evaluate(recording, mode: .optimized)
        return report(for: recording, runs: [baseline, optimized])
    }

    /// Adds controlled module groups to the same recorded trace for tuning studies.
    /// The normal camera A/B export remains the two-run Baseline/Optimized report.
    public static func evaluateSweep(_ recording: CursorExperimentRecording) throws -> CursorExperimentReplayReport {
        guard recording.schemaVersion == CursorExperimentRecording.currentSchemaVersion else {
            throw CursorExperimentReplayError.unsupportedSchema(recording.schemaVersion)
        }
        guard !recording.frames.isEmpty else { throw CursorExperimentReplayError.emptyRecording }
        let modes: [CursorExperimentReplayMode] = [
            .baseline, .stableRelativeOnly, .filterDragQuantization, .adaptive, .optimized, .fullSeven
        ]
        return report(for: recording, runs: modes.map { evaluate(recording, mode: $0) })
    }

    private static func report(
        for recording: CursorExperimentRecording,
        runs: [CursorExperimentReplayRun]
    ) -> CursorExperimentReplayReport {
        return CursorExperimentReplayReport(
            sessionID: recording.sessionID,
            source: recording.source,
            calibrationProfile: recording.metadata.calibrationProfile,
            runs: runs
        )
    }

    private static func evaluate(
        _ recording: CursorExperimentRecording,
        mode: CursorExperimentReplayMode
    ) -> CursorExperimentReplayRun {
        let settings = settings(for: mode)

        let profile = recording.metadata.calibrationProfile
        let center = CGPoint(x: profile.displayBounds.midX, y: profile.displayBounds.midY)
        let initialCursor = recording.metadata.initialCursorPosition ?? center
        let controller = CursorController(profile: profile)
        controller.reconfigure(settings, cursorPosition: initialCursor)

        var rows: [CursorExperimentReplayRow] = []
        rows.reserveCapacity(recording.frames.count)
        var assumedStateCount = 0
        var currentCursor = initialCursor

        for frame in recording.frames {
            let state: GestureState
            if let recordedState = frame.state {
                state = recordedState
            } else {
                // Older LandmarkRecorder JSON did not store FSM state. This explicit
                // replay assumption preserves a useful sample-only replay and is counted.
                state = .pointer
                assumedStateCount += 1
            }
            controller.setInteractionState(state, currentCursor: currentCursor)

            if let sample = frame.sample {
                currentCursor = controller.processHand(sample) ?? currentCursor
            }

            let diagnostics = controller.lastDiagnostics
            let hasControllerObservation = frame.sample != nil || diagnostics.timestamp != 0
            let rawAnchor = hasControllerObservation ? diagnostics.rawAnchor : nil
            let filtered = hasControllerObservation ? diagnostics.filtered : nil
            let cursor = controller.lastOutputLocation ?? (hasControllerObservation ? diagnostics.cursor : nil)
            if let cursor { currentCursor = cursor }
            rows.append(CursorExperimentReplayRow(
                timestamp: frame.timestamp,
                source: frame.source,
                rawAnchor: rawAnchor,
                filtered: filtered,
                cursor: cursor,
                speed: hasControllerObservation ? diagnostics.speed : nil,
                deadzone: hasControllerObservation ? diagnostics.deadzone : nil,
                gain: hasControllerObservation ? diagnostics.gain : nil,
                state: frame.state,
                motionPhase: hasControllerObservation ? diagnostics.phase : nil,
                target: frame.groundTruth?.target,
                targetPhase: frame.groundTruth?.phase ?? recording.metadata.declaredTaskPhase,
                targetEvent: frame.groundTruth?.event,
                inferenceDurationMilliseconds: frame.inferenceDurationMilliseconds,
                mailboxWaitMilliseconds: frame.mailboxWaitMilliseconds
            ))
        }

        let summary = summarize(recording, rows: rows, assumedStateCount: assumedStateCount)
        return CursorExperimentReplayRun(mode: mode, settings: settings, rows: rows, summary: summary)
    }

    private static func settings(for mode: CursorExperimentReplayMode) -> CursorExperimentSettings {
        var settings = CursorExperimentSettings()
        switch mode {
        case .baseline:
            settings.applyPreset(.baseline)
        case .stableRelativeOnly:
            settings.preset = .custom
            settings.stableAnchorEnabled = true
            settings.relativeMappingEnabled = true
        case .filterDragQuantization:
            settings.preset = .custom
            settings.stableAnchorEnabled = true
            settings.relativeMappingEnabled = true
            settings.lowSpeedQuantizationEnabled = true
            settings.separateDragTuningEnabled = true
            settings.optimizedOneEuroEnabled = true
        case .adaptive:
            settings.preset = .custom
            settings.stableAnchorEnabled = true
            settings.relativeMappingEnabled = true
            settings.adaptiveDeadzoneEnabled = true
            settings.lowSpeedQuantizationEnabled = true
            settings.separateDragTuningEnabled = true
            settings.optimizedOneEuroEnabled = true
        case .optimized:
            settings.applyPreset(.optimized)
        case .fullSeven:
            settings.applyPreset(.optimized)
            settings.velocityGainEnabled = true
        }
        return settings.normalized()
    }

    private static func summarize(
        _ recording: CursorExperimentRecording,
        rows: [CursorExperimentReplayRow],
        assumedStateCount: Int
    ) -> CursorExperimentReplaySummary {
        let timestamps = recording.frames.map(\.timestamp).filter(\.isFinite)
        let fps: CursorExperimentMetricValue
        if timestamps.count >= 2, let first = timestamps.first, let last = timestamps.last, last > first {
            fps = .init(value: Double(timestamps.count - 1) / (last - first), unit: "frames/second")
        } else {
            fps = .unavailable("At least two frames with increasing host timestamps are required.", unit: "frames/second")
        }

        let inference = recording.frames.compactMap(\.inferenceDurationMilliseconds).filter { $0.isFinite && $0 >= 0 }
        let mailboxWait = recording.frames.compactMap(\.mailboxWaitMilliseconds).filter { $0.isFinite && $0 >= 0 }
        let mailboxDrops = recording.frames.compactMap(\.droppedFrames).max()
        let fullFrameCount = recording.frames.compactMap(\.roi).filter(\.usedFullFrame).count
        let roiFallbackCount = recording.frames.compactMap(\.roi).filter { $0.fallbackReason != nil }.count
        let roiKnown = recording.frames.contains { $0.roi != nil }
        let trackingLossTransitionCount = recording.frames.enumerated().reduce(into: 0) { count, entry in
            let previousState: GestureState? = entry.offset > 0 ? recording.frames[entry.offset - 1].state : nil
            if entry.element.state == .trackingLost && previousState != .trackingLost { count += 1 }
        }

        var statistics: [String: CursorExperimentJointStatistics] = [:]
        for joint in jointNames {
            let allPoints = recording.frames.compactMap { frame -> CGPoint? in
                guard let sample = frame.sample, let point = sample.joint(joint) else { return nil }
                return Self.finite(point)
            }
            let stationarySegments = stationaryPointSegments(recording: recording, rows: rows) { frame, _ in
                frame.sample?.joint(joint)
            }
            statistics[joint.rawValue] = CursorExperimentJointStatistics(
                allObservations: axisStatistics(allPoints, unit: "normalized_image_units"),
                stationaryObservations: stationaryAxisStatistics(stationarySegments, joint: joint.rawValue)
            )
        }

        let palmPoints = recording.frames.compactMap { frame -> CGPoint? in
            guard let sample = frame.sample else { return nil }
            return Self.palmCentroid(sample)
        }
        let stationaryPalmSegments = stationaryPointSegments(recording: recording, rows: rows) { frame, _ in
            guard let sample = frame.sample else { return nil }
            return Self.palmCentroid(sample)
        }
        statistics["palmCentroid"] = CursorExperimentJointStatistics(
            allObservations: axisStatistics(palmPoints, unit: "normalized_image_units"),
            stationaryObservations: stationaryAxisStatistics(stationaryPalmSegments, joint: "palmCentroid")
        )

        let pointerPoints = rows.compactMap(\.rawAnchor)
        let stationaryPointerSegments = stationaryPointSegments(recording: recording, rows: rows) { _, row in
            row.rawAnchor
        }
        statistics["finalPointerAnchor"] = CursorExperimentJointStatistics(
            allObservations: axisStatistics(pointerPoints, unit: "Quartz_points"),
            stationaryObservations: stationaryAxisStatistics(stationaryPointerSegments, joint: "finalPointerAnchor", unit: "Quartz_points")
        )

        let cursorPoints = rows.compactMap(\.cursor)
        let stationaryCursorSegments = stationaryPointSegments(recording: recording, rows: rows) { _, row in
            row.cursor
        }
        statistics["cursorOutput"] = CursorExperimentJointStatistics(
            allObservations: axisStatistics(cursorPoints, unit: "Quartz_points"),
            stationaryObservations: stationaryAxisStatistics(stationaryCursorSegments, joint: "cursorOutput", unit: "Quartz_points")
        )

        let targets = targetMetrics(recording.frames, rows: rows)
        return CursorExperimentReplaySummary(
            frameCount: recording.frames.count,
            sampleCount: recording.frames.filter { $0.sample != nil }.count,
            assumedPointerStateFrames: assumedStateCount,
            trackingLossTransitionCount: trackingLossTransitionCount,
            effectiveFPS: fps,
            inferenceP50Milliseconds: percentileMetric(inference, fraction: 0.50, unit: "milliseconds", missing: "No inference timing was recorded."),
            inferenceP95Milliseconds: percentileMetric(inference, fraction: 0.95, unit: "milliseconds", missing: "No inference timing was recorded."),
            inferenceP99Milliseconds: percentileMetric(inference, fraction: 0.99, unit: "milliseconds", missing: "No inference timing was recorded."),
            mailboxWaitP50Milliseconds: percentileMetric(mailboxWait, fraction: 0.50, unit: "milliseconds", missing: "No mailbox wait timing was recorded."),
            mailboxWaitP95Milliseconds: percentileMetric(mailboxWait, fraction: 0.95, unit: "milliseconds", missing: "No mailbox wait timing was recorded."),
            mailboxWaitP99Milliseconds: percentileMetric(mailboxWait, fraction: 0.99, unit: "milliseconds", missing: "No mailbox wait timing was recorded."),
            observedMailboxDroppedFrames: mailboxDrops,
            mailboxDropsUnavailableReason: mailboxDrops == nil ? "The recording source did not provide mailbox drop counts." : nil,
            framesDroppedAtRecorderCapacity: recording.framesDroppedAtCapacity,
            framesRejectedForSourceMismatch: recording.framesRejectedForSourceMismatch,
            roiFullFrameCount: roiKnown ? fullFrameCount : nil,
            roiFallbackCount: roiKnown ? roiFallbackCount : nil,
            roiUnavailableReason: roiKnown ? nil : "No per-frame ROI metadata was recorded.",
            jointStatistics: statistics,
            targetMetrics: targets,
            cpuPercent: .unavailable("CPU requires a process sampler during the run (for example scripts/measure_process.py).", unit: "percent"),
            residentMemoryBytes: .unavailable("Resident memory requires a process sampler during the run (for example scripts/measure_process.py).", unit: "bytes"),
            calibrationProfileIsRecorded: recording.metadata.calibrationProfileIsRecorded,
            initialCursorWasAssumed: recording.metadata.initialCursorPosition == nil,
            interpretationNote: "All-observation sigma and displacement describe the full trace. Stationary statistics include only labeled, pointer-active frames and are computed within uninterrupted stationary segments; inactive/lost frames and transitions are excluded. A declared purpose does not provide target coordinates. Target and task metrics require recorded ground-truth annotations. Inference timing, CPU, memory, and mailbox drops are unavailable when not captured."
        )
    }

    private static func declaredPhase(
        for frame: CursorExperimentFrame,
        recording: CursorExperimentRecording
    ) -> CursorExperimentTaskPhase? {
        frame.groundTruth?.phase ?? recording.metadata.declaredTaskPhase
    }

    /// Collect stationary points only while the sample was actively driving the pointer.
    /// Inactive/lost frames, phase changes, tracking-ID changes, and long gaps split runs.
    private static func stationaryPointSegments(
        recording: CursorExperimentRecording,
        rows: [CursorExperimentReplayRow],
        point: (CursorExperimentFrame, CursorExperimentReplayRow) -> CGPoint?
    ) -> [[CGPoint]] {
        var segments: [[CGPoint]] = []
        var current: [CGPoint] = []
        var previousTimestamp: Double?
        var previousTrackingID: Int?
        var hasSeenActiveObservation = false
        var skipNextObservationAfterBoundary = false

        func flush(markBoundary: Bool = false) {
            if !current.isEmpty { segments.append(current) }
            current.removeAll(keepingCapacity: true)
            previousTimestamp = nil
            previousTrackingID = nil
            if markBoundary && hasSeenActiveObservation { skipNextObservationAfterBoundary = true }
        }

        for (frame, row) in zip(recording.frames, rows) {
            guard declaredPhase(for: frame, recording: recording) == .stationary,
                  frame.state == .pointer,
                  let sample = frame.sample,
                  row.motionPhase == .pointer,
                  frame.timestamp.isFinite,
                  let observed = finite(point(frame, row)) else {
                flush(markBoundary: true)
                continue
            }

            if frame.source == .camera {
                guard let motion = frame.motion,
                      motion.phase == .pointer,
                      motion.timestamp.isFinite,
                      abs(motion.timestamp - frame.timestamp) < 0.000_001 else {
                    flush(markBoundary: true)
                    continue
                }
            }

            if let previousTimestamp,
               frame.timestamp <= previousTimestamp || frame.timestamp - previousTimestamp > 0.25 {
                flush(markBoundary: true)
            }
            if let previousTrackingID, previousTrackingID != sample.trackingID {
                flush(markBoundary: true)
            }
            if skipNextObservationAfterBoundary {
                // The first valid frame after loss, a phase transition, a new hand,
                // or a long gap can still carry the previous cursor output while
                // the existing controller confirms/rebases the new anchor.
                skipNextObservationAfterBoundary = false
                hasSeenActiveObservation = true
                previousTimestamp = frame.timestamp
                previousTrackingID = sample.trackingID
                continue
            }

            current.append(observed)
            hasSeenActiveObservation = true
            previousTimestamp = frame.timestamp
            previousTrackingID = sample.trackingID
        }
        flush()
        return segments
    }

    private static func stationaryAxisStatistics(
        _ segments: [[CGPoint]],
        joint: String,
        unit: String = "normalized_image_units"
    ) -> CursorExperimentAxisStatistics {
        let validSegments = segments.map { $0.filter { $0.x.isFinite && $0.y.isFinite } }.filter { !$0.isEmpty }
        let points = validSegments.flatMap { $0 }
        guard !points.isEmpty else {
            let reason = "No valid pointer-active observations labeled stationary were recorded for \(joint)."
            return CursorExperimentAxisStatistics(
                observationCount: 0,
                unit: unit,
                sigmaX: .unavailable(reason, unit: unit),
                sigmaY: .unavailable(reason, unit: unit),
                rmsStepDisplacement: .unavailable(reason, unit: unit),
                p95StepDisplacement: .unavailable(reason, unit: unit),
                maximumStepDisplacement: .unavailable(reason, unit: unit)
            )
        }
        let count = Double(points.count)
        var sumSquaredX = 0.0
        var sumSquaredY = 0.0
        var steps: [Double] = []
        for segment in validSegments {
            let meanX = segment.reduce(0.0) { $0 + Double($1.x) } / Double(segment.count)
            let meanY = segment.reduce(0.0) { $0 + Double($1.y) } / Double(segment.count)
            sumSquaredX += segment.reduce(0.0) { $0 + pow(Double($1.x) - meanX, 2) }
            sumSquaredY += segment.reduce(0.0) { $0 + pow(Double($1.y) - meanY, 2) }
            steps.append(contentsOf: zip(segment, segment.dropFirst()).map {
                hypot(Double($1.x - $0.x), Double($1.y - $0.y))
            })
        }

        let rmsStep: CursorExperimentMetricValue
        let p95Step: CursorExperimentMetricValue
        let maxStep: CursorExperimentMetricValue
        if steps.isEmpty {
            let reason = "At least two valid pointer-active observations within one stationary segment are required."
            rmsStep = .unavailable(reason, unit: unit)
            p95Step = .unavailable(reason, unit: unit)
            maxStep = .unavailable(reason, unit: unit)
        } else {
            rmsStep = .init(value: sqrt(steps.reduce(0) { $0 + $1 * $1 } / Double(steps.count)), unit: unit)
            p95Step = .init(value: percentile(steps, fraction: 0.95), unit: unit)
            maxStep = .init(value: steps.max(), unit: unit)
        }

        return CursorExperimentAxisStatistics(
            observationCount: points.count,
            unit: unit,
            sigmaX: .init(value: sqrt(sumSquaredX / count), unit: unit),
            sigmaY: .init(value: sqrt(sumSquaredY / count), unit: unit),
            rmsStepDisplacement: rmsStep,
            p95StepDisplacement: p95Step,
            maximumStepDisplacement: maxStep
        )
    }

    private static func axisStatistics(_ points: [CGPoint], unit: String) -> CursorExperimentAxisStatistics {
        let valid = points.filter { $0.x.isFinite && $0.y.isFinite }
        guard !valid.isEmpty else {
            let reason = "No valid observations were available."
            return CursorExperimentAxisStatistics(
                observationCount: 0,
                unit: unit,
                sigmaX: .unavailable(reason, unit: unit),
                sigmaY: .unavailable(reason, unit: unit),
                rmsStepDisplacement: .unavailable("At least two valid observations are required.", unit: unit),
                p95StepDisplacement: .unavailable("At least two valid observations are required.", unit: unit),
                maximumStepDisplacement: .unavailable("At least two valid observations are required.", unit: unit)
            )
        }
        let meanX = valid.reduce(0.0) { $0 + Double($1.x) } / Double(valid.count)
        let meanY = valid.reduce(0.0) { $0 + Double($1.y) } / Double(valid.count)
        let varianceX = valid.reduce(0.0) { $0 + pow(Double($1.x) - meanX, 2) } / Double(valid.count)
        let varianceY = valid.reduce(0.0) { $0 + pow(Double($1.y) - meanY, 2) } / Double(valid.count)
        let steps = zip(valid, valid.dropFirst()).map { hypot(Double($1.x - $0.x), Double($1.y - $0.y)) }
        let displacement: CursorExperimentMetricValue
        let p95: CursorExperimentMetricValue
        let maximum: CursorExperimentMetricValue
        if steps.isEmpty {
            let reason = "At least two valid observations are required."
            displacement = .unavailable(reason, unit: unit)
            p95 = .unavailable(reason, unit: unit)
            maximum = .unavailable(reason, unit: unit)
        } else {
            displacement = .init(value: sqrt(steps.reduce(0) { $0 + $1 * $1 } / Double(steps.count)), unit: unit)
            p95 = .init(value: percentile(steps, fraction: 0.95), unit: unit)
            maximum = .init(value: steps.max(), unit: unit)
        }
        return CursorExperimentAxisStatistics(
            observationCount: valid.count,
            unit: unit,
            sigmaX: .init(value: sqrt(varianceX), unit: unit),
            sigmaY: .init(value: sqrt(varianceY), unit: unit),
            rmsStepDisplacement: displacement,
            p95StepDisplacement: p95,
            maximumStepDisplacement: maximum
        )
    }

    private static func targetMetrics(
        _ frames: [CursorExperimentFrame],
        rows: [CursorExperimentReplayRow]
    ) -> CursorExperimentTargetMetrics {
        let annotated = zip(frames, rows).filter { $0.0.groundTruth != nil && $0.1.cursor != nil }
        let errors = annotated.compactMap { frame, row -> Double? in
            guard let target = frame.groundTruth?.target, let cursor = row.cursor else { return nil }
            return distance(target, cursor)
        }
        let targetError = errors.isEmpty
            ? CursorExperimentMetricValue.unavailable("No target annotations and cursor outputs are available.", unit: "Quartz_points")
            : CursorExperimentMetricValue(value: sqrt(errors.reduce(0) { $0 + $1 * $1 } / Double(errors.count)), unit: "Quartz_points")

        var overshootsBySegment: [String: Double] = [:]
        for (frame, row) in zip(frames, rows) {
            guard let truth = frame.groundTruth,
                  let segment = truth.segmentID,
                  let start = truth.segmentStart,
                  let end = truth.segmentEnd,
                  let cursor = row.cursor else { continue }
            let dx = Double(end.x - start.x)
            let dy = Double(end.y - start.y)
            let length = hypot(dx, dy)
            guard length > 0 else { continue }
            let progress = ((Double(cursor.x - start.x) * dx) + (Double(cursor.y - start.y) * dy)) / length
            overshootsBySegment[segment] = max(overshootsBySegment[segment] ?? 0, max(0, progress - length))
        }
        let overshoots = Array(overshootsBySegment.values)
        let overshootMetrics = [0.10, 0.50, 0.90].map { fraction -> CursorExperimentMetricValue in
            guard !overshoots.isEmpty else {
                return .unavailable("No ground-truth movement segments with start and end points were recorded.", unit: "Quartz_points")
            }
            return .init(value: percentile(overshoots, fraction: fraction), unit: "Quartz_points")
        }

        let slowErrors = zip(frames, rows).compactMap { frame, row -> Double? in
            guard frame.groundTruth?.phase == .slowMove,
                  let target = frame.groundTruth?.target,
                  let cursor = row.cursor else { return nil }
            return distance(target, cursor)
        }
        let slowLag = slowErrors.isEmpty
            ? CursorExperimentMetricValue.unavailable("No explicitly target-labeled slow-movement frames were recorded.", unit: "Quartz_points")
            : CursorExperimentMetricValue(value: percentile(slowErrors, fraction: 0.95), unit: "Quartz_points")

        let fastCompletions = segmentCompletionTimes(frames, rows: rows, phase: .fastMove, tolerance: 10)
        let fastCompletion = fastCompletions.isEmpty
            ? CursorExperimentMetricValue.unavailable("No fast movement segment reached its labeled endpoint within 10 Quartz points.", unit: "milliseconds")
            : CursorExperimentMetricValue(value: percentile(fastCompletions, fraction: 0.95) * 1_000, unit: "milliseconds")

        let clickErrors = zip(frames, rows).compactMap { frame, row -> Double? in
            guard frame.groundTruth?.event == .click,
                  let target = frame.groundTruth?.target,
                  let cursor = row.cursor else { return nil }
            return distance(target, cursor)
        }
        let clickMetric = clickErrors.isEmpty
            ? CursorExperimentMetricValue.unavailable("No labeled click event with a cursor output was recorded.", unit: "Quartz_points")
            : CursorExperimentMetricValue(value: percentile(clickErrors, fraction: 0.95), unit: "Quartz_points")

        let dragSamples = zip(frames, rows).filter { frame, _ in frame.groundTruth?.phase == .dragging }
        let validDragCount = dragSamples.filter { $0.1.cursor != nil }.count
        let dragRatio = dragSamples.isEmpty
            ? CursorExperimentMetricValue.unavailable("No explicitly labeled drag frames were recorded.", unit: "ratio")
            : CursorExperimentMetricValue(value: Double(validDragCount) / Double(dragSamples.count), unit: "ratio")
        var consecutiveDragSteps: [Double] = []
        var previousDragPoint: CGPoint?
        for (_, row) in dragSamples {
            guard let point = row.cursor else { previousDragPoint = nil; continue }
            if let previousDragPoint { consecutiveDragSteps.append(distance(previousDragPoint, point)) }
            previousDragPoint = point
        }
        let dragMaximum = consecutiveDragSteps.max().map { CursorExperimentMetricValue(value: $0, unit: "Quartz_points") }
            ?? .unavailable("At least two valid cursor outputs within a labeled drag are required.", unit: "Quartz_points")

        return CursorExperimentTargetMetrics(
            targetErrorRMSPoints: targetError,
            overshootP10Points: overshootMetrics[0],
            overshootP50Points: overshootMetrics[1],
            overshootP90Points: overshootMetrics[2],
            slowMoveLagP95Points: slowLag,
            fastMoveCompletionP95Milliseconds: fastCompletion,
            cursorErrorAtClickP95Points: clickMetric,
            dragCursorContinuityRatio: dragRatio,
            dragMaximumStepPoints: dragMaximum
        )
    }

    private static func segmentCompletionTimes(
        _ frames: [CursorExperimentFrame],
        rows: [CursorExperimentReplayRow],
        phase: CursorExperimentTaskPhase,
        tolerance: Double
    ) -> [Double] {
        var segments: [String: [(CursorExperimentFrame, CursorExperimentReplayRow)]] = [:]
        for (frame, row) in zip(frames, rows) {
            guard let truth = frame.groundTruth,
                  (truth.phase == phase || (phase == .fastMove && truth.phase == .acquisition)),
                  let id = truth.segmentID else { continue }
            segments[id, default: []].append((frame, row))
        }
        return segments.values.compactMap { samples in
            guard let first = samples.first,
                  let end = first.0.groundTruth?.segmentEnd,
                  first.0.timestamp.isFinite,
                  let reached = samples.first(where: { _, row in
                      guard let cursor = row.cursor else { return false }
                      return distance(cursor, end) <= tolerance
                  }) else { return nil }
            return max(0, reached.0.timestamp - first.0.timestamp)
        }
    }

    private static func percentileMetric(_ values: [Double], fraction: Double, unit: String, missing: String) -> CursorExperimentMetricValue {
        guard !values.isEmpty else { return .unavailable(missing, unit: unit) }
        return .init(value: percentile(values, fraction: fraction), unit: unit)
    }

    private static func percentile(_ values: [Double], fraction: Double) -> Double {
        let sorted = values.filter(\.isFinite).sorted()
        guard let first = sorted.first else { return 0 }
        guard sorted.count > 1 else { return first }
        let position = min(Double(sorted.count - 1), max(0, fraction)) * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = min(sorted.count - 1, lower + 1)
        let alpha = position - Double(lower)
        return sorted[lower] * (1 - alpha) + sorted[upper] * alpha
    }

    private static func finite(_ point: CGPoint) -> CGPoint? {
        point.x.isFinite && point.y.isFinite ? point : nil
    }

    private static func finite(_ point: CGPoint?) -> CGPoint? {
        guard let point else { return nil }
        return finite(point)
    }

    private static func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> Double {
        hypot(Double(lhs.x - rhs.x), Double(lhs.y - rhs.y))
    }

    private static func palmCentroid(_ sample: HandSample) -> CGPoint? {
        let points = [HandJointName.wrist, .indexMCP, .middleMCP, .ringMCP, .littleMCP]
            .compactMap { sample.joint($0, minConfidence: 0.55) }
            .filter { $0.x.isFinite && $0.y.isFinite }
        guard points.count >= 3 else { return nil }
        return CGPoint(
            x: points.reduce(CGFloat.zero) { $0 + $1.x } / CGFloat(points.count),
            y: points.reduce(CGFloat.zero) { $0 + $1.y } / CGFloat(points.count)
        )
    }
}

/// Deterministic, target-labeled trace for smoke metrics and regression tests only.
public enum CursorExperimentSyntheticTrace {
    public static func makeRecording(fps requestedFPS: Int = 60, profile: CalibrationProfile = .init()) -> CursorExperimentRecording {
        let fps = min(120, max(10, requestedFPS))
        let duration = 7.5
        let count = Int(duration * Double(fps)) + 1
        let mapper = CoordinateMapper(profile: profile)
        var frames: [CursorExperimentFrame] = []
        frames.reserveCapacity(count)

        func mapped(_ point: CGPoint) -> CGPoint { mapper.mapToQuartzGlobal(visionPoint: point) }
        // The legacy Baseline cursor maps the index-tip anchor, which this fixture
        // places +0.12x/+0.10y from the translated hand center. Use that same screen
        // trajectory as task truth and start both controller runs at its first point.
        // This keeps target errors from measuring a preset-specific origin offset.
        let initial = mapped(CGPoint(x: 0.62, y: 0.60))
        let slowStart = initial
        let slowEnd = mapped(CGPoint(x: 0.74, y: 0.60))
        let fastEnd = mapped(CGPoint(x: 0.84, y: 0.60))
        let dragEnd = slowEnd

        for index in 0..<count {
            let timestamp = 1_000.0 + Double(index) / Double(fps)
            let time = Double(index) / Double(fps)
            let phase: CursorExperimentTaskPhase
            let segmentID: String?
            let segmentStart: CGPoint?
            let segmentEnd: CGPoint?
            let normalizedX: Double
            let state: GestureState
            var event: CursorExperimentTaskEvent?
            let clickEventIndex = Int((4.25 * Double(fps)).rounded())
            let dragStartEventIndex = Int(ceil(4.75 * Double(fps)))
            let dragEndEventIndex = Int(ceil(6.75 * Double(fps))) - 1

            if time < 1.0 {
                phase = .stationary
                segmentID = nil; segmentStart = nil; segmentEnd = nil
                normalizedX = 0.50
                state = .pointer
            } else if time < 3.5 {
                phase = .slowMove
                segmentID = "slow-1"; segmentStart = slowStart; segmentEnd = slowEnd
                let progress = (time - 1.0) / 2.5
                normalizedX = 0.50 + 0.12 * progress
                state = .pointer
            } else if time < 4.25 {
                phase = .fastMove
                segmentID = "fast-1"; segmentStart = slowEnd; segmentEnd = fastEnd
                let progress = (time - 3.5) / 0.75
                normalizedX = 0.62 + 0.10 * progress
                state = .pointer
            } else if time < 4.75 {
                phase = .acquisition
                segmentID = "fast-1"; segmentStart = slowEnd; segmentEnd = fastEnd
                normalizedX = 0.72
                state = .pointer
            } else if time < 6.75 {
                phase = .dragging
                segmentID = "drag-1"; segmentStart = fastEnd; segmentEnd = dragEnd
                let progress = (time - 4.75) / 2.0
                normalizedX = 0.72 - 0.10 * progress
                state = .dragging
            } else {
                phase = .stationary
                segmentID = nil; segmentStart = nil; segmentEnd = nil
                normalizedX = 0.62
                state = .pointer
            }
            if index == clickEventIndex { event = .click }
            if index == dragStartEventIndex { event = .dragStart }
            if index == dragEndEventIndex { event = .dragEnd }

            let base = CGPoint(x: normalizedX, y: 0.50)
            let jitter = phase == .stationary
                ? 0.0015 * sin(Double(index) * 0.73) + 0.0007 * cos(Double(index) * 0.19)
                : 0.00025 * sin(Double(index) * 0.41)
            let observed = CGPoint(x: base.x + jitter, y: base.y + 0.0008 * sin(Double(index) * 0.31))
            let sample = makeHandSample(timestamp: timestamp, center: observed)
            let target = mapped(CGPoint(x: normalizedX + 0.12, y: 0.60))
            let groundTruth = CursorExperimentGroundTruth(
                target: target,
                phase: phase,
                segmentID: segmentID,
                segmentStart: segmentStart,
                segmentEnd: segmentEnd,
                event: event
            )
            frames.append(CursorExperimentFrame(
                timestamp: timestamp,
                source: .synthetic,
                sample: sample,
                state: state,
                groundTruth: groundTruth
            ))
        }

        return CursorExperimentRecording(
            sessionID: "synthetic-cursor-trace-v1-\(fps)fps",
            startTime: Date(timeIntervalSince1970: 0),
            source: .synthetic,
            durationLimitSeconds: duration,
            capacity: count,
            metadata: CursorExperimentRecordingMetadata(
                calibrationProfile: profile,
                initialCursorPosition: initial,
                provider: "deterministic-synthetic"
            ),
            frames: frames
        )
    }

    private static func makeHandSample(timestamp: Double, center: CGPoint) -> HandSample {
        let points: [(HandJointName, CGPoint)] = [
            (.wrist, CGPoint(x: center.x, y: center.y - 0.12)),
            (.indexMCP, center),
            (.middleMCP, CGPoint(x: center.x + 0.025, y: center.y + 0.02)),
            (.ringMCP, CGPoint(x: center.x - 0.035, y: center.y + 0.005)),
            (.littleMCP, CGPoint(x: center.x - 0.075, y: center.y - 0.02)),
            (.indexTip, CGPoint(x: center.x + 0.12, y: center.y + 0.10))
        ]
        let joints = Dictionary(uniqueKeysWithValues: points.map { name, position in
            (name, HandJoint(name: name, position: position, confidence: 0.98))
        })
        return HandSample(
            hostTimestamp: timestamp,
            presentationTimeSeconds: timestamp,
            isPresentationTimeEstimated: true,
            joints: joints,
            overallConfidence: 0.98,
            estimatedHandedness: .right,
            trackingID: 1
        )
    }
}

/// Reads current recorder JSON or the older `RecordedSession.json` format.
public enum CursorExperimentRecordingCodec {
    public static func load(from url: URL, legacySource: CursorExperimentSource? = nil) throws -> CursorExperimentRecording {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let envelope = try? decoder.decode(CursorExperimentRecordingEnvelope.self, from: data) {
            if let legacySource, envelope.recording.source != legacySource {
                throw CursorExperimentReplayError.sourceMismatch
            }
            return envelope.recording
        }
        if let current = try? decoder.decode(CursorExperimentRecording.self, from: data) {
            if let legacySource, current.source != legacySource { throw CursorExperimentReplayError.sourceMismatch }
            return current
        }
        guard let legacySource else { throw CursorExperimentReplayError.legacySourceRequired }
        let session = try decoder.decode(RecordedSession.self, from: data)
        let frames = session.samples.map { sample in
            CursorExperimentFrame(
                timestamp: sample.hostTimestamp,
                source: legacySource,
                sample: sample,
                state: nil
            )
        }
        return CursorExperimentRecording(
            schemaVersion: CursorExperimentRecording.currentSchemaVersion,
            sessionID: session.sessionID,
            startTime: session.startTime,
            source: legacySource,
            durationLimitSeconds: 300,
            capacity: max(1, frames.count),
            metadata: CursorExperimentRecordingMetadata(calibrationProfileIsRecorded: false),
            frames: frames
        )
    }
}

private struct CursorExperimentRecordingEnvelope: Decodable {
    let recording: CursorExperimentRecording
}
