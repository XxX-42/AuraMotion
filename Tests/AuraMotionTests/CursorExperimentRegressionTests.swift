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
        XCTAssertNotNil(first.runs[0].summary.targetMetrics.targetErrorRMSPoints.value)
        XCTAssertNotNil(first.runs[0].summary.targetMetrics.cursorErrorAtClickP95Points.value)
        XCTAssertNotNil(first.runs[0].summary.targetMetrics.dragCursorContinuityRatio.value)
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
            XCTAssertTrue(anchor.stationaryObservations.sigmaX.unavailableReason?.contains("explicitly labeled stationary") == true)
            XCTAssertEqual(run.summary.assumedPointerStateFrames, recording.frames.count)
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
}
