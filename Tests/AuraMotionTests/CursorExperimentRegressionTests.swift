import CoreGraphics
import XCTest
@testable import AuraMotionCore

final class CursorExperimentRegressionTests: XCTestCase {
    func testBaselineReplayMatchesTheExistingRuntimeOffControllerPath() throws {
        let recording = CursorExperimentSyntheticTrace.makeRecording(fps: 20)
        let profile = recording.metadata.calibrationProfile
        let directController = CursorController(profile: profile)
        var directOutput: [CGPoint] = []

        for frame in recording.frames {
            guard let sample = frame.sample else { continue }
            if let point = directController.processHand(sample) {
                directOutput.append(point)
            }
        }

        let report = try CursorExperimentReplayEvaluator.evaluate(recording)
        let baseline = try XCTUnwrap(report.runs.first(where: { $0.mode == .baseline }))
        XCTAssertFalse(baseline.settings.hasCursorExperiments)
        XCTAssertEqual(directOutput.count, baseline.rows.filter { $0.cursor != nil }.count)

        let replayOutput = baseline.rows.compactMap(\.cursor)
        for (expected, actual) in zip(directOutput, replayOutput) {
            XCTAssertEqual(actual.x, expected.x, accuracy: 1e-9)
            XCTAssertEqual(actual.y, expected.y, accuracy: 1e-9)
        }
    }

