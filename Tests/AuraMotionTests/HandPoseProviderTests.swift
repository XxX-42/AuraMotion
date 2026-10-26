import Foundation
import CoreVideo
import CoreMedia
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

    func testSlowProviderKeepsMailboxIngressToOneScheduledDrain() throws {
        let provider = SlowFirstInferenceProvider()
        let worker = VisionInferenceWorker(providerFactory: { _, _ in provider })
        let mailbox = FrameMailbox()
        let carrier = try makeCarrier(timestamp: 1)

        mailbox.postFrame(carrier)
        worker.processMailbox(mailbox: mailbox)
        XCTAssertEqual(provider.firstInferenceEntered.wait(timeout: .now() + 2), .success)

        for index in 0..<10_000 {
            let next = SampleCarrier(
                buffer: carrier.buffer,
                hostPresentationTime: Double(index + 2),
                isEstimatedTime: false
            )
            mailbox.postFrame(next)
            worker.processMailbox(mailbox: mailbox)
        }

        XCTAssertEqual(worker.mailboxDrainSubmissionCountForTesting, 1)

        let reconfigured = expectation(description: "provider reconfiguration completes")
        worker.reconfigure(CursorExperimentSettings()) {
            reconfigured.fulfill()
        }
        provider.resumeFirstInference.signal()
        wait(for: [reconfigured], timeout: 3)

        XCTAssertLessThanOrEqual(worker.mailboxDrainSubmissionCountForTesting, 2)
        XCTAssertEqual(mailbox.droppedFrames, 9_999)
    }

    private func makeCarrier(timestamp: Double) throws -> SampleCarrier {
        var pixelBuffer: CVPixelBuffer?
        XCTAssertEqual(
            CVPixelBufferCreate(kCFAllocatorDefault, 32, 32, kCVPixelFormatType_32BGRA, nil, &pixelBuffer),
            kCVReturnSuccess
        )
        let image = try XCTUnwrap(pixelBuffer)
        var formatDescription: CMVideoFormatDescription?
        XCTAssertEqual(
            CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: image,
                formatDescriptionOut: &formatDescription
            ),
            noErr
        )
        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMTime(seconds: timestamp, preferredTimescale: 600),
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        XCTAssertEqual(
            CMSampleBufferCreateReadyWithImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: image,
                formatDescription: try XCTUnwrap(formatDescription),
                sampleTiming: &timing,
                sampleBufferOut: &sampleBuffer
            ),
            noErr
        )
        return SampleCarrier(
            buffer: try XCTUnwrap(sampleBuffer),
            hostPresentationTime: timestamp,
            isEstimatedTime: false
        )
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

private final class SlowFirstInferenceProvider: HandPoseProvider, @unchecked Sendable {
    let identifier = "slow-test"
    let firstInferenceEntered = DispatchSemaphore(value: 0)
    let resumeFirstInference = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var inferenceCount = 0

    var statusSnapshot: HandPoseProviderStatusSnapshot {
        HandPoseProviderStatusSnapshot(
            providerIdentifier: identifier,
            roiEnabled: false,
            currentROI: VisionROI.fullFrame
        )
    }

    func configure(settings: CursorExperimentSettings) {}
    func stop() {}
    func reset() {}

    func infer(
        pixelBuffer: CVPixelBuffer,
        hostTimestamp: TimeInterval,
        presentationTime: Double,
        isEstimatedTime: Bool,
        trackingID: Int,
        isMirrored: Bool
    ) -> HandPoseProviderOutput {
        lock.lock()
        inferenceCount += 1
        let shouldBlock = inferenceCount == 1
        lock.unlock()

        if shouldBlock {
            firstInferenceEntered.signal()
            _ = resumeFirstInference.wait(timeout: .now() + 3)
        }
        return HandPoseProviderOutput(
            sample: nil,
            outcome: .noHand,
            regionOfInterest: VisionROI.fullFrame,
            usedFullFrame: true
        )
    }
}
