import Foundation
import CoreGraphics

/// Palm translation carries fast motion; a slowly varying fingertip offset keeps
/// absolute index aiming while attenuating independent finger wobble.
public final class HandCursorFusion: @unchecked Sendable {
    private var previousTime: Double?
    private var identity: Int?
    private var offset: CGPoint?
    private var palmJoints: [HandJointName] = []

    private var stableLandmarks: [HandJointName] = []
    private var stableMCPOffset: CGPoint?
    private var stableContinuityOffset: CGPoint?
    private var stableLastOutput: CGPoint?

    public private(set) var strategy: PointerAnchorStrategy = .legacyTipFusion

    private static let stableJointNames: [HandJointName] = [
        .wrist, .indexMCP, .middleMCP, .ringMCP, .littleMCP
    ]

    public init() {}
    public func reset() {
        previousTime = nil; identity = nil; offset = nil; palmJoints = []
        stableLandmarks = []; stableMCPOffset = nil
        stableContinuityOffset = nil; stableLastOutput = nil
    }

    public func update(_ sample: HandSample) -> CGPoint? {
        guard strategy != .legacyTipFusion else { return updateLegacy(sample) }
        return updateStable(sample)
    }

    /// Selects the pointer anchor. Changing strategies starts a fresh observation span.
    /// Calling this repeatedly with the active strategy leaves the current span intact.
    public func configure(strategy newStrategy: PointerAnchorStrategy) {
        guard strategy != newStrategy else { return }
        strategy = newStrategy
        reset()
    }

    /// The original tip-fusion path is kept intact for the default and disabled mode.
    private func updateLegacy(_ sample: HandSample) -> CGPoint? {
        guard sample.hostTimestamp.isFinite,
              let tip = sample.joint(.indexTip, minConfidence: 0.45),
              tip.x.isFinite, tip.y.isFinite else { return nil }
        if let time = previousTime, sample.hostTimestamp <= time { return nil }
        if identity != sample.trackingID || previousTime.map({ sample.hostTimestamp - $0 > 0.25 }) == true { reset() }
        let dt = min(0.1, max(0.001, sample.hostTimestamp - (previousTime ?? sample.hostTimestamp)))
        previousTime = sample.hostTimestamp; identity = sample.trackingID
        let names: [HandJointName] = [.wrist, .indexMCP, .middleMCP, .ringMCP, .littleMCP]
        let available = names.filter { name in
            guard let p = sample.joint(name, minConfidence: 0.55) else { return false }
            return p.x.isFinite && p.y.isFinite
        }
        // Use a fixed landmark set per uninterrupted observation span. Changing
        // the centroid without re-anchoring would introduce an artificial jump.
        guard available.count >= 3 else { offset = nil; palmJoints = []; return tip }
        let points = available.compactMap { sample.joint($0, minConfidence: 0.55) }
        let palm = CGPoint(x: points.map(\.x).reduce(0, +) / CGFloat(points.count),
                           y: points.map(\.y).reduce(0, +) / CGFloat(points.count))
        let measured = CGPoint(x: tip.x - palm.x, y: tip.y - palm.y)
        if offset == nil || available != palmJoints { offset = measured; palmJoints = available }
        let previous = offset ?? measured
        let pose = PoseClassifier.classify(sample: sample)
        if pose.isPinchApproach || pose.isTwoFingerPointing {
            // Finger articulation for clicking or scrolling is not translation.
            // Keep the last pointing offset and let palm motion carry the action.
            return CGPoint(x: palm.x + previous.x, y: palm.y + previous.y)
        }
        let alpha = CGFloat(1 - exp(-dt / 0.085))
        let learned = CGPoint(x: previous.x + alpha * (measured.x - previous.x),
                              y: previous.y + alpha * (measured.y - previous.y))
        offset = learned
        return CGPoint(x: palm.x + learned.x, y: palm.y + learned.y)
    }

    /// Optimized anchors use only wrist and MCP landmarks. Fingertips remain available to
    /// gesture recognition elsewhere, but never determine an optimized pointer coordinate.
    private func updateStable(_ sample: HandSample) -> CGPoint? {
        guard sample.hostTimestamp.isFinite else { return nil }
        if let time = previousTime, sample.hostTimestamp <= time { return nil }

        if identity.map({ $0 != sample.trackingID }) == true
            || previousTime.map({ sample.hostTimestamp - $0 > 0.25 }) == true {
            reset()
        }

        guard sample.overallConfidence.isFinite,
              (0.45...1.0).contains(sample.overallConfidence) else {
            breakStableSpan()
            return nil
        }

        let dt = min(0.1, max(0.001, sample.hostTimestamp - (previousTime ?? sample.hostTimestamp)))
        var points: [HandJointName: CGPoint] = [:]
        for name in Self.stableJointNames {
            guard let joint = sample.joints[name],
                  joint.confidence.isFinite,
                  (0.55...1.0).contains(joint.confidence),
                  joint.position.x.isFinite,
                  joint.position.y.isFinite else { continue }
            points[name] = joint.position
        }
        let available = Self.stableJointNames.filter { points[$0] != nil }
        guard available.count >= 3 else {
            breakStableSpan()
            return nil
        }

        let centroid = CGPoint(
            x: available.reduce(CGFloat.zero) { $0 + (points[$1]?.x ?? 0) } / CGFloat(available.count),
            y: available.reduce(CGFloat.zero) { $0 + (points[$1]?.y ?? 0) } / CGFloat(available.count)
        )
        let setChanged = available != stableLandmarks
        let candidate: CGPoint
        switch strategy {
        case .legacyTipFusion:
            // update(_:) dispatches legacy directly, so this is unreachable.
            return nil
        case .indexMCP:
            guard let indexMCP = points[.indexMCP] else {
                breakStableSpan()
                return nil
            }
            candidate = indexMCP
        case .palmCentroid:
            candidate = centroid
        case .palmMCPFusion:
            guard let indexMCP = points[.indexMCP] else {
                breakStableSpan()
                return nil
            }
            let measured = CGPoint(x: indexMCP.x - centroid.x, y: indexMCP.y - centroid.y)
            if setChanged || stableMCPOffset == nil {
                stableMCPOffset = measured
            } else if let previous = stableMCPOffset {
                let alpha = CGFloat(1 - exp(-dt / 0.085))
                stableMCPOffset = CGPoint(
                    x: previous.x + alpha * (measured.x - previous.x),
                    y: previous.y + alpha * (measured.y - previous.y)
                )
            }
            let relative = stableMCPOffset ?? measured
            candidate = CGPoint(x: centroid.x + relative.x, y: centroid.y + relative.y)
        }

        if setChanged, let previousOutput = stableLastOutput {
            // Re-anchor a changed centroid or support set to the last emitted point.
            // The next frame then follows motion from the new stable set without a jump.
            stableContinuityOffset = CGPoint(
                x: previousOutput.x - candidate.x,
                y: previousOutput.y - candidate.y
            )
        }
        let continuity = stableContinuityOffset ?? .zero
        let output = CGPoint(x: candidate.x + continuity.x, y: candidate.y + continuity.y)
        previousTime = sample.hostTimestamp
        identity = sample.trackingID
        stableLandmarks = available
        stableLastOutput = output
        return output
    }

    /// Invalid frames end the current landmark-set span while retaining its last output
    /// so that a later, valid set can be re-anchored without a discontinuity.
    private func breakStableSpan() {
        stableLandmarks = []
        stableMCPOffset = nil
    }
}
