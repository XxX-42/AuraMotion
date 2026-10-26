import CoreGraphics
import Foundation

public struct VisionROIRequest: Sendable, Equatable {
    public let region: CGRect
    public let usedFullFrame: Bool

    public init(region: CGRect, usedFullFrame: Bool) {
        self.region = region
        self.usedFullFrame = usedFullFrame
    }
}

/// Maintains the last detected hand bounds on the Vision queue.
/// Every enabled ROI run starts with a full-frame search, periodically checks the
/// full frame again, and immediately returns to full-frame search after a loss.
public struct VisionROIController {
    public let fullFrameRefreshInterval: TimeInterval

    public private(set) var isEnabled = false
    public private(set) var currentRequest = VisionROIRequest(
        region: VisionROI.fullFrame,
        usedFullFrame: true
    )
    public private(set) var trackedBounds: CGRect?

    private var scale = 1.8
    private var minimumSize = 0.35
    private var lastFullFrameRequestTimestamp: TimeInterval?

    public init(fullFrameRefreshInterval: TimeInterval = 1.0) {
        self.fullFrameRefreshInterval = fullFrameRefreshInterval.isFinite
            ? max(0.05, fullFrameRefreshInterval)
            : 1.0
    }

    public mutating func configure(settings: CursorExperimentSettings) {
        let normalized = settings.normalized()
        isEnabled = normalized.visionROIEnabled
        scale = normalized.roiScale
        minimumSize = normalized.roiMinimumSize
        resetTracking()
    }

    /// The next request uses ROI only after a full-frame request has detected a hand.
    public mutating func nextRequest(at hostTimestamp: TimeInterval) -> VisionROIRequest {
        guard isEnabled else { return currentRequest }
        guard let trackedBounds else {
            return fullFrameRequest(at: hostTimestamp)
        }

        guard hostTimestamp.isFinite,
              let lastFullFrameRequestTimestamp,
              hostTimestamp >= lastFullFrameRequestTimestamp,
              hostTimestamp - lastFullFrameRequestTimestamp < fullFrameRefreshInterval else {
            return fullFrameRequest(at: hostTimestamp)
        }

        currentRequest = VisionROIRequest(
            region: VisionROI.expanded(around: trackedBounds, scale: scale, minimumSize: minimumSize),
            usedFullFrame: false
        )
        return currentRequest
    }

    /// Updates tracking bounds from normalized image coordinates. A miss resets
    /// the next request to the entire image so the hand can be reacquired anywhere.
    public mutating func completeRequest(with sample: HandSample?, isMirrored: Bool = false) {
        guard isEnabled else { return }
        guard let sample, let bounds = VisionROI.bounds(of: sample, isMirrored: isMirrored) else {
            trackedBounds = nil
            currentRequest = VisionROIRequest(region: VisionROI.fullFrame, usedFullFrame: true)
            return
        }
        trackedBounds = bounds
    }

    public mutating func reset() {
        resetTracking()
    }

    private mutating func resetTracking() {
        trackedBounds = nil
        lastFullFrameRequestTimestamp = nil
        currentRequest = VisionROIRequest(region: VisionROI.fullFrame, usedFullFrame: true)
    }

    private mutating func fullFrameRequest(at hostTimestamp: TimeInterval) -> VisionROIRequest {
        lastFullFrameRequestTimestamp = hostTimestamp.isFinite ? hostTimestamp : nil
        currentRequest = VisionROIRequest(region: VisionROI.fullFrame, usedFullFrame: true)
        return currentRequest
    }
}
