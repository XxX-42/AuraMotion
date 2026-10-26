import QuartzCore
import Foundation
import Vision
import CoreMedia
import CoreGraphics

public protocol VisionInferenceWorkerDelegate: AnyObject, Sendable {
    func visionWorker(
        _ worker: VisionInferenceWorker,
        didProduce sample: HandSample?,
        carrier: SampleCarrier,
        inferenceDuration: TimeInterval,
        mailboxWaitDuration: TimeInterval
    )
}

public struct VisionWorkerStatusSnapshot: Sendable, Equatable {
    public let activeProviderIdentifier: String
    public let requestedMediaPipeBenchmark: Bool
    public let mediaPipeBenchmarkAvailable: Bool
    public let mediaPipeUnavailabilityReason: String?
    public let roiEnabled: Bool
    public let currentROI: CGRect
    public let lastDiagnostics: HandPoseProviderDiagnostics?
    public let configurationSequence: UInt64

    public init(
        activeProviderIdentifier: String,
        requestedMediaPipeBenchmark: Bool,
        mediaPipeBenchmarkAvailable: Bool,
        mediaPipeUnavailabilityReason: String?,
        roiEnabled: Bool,
        currentROI: CGRect,
        lastDiagnostics: HandPoseProviderDiagnostics?,
        configurationSequence: UInt64
    ) {
        self.activeProviderIdentifier = activeProviderIdentifier
        self.requestedMediaPipeBenchmark = requestedMediaPipeBenchmark
        self.mediaPipeBenchmarkAvailable = mediaPipeBenchmarkAvailable
        self.mediaPipeUnavailabilityReason = mediaPipeUnavailabilityReason
        self.roiEnabled = roiEnabled
        self.currentROI = currentROI
        self.lastDiagnostics = lastDiagnostics
        self.configurationSequence = configurationSequence
    }
}

/// Executes one provider inference at a time on a dedicated .userInitiated queue.
/// Frame flow continues to use the existing bounded latest-frame FrameMailbox.
public final class VisionInferenceWorker: @unchecked Sendable {
    typealias ProviderFactory = @Sendable (Int, CursorExperimentSettings) -> any HandPoseProvider

    private let visionQueue = DispatchQueue(label: "com.auramotion.vision", qos: .userInitiated)
    private let providerFactory: ProviderFactory
    private var provider: any HandPoseProvider
    private var activeSettings: CursorExperimentSettings
    private var activeConfigurationSequence: UInt64 = 0

    private let stateLock = NSLock()
    private var requestedConfigurationSequence: UInt64 = 0
    private var mirroredSnapshot = true
    private var statusStorage: VisionWorkerStatusSnapshot
    private var isMailboxDrainScheduledOrRunning = false
    private var mailboxWakeRequested = false
    private var mailboxDrainSubmissionCount: UInt64 = 0

    public let activeRevision: Int
    public weak var delegate: VisionInferenceWorkerDelegate?

