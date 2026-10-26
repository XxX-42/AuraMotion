import CoreGraphics
import CoreVideo
import Foundation

/// The common hand-pose result delivered by every inference backend.
/// Backend-specific coordinates, timing, and status stay inside the Vision layer.
public enum HandPoseInferenceOutcome: String, Sendable, Equatable {
    case detected
    case noHand
    case failed
    case unavailable
}

/// A single synchronous inference result. `regionOfInterest` is in normalized
/// full-image coordinates with a lower-left origin.
public struct HandPoseProviderOutput: Sendable, Equatable {
    public let sample: HandSample?
    public let outcome: HandPoseInferenceOutcome
    public let regionOfInterest: CGRect
    public let usedFullFrame: Bool
    public let detail: String?

    public init(
        sample: HandSample?,
        outcome: HandPoseInferenceOutcome,
        regionOfInterest: CGRect,
        usedFullFrame: Bool,
        detail: String? = nil
    ) {
        self.sample = sample
        self.outcome = outcome
        self.regionOfInterest = regionOfInterest
        self.usedFullFrame = usedFullFrame
        self.detail = detail
    }
}

/// Last-frame timing and loss information suitable for diagnostics and benchmarks.
public struct HandPoseProviderDiagnostics: Sendable, Equatable {
    public let providerIdentifier: String
    public let outcome: HandPoseInferenceOutcome
    public let inferenceDuration: TimeInterval
    public let mailboxWaitDuration: TimeInterval
    public let regionOfInterest: CGRect
    public let usedFullFrame: Bool
    public let detail: String?

    public init(
        providerIdentifier: String,
        outcome: HandPoseInferenceOutcome,
        inferenceDuration: TimeInterval,
        mailboxWaitDuration: TimeInterval,
        regionOfInterest: CGRect,
        usedFullFrame: Bool,
        detail: String? = nil
    ) {
        self.providerIdentifier = providerIdentifier
        self.outcome = outcome
        self.inferenceDuration = inferenceDuration
        self.mailboxWaitDuration = mailboxWaitDuration
        self.regionOfInterest = regionOfInterest
        self.usedFullFrame = usedFullFrame
        self.detail = detail
    }
}

/// Thread-safe, value-only description of the provider currently in use.
public struct HandPoseProviderStatusSnapshot: Sendable, Equatable {
    public let providerIdentifier: String
    public let isAvailable: Bool
    public let unavailabilityReason: String?
    public let roiEnabled: Bool
    public let currentROI: CGRect

    public init(
        providerIdentifier: String,
        isAvailable: Bool = true,
        unavailabilityReason: String? = nil,
        roiEnabled: Bool = false,
        currentROI: CGRect = VisionROI.fullFrame
    ) {
        self.providerIdentifier = providerIdentifier
        self.isAvailable = isAvailable
        self.unavailabilityReason = unavailabilityReason
        self.roiEnabled = roiEnabled
        self.currentROI = currentROI
    }
}

/// Inference backends are called only from VisionInferenceWorker's serial queue.
public protocol HandPoseProvider: AnyObject, Sendable {
    var identifier: String { get }
    var statusSnapshot: HandPoseProviderStatusSnapshot { get }

    func configure(settings: CursorExperimentSettings)
    func stop()
    func reset()
    func infer(
        pixelBuffer: CVPixelBuffer,
        hostTimestamp: TimeInterval,
        presentationTime: Double,
        isEstimatedTime: Bool,
        trackingID: Int,
        isMirrored: Bool
    ) -> HandPoseProviderOutput
}
