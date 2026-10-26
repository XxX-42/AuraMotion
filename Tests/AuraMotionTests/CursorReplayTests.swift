import XCTest
@testable import AuraMotionCore

final class CursorReplayTests: XCTestCase {
    func testKnownSyntheticTraceCarriesTargetsAndNoFakeInferenceTiming() throws {
        let recording = CursorExperimentSyntheticTrace.makeRecording(fps: 30)
        XCTAssertEqual(recording.source, .synthetic)
        XCTAssertTrue(recording.frames.allSatisfy { $0.source == .synthetic && $0.groundTruth != nil })
        XCTAssertTrue(recording.frames.allSatisfy { $0.inferenceDurationMilliseconds == nil })

        let report = try CursorExperimentReplayEvaluator.evaluate(recording)
        for run in report.runs {
            XCTAssertNil(run.summary.inferenceP50Milliseconds.value)
            XCTAssertTrue(run.summary.inferenceP50Milliseconds.unavailableReason?.contains("No inference timing") == true)
            XCTAssertNotNil(run.summary.effectiveFPS.value)
            XCTAssertEqual(run.summary.effectiveFPS.value ?? 0, 30, accuracy: 1e-9)
        }
    }

    func testRecordedTimingPercentilesAndFrameMetadataAreSummarized() throws {
        let frames: [CursorExperimentFrame] = (0..<5).map { index in
            let timestamp = 100.0 + Double(index) / 10.0
            let fullFrame = index == 0
            let roi = CursorExperimentROI(
                x: 0,
                y: 0,
                width: fullFrame ? 1.0 : 0.5,
                height: 1.0,
                usedFullFrame: fullFrame,
                fallbackReason: index == 4 ? "hand-loss" : nil
            )
            let inferenceMilliseconds = Double(index + 1)
            let mailboxMilliseconds = Double((index + 1) * 2)
            return CursorExperimentFrame(
                timestamp: timestamp,
                source: .camera,
                sample: nil,
                inferenceDurationMilliseconds: inferenceMilliseconds,
                mailboxWaitMilliseconds: mailboxMilliseconds,
                droppedFrames: index,
                roi: roi
            )
        }
        let recording = CursorExperimentRecording(
            sessionID: "timing-summary",
            startTime: Date(timeIntervalSince1970: 0),
            source: .camera,
            durationLimitSeconds: 1,
            capacity: frames.count,
            metadata: .init(),
            frames: frames
        )
        let report = try CursorExperimentReplayEvaluator.evaluate(recording)

        for run in report.runs {
            XCTAssertEqual(run.summary.effectiveFPS.value ?? 0, 10, accuracy: 1e-8)
            XCTAssertEqual(run.summary.inferenceP50Milliseconds.value ?? 0, 3, accuracy: 1e-8)
            XCTAssertEqual(run.summary.inferenceP95Milliseconds.value ?? 0, 4.8, accuracy: 1e-8)
            XCTAssertEqual(run.summary.inferenceP99Milliseconds.value ?? 0, 4.96, accuracy: 1e-8)
            XCTAssertEqual(run.summary.mailboxWaitP50Milliseconds.value ?? 0, 6, accuracy: 1e-8)
            XCTAssertEqual(run.summary.observedMailboxDroppedFrames, 4)
            XCTAssertEqual(run.summary.roiFullFrameCount, 1)
            XCTAssertEqual(run.summary.roiFallbackCount, 1)
        }
    }

    func testRecordingJSONRoundTripsSourceAndLandmarks() throws {
        let original = CursorExperimentSyntheticTrace.makeRecording(fps: 10)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("recording.json")
        _ = try CursorExperimentMetricsExporter.writeJSON(original, to: url)

        let decoded = try CursorExperimentRecordingCodec.load(from: url)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.source, .synthetic)
        XCTAssertEqual(decoded.frames.first?.sample, original.frames.first?.sample)
    }

    func testLiveExportBundleIncludesLandmarksAndBothEvaluations() throws {
        let recording = CursorExperimentSyntheticTrace.makeRecording(fps: 10)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("experiment.json")

        _ = try CursorExperimentMetricsExporter.writeBundle(recording, to: url)
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(CursorExperimentExportDocument.self, from: data)
        XCTAssertEqual(document.recording, recording)
        XCTAssertEqual(document.replay.runs.map(\.mode), [.baseline, .optimized])
        XCTAssertEqual(document.recording.frames.count, recording.frames.count)
    }

    func testLegacySessionRequiresExplicitSource() throws {
        guard let url = Bundle.module.url(forResource: "sudden_hand_loss", withExtension: "json", subdirectory: "Fixtures") else {
            XCTFail("Fixture sudden_hand_loss.json not found")
            return
        }
        XCTAssertThrowsError(try CursorExperimentRecordingCodec.load(from: url)) { error in
            XCTAssertEqual(error as? CursorExperimentReplayError, .legacySourceRequired)
        }
        let imported = try CursorExperimentRecordingCodec.load(from: url, legacySource: .camera)
        XCTAssertEqual(imported.source, .camera)
        XCTAssertEqual(imported.frames.count, 4)
    }
}