    /// A lock-protected property retained for existing AppEnvironment callers.
    public var isMirrored: Bool {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return mirroredSnapshot
        }
        set {
            stateLock.lock()
            mirroredSnapshot = newValue
            stateLock.unlock()
        }
    }

    /// An immutable thread-safe snapshot for diagnostics and experiment reporting.
    public var statusSnapshot: VisionWorkerStatusSnapshot {
        stateLock.lock()
        defer { stateLock.unlock() }
        return statusStorage
    }

    var mailboxDrainSubmissionCountForTesting: UInt64 {
        stateLock.lock()
        defer { stateLock.unlock() }
        return mailboxDrainSubmissionCount
    }

    public convenience init() {
        self.init(providerFactory: Self.makeProvider)
    }

    init(providerFactory: @escaping ProviderFactory) {
        let revision = VisionRevisionPolicy.selectActiveRevision()
        let settings = CursorExperimentSettings().normalized()
        let provider = providerFactory(revision, settings)

        activeRevision = revision
        self.providerFactory = providerFactory
        self.provider = provider
        activeSettings = settings
        statusStorage = VisionWorkerStatusSnapshot(
            activeProviderIdentifier: provider.identifier,
            requestedMediaPipeBenchmark: false,
            mediaPipeBenchmarkAvailable: MediaPipeHandPoseProvider.isAvailable,
            mediaPipeUnavailabilityReason: MediaPipeHandPoseProvider.unavailabilityReason,
            roiEnabled: provider.statusSnapshot.roiEnabled,
            currentROI: provider.statusSnapshot.currentROI,
            lastDiagnostics: nil,
            configurationSequence: 0
        )
    }

    private static func makeProvider(
        revision: Int,
        settings: CursorExperimentSettings
    ) -> any HandPoseProvider {
        if settings.mediaPipeBenchmarkEnabled, MediaPipeHandPoseProvider.isAvailable {
            return MediaPipeHandPoseProvider()
        }
        return VisionHandPoseProvider(revision: revision)
    }

    /// Applies provider configuration on the same serial queue as inference.
    /// Completion runs after the prior request has ended and the old provider has
    /// been stopped/reset, so callers can safely rebase interaction state there.
    public func reconfigure(
        _ settings: CursorExperimentSettings,
        completion: @escaping @Sendable () -> Void
    ) {
        let normalizedSettings = settings.normalized()
        stateLock.lock()
        requestedConfigurationSequence &+= 1
        let sequence = requestedConfigurationSequence
        stateLock.unlock()

        visionQueue.async { [self] in
            provider.stop()
            provider.reset()

            let replacement = providerFactory(activeRevision, normalizedSettings)
            replacement.configure(settings: normalizedSettings)
            provider = replacement
            activeSettings = normalizedSettings
            activeConfigurationSequence = sequence
            publishStatus(lastDiagnostics: nil)
            completion()
        }
    }

    /// Triggers the worker to evaluate the latest waiting frame from the mailbox.
    public func processMailbox(mailbox: FrameMailbox) {
        stateLock.lock()
        mailboxWakeRequested = true
        guard !isMailboxDrainScheduledOrRunning else {
            stateLock.unlock()
            return
        }
        isMailboxDrainScheduledOrRunning = true
        mailboxWakeRequested = false
        stateLock.unlock()
        enqueueMailboxDrain(mailbox: mailbox)
    }

    private func enqueueMailboxDrain(mailbox: FrameMailbox) {
        stateLock.lock()
        mailboxDrainSubmissionCount &+= 1
        stateLock.unlock()

        visionQueue.async { [weak self] in
            guard let self else { return }
            if let carrier = mailbox.beginNextInference() {
                self.executeInference(carrier: carrier, mailbox: mailbox)
            }
            self.finishMailboxDrain(mailbox: mailbox)
        }
    }

    private func finishMailboxDrain(mailbox: FrameMailbox) {
        stateLock.lock()
        let shouldDrainAgain = mailboxWakeRequested
        if shouldDrainAgain {
            mailboxWakeRequested = false
        } else {
            isMailboxDrainScheduledOrRunning = false
        }
        stateLock.unlock()

        // Keep one scheduled/running flag set across the handoff. A capture
        // wake arriving here either sets mailboxWakeRequested before this lock,
        // or sees the flag clear afterward and schedules the next drain itself.
        if shouldDrainAgain {
            enqueueMailboxDrain(mailbox: mailbox)
        }
    }

    private func executeInference(carrier: SampleCarrier, mailbox: FrameMailbox) {
        var currentCarrier = carrier

        while true {
            let inferenceSequence = activeConfigurationSequence
            guard inferenceSequence == requestedSequenceSnapshot() else {
                // Drop a queued old-configuration frame and release the mailbox
                // before the serialized provider replacement runs.
                mailbox.clear()
                return
            }

            let tStart = CACurrentMediaTime()
            let mailboxWait = max(0, tStart - currentCarrier.hostPresentationTime)
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(currentCarrier.buffer) else {
                if inferenceSequence != requestedSequenceSnapshot() {
                    mailbox.clear()
                    return
                }
                guard let next = mailbox.endInferenceAndAcquireNext() else { return }
                currentCarrier = next
                continue
            }

            let output = provider.infer(
                pixelBuffer: pixelBuffer,
                hostTimestamp: currentCarrier.hostPresentationTime,
                presentationTime: currentCarrier.hostPresentationTime,
                isEstimatedTime: currentCarrier.isEstimatedTime,
                trackingID: 1,
                isMirrored: isMirrored
            )

            let inferenceDuration = max(0, CACurrentMediaTime() - tStart)
            let diagnostics = HandPoseProviderDiagnostics(
                providerIdentifier: provider.identifier,
                outcome: output.outcome,
                inferenceDuration: inferenceDuration,
                mailboxWaitDuration: mailboxWait,
                regionOfInterest: output.regionOfInterest,
                usedFullFrame: output.usedFullFrame,
                detail: output.detail
            )
            publishStatus(lastDiagnostics: diagnostics)

            // Ignore a result if a configuration request arrived while Vision was busy.
            if inferenceSequence == requestedSequenceSnapshot() {
                delegate?.visionWorker(
                    self,
                    didProduce: output.sample,
                    carrier: currentCarrier,
                    inferenceDuration: inferenceDuration,
                    mailboxWaitDuration: mailboxWait
                )
            }

            guard inferenceSequence == requestedSequenceSnapshot() else {
                mailbox.clear()
                return
            }

            // Preserve the existing immediate-drain behavior when configuration is stable.
            guard let next = mailbox.endInferenceAndAcquireNext() else { return }
            currentCarrier = next
        }
    }

    private func requestedSequenceSnapshot() -> UInt64 {
        stateLock.lock()
        defer { stateLock.unlock() }
        return requestedConfigurationSequence
    }

    private func publishStatus(lastDiagnostics: HandPoseProviderDiagnostics?) {
        let providerStatus = provider.statusSnapshot
        let snapshot = VisionWorkerStatusSnapshot(
            activeProviderIdentifier: providerStatus.providerIdentifier,
            requestedMediaPipeBenchmark: activeSettings.mediaPipeBenchmarkEnabled,
            mediaPipeBenchmarkAvailable: MediaPipeHandPoseProvider.isAvailable,
            mediaPipeUnavailabilityReason: MediaPipeHandPoseProvider.unavailabilityReason,
            roiEnabled: providerStatus.roiEnabled,
            currentROI: providerStatus.currentROI,
            lastDiagnostics: lastDiagnostics,
            configurationSequence: activeConfigurationSequence
        )
        stateLock.lock()
        statusStorage = snapshot
        stateLock.unlock()
    }
}