    func testSameTraceProducesStableBaselineAndOptimizedRuns() throws {
        let recording = CursorExperimentSyntheticTrace.makeRecording(fps: 24)
        let first = try CursorExperimentReplayEvaluator.evaluate(recording)
        let second = try CursorExperimentReplayEvaluator.evaluate(recording)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.source, .synthetic)
        XCTAssertEqual(first.runs.map(\.mode), [.baseline, .optimized])
        XCTAssertEqual(first.runs[0].rows.map(\.timestamp), first.runs[1].rows.map(\.timestamp))
        XCTAssertFalse(first.runs[0].settings.hasCursorExperiments)
        XCTAssertTrue(first.runs[1].settings.hasCursorExperiments)
        XCTAssertTrue(first.runs[0].rows.contains { $0.rawAnchor != nil && $0.filtered != nil && $0.cursor != nil })
        XCTAssertTrue(first.runs[1].rows.contains { $0.rawAnchor != nil && $0.filtered != nil && $0.cursor != nil })
        let initialTarget = try XCTUnwrap(recording.frames.first?.groundTruth?.target)
        for run in first.runs {
            let initialCursor = try XCTUnwrap(run.rows.first?.cursor)
            XCTAssertLessThan(hypot(initialCursor.x - initialTarget.x, initialCursor.y - initialTarget.y), 5)
        }
        XCTAssertNotNil(first.runs[0].summary.targetMetrics.targetErrorRMSPoints.value)
        XCTAssertNotNil(first.runs[0].summary.targetMetrics.cursorErrorAtClickP95Points.value)
        XCTAssertNotNil(first.runs[0].summary.targetMetrics.dragCursorContinuityRatio.value)
    }

    func testSweepSeparatesTheIndependentCursorFeatureGroups() throws {
        let recording = CursorExperimentSyntheticTrace.makeRecording(fps: 10)
        let report = try CursorExperimentReplayEvaluator.evaluateSweep(recording)
        XCTAssertEqual(report.runs.map(\.mode), [
            .baseline, .stableRelativeOnly, .filterDragQuantization, .adaptive, .optimized, .fullSeven
        ])
        XCTAssertTrue(report.runs.allSatisfy { $0.rows.map(\.timestamp) == recording.frames.map(\.timestamp) })

        let relative = try XCTUnwrap(report.runs.first { $0.mode == .stableRelativeOnly }?.settings)
        XCTAssertTrue(relative.stableAnchorEnabled)
        XCTAssertTrue(relative.relativeMappingEnabled)
        XCTAssertFalse(relative.adaptiveDeadzoneEnabled)
        XCTAssertFalse(relative.lowSpeedQuantizationEnabled)
        XCTAssertFalse(relative.separateDragTuningEnabled)
        XCTAssertFalse(relative.optimizedOneEuroEnabled)
        XCTAssertFalse(relative.velocityGainEnabled)

        let filtered = try XCTUnwrap(report.runs.first { $0.mode == .filterDragQuantization }?.settings)
        XCTAssertTrue(filtered.stableAnchorEnabled && filtered.relativeMappingEnabled)
        XCTAssertTrue(filtered.lowSpeedQuantizationEnabled && filtered.separateDragTuningEnabled)
        XCTAssertTrue(filtered.optimizedOneEuroEnabled)
        XCTAssertFalse(filtered.adaptiveDeadzoneEnabled)
        XCTAssertFalse(filtered.velocityGainEnabled)

        let adaptive = try XCTUnwrap(report.runs.first { $0.mode == .adaptive }?.settings)
        XCTAssertTrue(adaptive.adaptiveDeadzoneEnabled)
        XCTAssertFalse(adaptive.velocityGainEnabled)

        let optimized = try XCTUnwrap(report.runs.first { $0.mode == .optimized }?.settings)
        XCTAssertTrue(optimized.hasCursorExperiments)
        XCTAssertFalse(optimized.velocityGainEnabled)
        XCTAssertFalse(optimized.visionROIEnabled)
        XCTAssertFalse(optimized.mediaPipeBenchmarkEnabled)

        let fullSeven = try XCTUnwrap(report.runs.first { $0.mode == .fullSeven }?.settings)
        XCTAssertTrue(fullSeven.velocityGainEnabled)
    }

    func testRecorderUsesBoundedRingAndRejectsMixedSources() throws {
        let recorder = CursorExperimentMetricsRecorder(capacity: 3)
        recorder.start(duration: 30, source: .synthetic)
        for timestamp in 0..<5 {
            XCTAssertTrue(recorder.record(frame: frame(Double(timestamp), source: .synthetic)))
        }
        XCTAssertFalse(recorder.record(frame: frame(5, source: .camera)))

        let recording = try XCTUnwrap(recorder.stop())
        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(recording.frames.map(\.timestamp), [2, 3, 4])
        XCTAssertEqual(recording.framesDroppedAtCapacity, 2)
        XCTAssertEqual(recording.framesRejectedForSourceMismatch, 1)
        XCTAssertNil(recorder.stop())
    }

    func testRecorderStopsAtDurationAndResetReleasesSnapshot() throws {
        let recorder = CursorExperimentMetricsRecorder(capacity: 10)
        recorder.start(duration: 1, source: .camera)
        XCTAssertTrue(recorder.record(frame: frame(10, source: .camera)))
        XCTAssertTrue(recorder.record(frame: frame(10.5, source: .camera)))
        XCTAssertFalse(recorder.record(frame: frame(11, source: .camera)))
        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(try XCTUnwrap(recorder.stop()).frames.count, 2)
        recorder.reset()
        XCTAssertNil(recorder.snapshot())
    }

    func testUnlabeledCameraTraceDoesNotInventAccuracyOrStationaryJitter() throws {
        guard let url = Bundle.module.url(forResource: "clean_pinch_click", withExtension: "json", subdirectory: "Fixtures") else {
            XCTFail("Fixture clean_pinch_click.json not found")
            return
        }
        let recording = try CursorExperimentRecordingCodec.load(from: url, legacySource: .camera)
        let report = try CursorExperimentReplayEvaluator.evaluate(recording)

        XCTAssertEqual(report.source, .camera)
        XCTAssertFalse(recording.metadata.calibrationProfileIsRecorded)
        for run in report.runs {
            XCTAssertNil(run.summary.targetMetrics.targetErrorRMSPoints.value)
            XCTAssertNotNil(run.summary.targetMetrics.targetErrorRMSPoints.unavailableReason)
            XCTAssertNil(run.summary.targetMetrics.overshootP50Points.value)
            XCTAssertNil(run.summary.targetMetrics.slowMoveLagP95Points.value)
            XCTAssertNil(run.summary.targetMetrics.fastMoveCompletionP95Milliseconds.value)
            XCTAssertNil(run.summary.targetMetrics.cursorErrorAtClickP95Points.value)
            let anchor = try XCTUnwrap(run.summary.jointStatistics["finalPointerAnchor"])
            XCTAssertNil(anchor.stationaryObservations.sigmaX.value)
            XCTAssertTrue(anchor.stationaryObservations.sigmaX.unavailableReason?.contains("labeled stationary") == true)
            XCTAssertEqual(run.summary.assumedPointerStateFrames, recording.frames.count)
        }
    }

    func testDeclaredStationaryPurposeLabelsStationaryStatsWithoutCreatingTargets() throws {
        let frames = (0..<8).map { index -> CursorExperimentFrame in
            let timestamp = 20 + Double(index) / 30
            let joints: [HandJointName: HandJoint] = [
                .wrist: HandJoint(name: .wrist, position: CGPoint(x: 0.50, y: 0.20), confidence: 0.9),
                .indexMCP: HandJoint(name: .indexMCP, position: CGPoint(x: 0.40, y: 0.40), confidence: 0.9),
                .middleMCP: HandJoint(name: .middleMCP, position: CGPoint(x: 0.50, y: 0.40), confidence: 0.9),
                .ringMCP: HandJoint(name: .ringMCP, position: CGPoint(x: 0.60, y: 0.40), confidence: 0.9),
                .littleMCP: HandJoint(name: .littleMCP, position: CGPoint(x: 0.70, y: 0.40), confidence: 0.9),
                .indexTip: HandJoint(name: .indexTip, position: CGPoint(x: 0.40, y: 0.70), confidence: 0.9)
            ]
            let sample = HandSample(
                hostTimestamp: timestamp,
                presentationTimeSeconds: timestamp,
                isPresentationTimeEstimated: false,
                joints: joints,
                overallConfidence: 0.9,
                estimatedHandedness: .right,
                trackingID: 1
            )
            return CursorExperimentFrame(timestamp: timestamp, source: .synthetic, sample: sample, state: .pointer)
        }
        let recording = CursorExperimentRecording(
            sessionID: "declared-stationary-purpose",
            startTime: Date(timeIntervalSince1970: 0),
            source: .synthetic,
            durationLimitSeconds: 1,
            capacity: frames.count,
            metadata: CursorExperimentRecordingMetadata(declaredTaskPhase: .stationary),
            frames: frames
        )

        let report = try CursorExperimentReplayEvaluator.evaluate(recording)
        for run in report.runs {
            let anchor = try XCTUnwrap(run.summary.jointStatistics["finalPointerAnchor"])
            XCTAssertEqual(anchor.stationaryObservations.observationCount, frames.count)
            XCTAssertNotNil(anchor.stationaryObservations.sigmaX.value)
            XCTAssertTrue(run.rows.allSatisfy { $0.target == nil && $0.targetPhase == .stationary })
            XCTAssertNil(run.summary.targetMetrics.targetErrorRMSPoints.value)
        }
    }

    func testStationaryMetricsRequireActivePointerAndSplitOnLossIdentityAndGaps() throws {
        let definitions: [(time: Double, state: GestureState, trackingID: Int?, x: CGFloat, phase: CursorMotionPhase)] = [
            (100.000, .pointer, 1, 0.500, .pointer),
            (100.033, .pointer, 1, 0.501, .pointer),
            (100.066, .trackingLost, nil, 0.502, .frozen),
            (100.099, .pointer, 2, 0.700, .pointer),
            (100.132, .pointer, 2, 0.701, .pointer),
            (100.165, .pointer, 2, 0.702, .frozen),
            (100.198, .pointer, 2, 0.703, .pointer),
            (100.600, .pointer, 2, 0.704, .pointer),
            (100.633, .pointer, 2, 0.705, .pointer)
        ]
        let frames = definitions.map { definition -> CursorExperimentFrame in
            let sample = definition.trackingID.map {
                stationarySample(timestamp: definition.time, centerX: definition.x, trackingID: $0)
            }
            let motion = definition.phase == .pointer
                ? CursorExperimentMotionSample(
                    timestamp: definition.time,
                    rawAnchor: CGPoint(x: definition.x * 1_000, y: 500),
                    filtered: CGPoint(x: definition.x * 1_000, y: 500),
                    cursor: CGPoint(x: definition.x * 1_000, y: 500),
                    speed: 0,
                    deadzone: 1,
                    gain: 1,
                    phase: .pointer
                )
                : CursorExperimentMotionSample(
                    timestamp: definition.time,
                    rawAnchor: CGPoint(x: definition.x * 1_000, y: 500),
                    filtered: CGPoint(x: definition.x * 1_000, y: 500),
                    cursor: CGPoint(x: definition.x * 1_000, y: 500),
                    speed: 0,
                    deadzone: 0,
                    gain: 1,
                    phase: .frozen
                )
            return CursorExperimentFrame(
                timestamp: definition.time,
                source: .camera,
                sample: sample,
                state: definition.state,
                motion: motion
            )
        }
        let recording = CursorExperimentRecording(
            sessionID: "stationary-active-segments",
            startTime: Date(timeIntervalSince1970: 0),
            source: .camera,
            durationLimitSeconds: 1,
            capacity: frames.count,
            metadata: CursorExperimentRecordingMetadata(declaredTaskPhase: .stationary),
            frames: frames
        )

        let report = try CursorExperimentReplayEvaluator.evaluate(recording)
        for run in report.runs {
            let cursorStats = try XCTUnwrap(run.summary.jointStatistics["cursorOutput"]?.stationaryObservations)
            let tipStats = try XCTUnwrap(run.summary.jointStatistics[HandJointName.indexTip.rawValue]?.stationaryObservations)
            let cursorPath = run.rows.map { row in
                row.cursor.map { String(format: "%.1f", Double($0.x)) } ?? "nil"
            }.joined(separator: ",")
            XCTAssertEqual(cursorStats.observationCount, 4)
            XCTAssertEqual(tipStats.observationCount, 4)
            XCTAssertLessThan(cursorStats.sigmaX.value ?? .infinity, 20, "\(run.mode.rawValue): \(cursorPath)")
            XCTAssertLessThan(tipStats.sigmaX.value ?? .infinity, 0.01)
            XCTAssertLessThan(cursorStats.maximumStepDisplacement.value ?? .infinity, 20, "\(run.mode.rawValue): \(cursorPath)")
            XCTAssertEqual(run.summary.trackingLossTransitionCount, 1)
            XCTAssertNil(run.summary.targetMetrics.targetErrorRMSPoints.value)
        }
    }

    func testIdleAndFrozenCameraFramesDoNotCountAsStationaryJitter() throws {
        let timestamp = 50.0
        let sample = stationarySample(timestamp: timestamp, centerX: 0.5, trackingID: 3)
        let frame = CursorExperimentFrame(
            timestamp: timestamp,
            source: .camera,
            sample: sample,
            state: .idle,
            motion: CursorExperimentMotionSample(
                timestamp: timestamp,
                rawAnchor: CGPoint(x: 960, y: 540),
                filtered: CGPoint(x: 960, y: 540),
                cursor: CGPoint(x: 960, y: 540),
                speed: 0,
                deadzone: 0,
                gain: 1,
                phase: .frozen
            )
        )
        let recording = CursorExperimentRecording(
            sessionID: "idle-is-not-stationary-jitter",
            startTime: Date(timeIntervalSince1970: 0),
            source: .camera,
            durationLimitSeconds: 1,
            capacity: 1,
            metadata: CursorExperimentRecordingMetadata(declaredTaskPhase: .stationary),
            frames: [frame]
        )

        let report = try CursorExperimentReplayEvaluator.evaluate(recording)
        for run in report.runs {
            let stats = try XCTUnwrap(run.summary.jointStatistics["cursorOutput"]?.stationaryObservations)
            XCTAssertEqual(stats.observationCount, 0)
            XCTAssertNil(stats.sigmaX.value)
            XCTAssertTrue(stats.sigmaX.unavailableReason?.contains("pointer-active") == true)
        }
    }

    func testExportIncludesRequiredReplayColumnsAndBothModes() throws {
        let recording = CursorExperimentSyntheticTrace.makeRecording(fps: 10)
        let report = try CursorExperimentReplayEvaluator.evaluate(recording)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("replay.csv")

        _ = try CursorExperimentMetricsExporter.write(report, to: destination)
        let csv = try String(contentsOf: destination, encoding: .utf8)
        XCTAssertTrue(csv.contains("timestamp,source,mode,raw_anchor_x,raw_anchor_y,filtered_x,filtered_y,cursor_x,cursor_y,speed,deadzone,gain,state"))
        XCTAssertTrue(csv.contains("synthetic,baseline"))
        XCTAssertTrue(csv.contains("synthetic,optimized"))
    }

    private func frame(_ timestamp: Double, source: CursorExperimentSource) -> CursorExperimentFrame {
        CursorExperimentFrame(timestamp: timestamp, source: source, sample: nil)
    }

    private func stationarySample(timestamp: Double, centerX: CGFloat, trackingID: Int) -> HandSample {
        let joints: [HandJointName: HandJoint] = [
            .wrist: HandJoint(name: .wrist, position: CGPoint(x: centerX, y: 0.30), confidence: 0.9),
            .indexMCP: HandJoint(name: .indexMCP, position: CGPoint(x: centerX, y: 0.50), confidence: 0.9),
            .middleMCP: HandJoint(name: .middleMCP, position: CGPoint(x: centerX + 0.04, y: 0.51), confidence: 0.9),
            .ringMCP: HandJoint(name: .ringMCP, position: CGPoint(x: centerX - 0.04, y: 0.50), confidence: 0.9),
            .littleMCP: HandJoint(name: .littleMCP, position: CGPoint(x: centerX - 0.08, y: 0.48), confidence: 0.9),
            .indexTip: HandJoint(name: .indexTip, position: CGPoint(x: centerX + 0.12, y: 0.60), confidence: 0.9)
        ]
        return HandSample(
            hostTimestamp: timestamp,
            presentationTimeSeconds: timestamp,
            isPresentationTimeEstimated: false,
            joints: joints,
            overallConfidence: 0.9,
            estimatedHandedness: .right,
            trackingID: trackingID
        )
    }
}
