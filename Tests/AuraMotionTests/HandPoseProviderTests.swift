import Foundation
import CoreVideo
import XCTest
@testable import AuraMotionCore

final class HandPoseProviderTests: XCTestCase {
    func testVisionIsTheDefaultProviderWithFullFrameInference() {
        let worker = VisionInferenceWorker()

        XCTAssertEqual(worker.statusSnapshot.activeProviderIdentifier, "vision")
        XCTAssertFalse(worker.statusSnapshot.roiEnabled)
        XCTAssertEqual(worker.statusSnapshot.currentROI, VisionROI.fullFrame)
        XCTAssertFalse(worker.statusSnapshot.requestedMediaPipeBenchmark)
    }

    func testMediaPipeIsExplicitlyUnavailableWithoutARealBackend() {
        XCTAssertFalse(MediaPipeHandPoseProvider.isAvailable)
        XCTAssertNotNil(MediaPipeHandPoseProvider.unavailabilityReason)

        let provider = MediaPipeHandPoseProvider()
        XCTAssertFalse(provider.statusSnapshot.isAvailable)
        XCTAssertEqual(provider.statusSnapshot.unavailabilityReason, MediaPipeHandPoseProvider.unavailabilityReason)
    }

    func testReconfigureResetsOldProviderAndCompletesAfterReplacementIsReady() throws {
        let registry = FakeProviderRegistry()
        let worker = VisionInferenceWorker(providerFactory: { _, _ in registry.makeProvider() })
        let original = try XCTUnwrap(registry.providers.first)
        var settings = CursorExperimentSettings()
        settings.visionROIEnabled = true
        settings.mediaPipeBenchmarkEnabled = true

        let completion = DispatchSemaphore(value: 0)
        worker.reconfigure(settings) {
            completion.signal()
        }

        XCTAssertEqual(completion.wait(timeout: .now() + 2), .success)
        let replacement = try XCTUnwrap(registry.providers.last)

        XCTAssertEqual(original.stopCount, 1)
        XCTAssertEqual(original.resetCount, 1)
        XCTAssertEqual(replacement.configureCount, 1)
        XCTAssertEqual(worker.statusSnapshot.activeProviderIdentifier, replacement.identifier)
        XCTAssertTrue(worker.statusSnapshot.roiEnabled)
        XCTAssertTrue(worker.statusSnapshot.requestedMediaPipeBenchmark)
        XCTAssertFalse(worker.statusSnapshot.mediaPipeBenchmarkAvailable)
        XCTAssertNotNil(worker.statusSnapshot.mediaPipeUnavailabilityReason)
        XCTAssertEqual(worker.statusSnapshot.configurationSequence, 1)
    }
}

private final class FakeProviderRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [FakeHandPoseProvider] = []

    var providers: [FakeHandPoseProvider] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func makeProvider() -> FakeHandPoseProvider {
        lock.lock()
        defer { lock.unlock() }
        let provider = FakeHandPoseProvider(identifier: "fake-\(storage.count)")
        storage.append(provider)
        return provider
    }
}

private final class FakeHandPoseProvider: HandPoseProvider, @unchecked Sendable {
    let identifier: String
    private let lock = NSLock()
    private var _stopCount = 0
    private var _resetCount = 0
    private var _configureCount = 0
    private var _roiEnabled = false

    init(identifier: String) {
        self.identifier = identifier
    }

    var stopCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _stopCount
    }

    var resetCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _resetCount
    }

    var configureCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _configureCount
    }

    var statusSnapshot: HandPoseProviderStatusSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return HandPoseProviderStatusSnapshot(
            providerIdentifier: identifier,
            roiEnabled: _roiEnabled,
            currentROI: VisionROI.fullFrame
        )
    }

    func configure(settings: CursorExperimentSettings) {
        lock.lock()
        _configureCount += 1
        _roiEnabled = settings.visionROIEnabled
        lock.unlock()
    }

    func stop() {
        lock.lock()
        _stopCount += 1
        lock.unlock()
    }

    func reset() {
        lock.lock()
        _resetCount += 1
        lock.unlock()
    }

    func infer(
        pixelBuffer: CVPixelBuffer,
        hostTimestamp: TimeInterval,
        presentationTime: Double,
        isEstimatedTime: Bool,
        trackingID: Int,
        isMirrored: Bool
    ) -> HandPoseProviderOutput {
        HandPoseProviderOutput(
            sample: nil,
            outcome: .noHand,
            regionOfInterest: VisionROI.fullFrame,
            usedFullFrame: true
        )
    }
}
