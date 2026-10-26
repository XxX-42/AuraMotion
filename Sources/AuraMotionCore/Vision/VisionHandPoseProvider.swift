import CoreVideo
import Foundation
import Vision

/// The production Apple Vision implementation behind HandPoseProvider.
/// Instance access is confined to VisionInferenceWorker's serial queue.
public final class VisionHandPoseProvider: HandPoseProvider, @unchecked Sendable {
    public let identifier = "vision"

    private let request: VNDetectHumanHandPoseRequest
    private var roiController = VisionROIController()

    public init(revision: Int = VisionRevisionPolicy.selectActiveRevision()) {
        request = VNDetectHumanHandPoseRequest()
        request.revision = revision
        request.maximumHandCount = 1
        request.regionOfInterest = VisionROI.fullFrame
    }

    public var statusSnapshot: HandPoseProviderStatusSnapshot {
        HandPoseProviderStatusSnapshot(
            providerIdentifier: identifier,
            roiEnabled: roiController.isEnabled,
            currentROI: roiController.currentRequest.region
        )
    }

    public func configure(settings: CursorExperimentSettings) {
        roiController.configure(settings: settings)
        request.regionOfInterest = VisionROI.fullFrame
    }

    public func reset() {
        roiController.reset()
        request.regionOfInterest = VisionROI.fullFrame
    }

    public func stop() {}

    public func infer(
        pixelBuffer: CVPixelBuffer,
        hostTimestamp: TimeInterval,
        presentationTime: Double,
        isEstimatedTime: Bool,
        trackingID: Int,
        isMirrored: Bool
    ) -> HandPoseProviderOutput {
        let roiRequest = roiController.nextRequest(at: hostTimestamp)
        request.regionOfInterest = roiRequest.region
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])

        do {
            try handler.perform([request])
            let observation = request.results?.first
            let sample = observation.map {
                HandObservationDecoder.decode(
                    observation: $0,
                    hostTimestamp: hostTimestamp,
                    presentationTime: presentationTime,
                    isEstimatedTime: isEstimatedTime,
                    trackingID: trackingID,
                    isMirrored: isMirrored,
                    regionOfInterest: roiRequest.region,
                    usedFullFrame: roiRequest.usedFullFrame
                )
            }
            roiController.completeRequest(with: sample, isMirrored: isMirrored)

            return HandPoseProviderOutput(
                sample: sample,
                outcome: sample == nil ? .noHand : .detected,
                regionOfInterest: roiRequest.region,
                usedFullFrame: roiRequest.usedFullFrame
            )
        } catch {
            roiController.completeRequest(with: nil, isMirrored: isMirrored)
            return HandPoseProviderOutput(
                sample: nil,
                outcome: .failed,
                regionOfInterest: roiRequest.region,
                usedFullFrame: roiRequest.usedFullFrame,
                detail: String(describing: error)
            )
        }
    }
}
