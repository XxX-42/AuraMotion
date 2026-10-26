import CoreVideo
import Foundation

/// Explicit unavailable marker for the optional MediaPipe benchmark backend.
/// The current upstream binary package has no macOS slice, so this provider
/// never schedules work and never returns a sample on this platform.
public final class MediaPipeHandPoseProvider: HandPoseProvider, @unchecked Sendable {
    public static let isAvailable = false
    public static let unavailabilityReason: String? =
        "MediaPipe Tasks Vision is unavailable on macOS: the current upstream binary provides iOS and iOS Simulator slices only, with no macOS slice."

    public let identifier = "mediapipe"

    public init() {}

    public var statusSnapshot: HandPoseProviderStatusSnapshot {
        HandPoseProviderStatusSnapshot(
            providerIdentifier: identifier,
            isAvailable: Self.isAvailable,
            unavailabilityReason: Self.unavailabilityReason
        )
    }

    public func configure(settings: CursorExperimentSettings) {}

    public func reset() {}

    public func stop() {}

    public func infer(
        pixelBuffer: CVPixelBuffer,
        hostTimestamp: TimeInterval,
        presentationTime: Double,
        isEstimatedTime: Bool,
        trackingID: Int,
        isMirrored: Bool
    ) -> HandPoseProviderOutput {
        HandPoseProviderOutput(
            sample: nil,
            outcome: .unavailable,
            regionOfInterest: VisionROI.fullFrame,
            usedFullFrame: true,
            detail: Self.unavailabilityReason
        )
    }
}
