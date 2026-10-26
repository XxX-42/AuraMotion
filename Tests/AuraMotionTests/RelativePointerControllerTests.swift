import XCTest
import CoreGraphics
@testable import AuraMotionCore

final class RelativePointerControllerTests: XCTestCase {
    func testHotDisableKeepsLegacyMappingContinuousAcrossSteadyFrames() throws {
        let profile = CalibrationProfile(
            activeRegion: CGRect(x: 0, y: 0, width: 1, height: 1),
            displayBounds: CGRect(x: 0, y: 0, width: 1000, height: 800)
        )
        let controller = CursorController(profile: profile)
        let visible = CGPoint(x: 420, y: 310)
        var optimized = CursorExperimentSettings()
        optimized.relativeMappingEnabled = true
        optimized.mappingMode = .relativeRebased

        controller.reconfigure(optimized, cursorPosition: visible)
        controller.setInteractionState(.pointer, currentCursor: visible)
        _ = try XCTUnwrap(controller.processIndexTip(normalizedPoint: CGPoint(x: 0.5, y: 0.5), timestamp: 1.0))
        let beforeDisable = try XCTUnwrap(controller.processIndexTip(
            normalizedPoint: CGPoint(x: 0.5, y: 0.5), timestamp: 1.033
        ))
        XCTAssertEqual(beforeDisable.x, visible.x, accuracy: 0.01)
        XCTAssertEqual(beforeDisable.y, visible.y, accuracy: 0.01)

        // Recreate AppEnvironment's settings-change sequence.
        controller.freeze(at: beforeDisable)
        controller.reconfigure(CursorExperimentSettings(), cursorPosition: beforeDisable)
        let baselineFrame1 = try XCTUnwrap(controller.processIndexTip(
            normalizedPoint: CGPoint(x: 0.5, y: 0.5), timestamp: 1.066
        ))
        let baselineFrame2 = try XCTUnwrap(controller.processIndexTip(
            normalizedPoint: CGPoint(x: 0.5, y: 0.5), timestamp: 1.099
        ))
        let baselineFrame3 = try XCTUnwrap(controller.processIndexTip(
            normalizedPoint: CGPoint(x: 0.52, y: 0.5), timestamp: 1.132
        ))

        XCTAssertEqual(baselineFrame1.x, beforeDisable.x, accuracy: 0.01)
        XCTAssertEqual(baselineFrame1.y, beforeDisable.y, accuracy: 0.01)
        XCTAssertEqual(baselineFrame2.x, beforeDisable.x, accuracy: 0.01)
        XCTAssertEqual(baselineFrame2.y, beforeDisable.y, accuracy: 0.01)
        XCTAssertGreaterThan(baselineFrame3.x, baselineFrame2.x)
        XCTAssertLessThan(baselineFrame3.x - baselineFrame2.x, 10)
    }

    func testFrozenPhaseResumesAtSuppliedPhysicalCursorPosition() throws {
        let profile = CalibrationProfile(
            activeRegion: CGRect(x: 0, y: 0, width: 1, height: 1),
            displayBounds: CGRect(x: 0, y: 0, width: 1000, height: 800)
        )
        let controller = CursorController(profile: profile)
        let original = CGPoint(x: 400, y: 300)
        var settings = CursorExperimentSettings()
        settings.relativeMappingEnabled = true
        settings.mappingMode = .relativeRebased

        controller.reconfigure(settings, cursorPosition: original)
        controller.setInteractionState(.pointer, currentCursor: original)
        _ = try XCTUnwrap(controller.processIndexTip(normalizedPoint: CGPoint(x: 0.5, y: 0.5), timestamp: 2.0))

        let physicalCursor = CGPoint(x: 720, y: 510)
        controller.setInteractionState(.scrolling, currentCursor: physicalCursor)
        let frozen = try XCTUnwrap(controller.processIndexTip(
            normalizedPoint: CGPoint(x: 0.9, y: 0.9), timestamp: 2.033
        ))
        XCTAssertEqual(frozen.x, physicalCursor.x, accuracy: 0.01)
        XCTAssertEqual(frozen.y, physicalCursor.y, accuracy: 0.01)

        controller.setInteractionState(.pointer, currentCursor: physicalCursor)
        let resumed = try XCTUnwrap(controller.processIndexTip(
            normalizedPoint: CGPoint(x: 0.9, y: 0.9), timestamp: 2.066
        ))
        XCTAssertEqual(resumed.x, physicalCursor.x, accuracy: 0.01)
        XCTAssertEqual(resumed.y, physicalCursor.y, accuracy: 0.01)

        let moved = try XCTUnwrap(controller.processIndexTip(
            normalizedPoint: CGPoint(x: 0.91, y: 0.91), timestamp: 2.099
        ))
        XCTAssertGreaterThan(moved.x, physicalCursor.x)
        XCTAssertLessThan(moved.y, physicalCursor.y)
    }

    func testOptimizedMappingRebasesAcrossIdentityChangeAndInvalidAnchorSpan() throws {
        let profile = CalibrationProfile(
            activeRegion: CGRect(x: 0, y: 0, width: 1, height: 1),
            displayBounds: CGRect(x: 0, y: 0, width: 1000, height: 800)
        )
        let controller = CursorController(profile: profile)
        var settings = CursorExperimentSettings()
        settings.stableAnchorEnabled = true
        settings.relativeMappingEnabled = true
        settings.mappingMode = .relativeRebased
        settings.anchorStrategy = .indexMCP
        let visible = CGPoint(x: 420, y: 310)
        controller.reconfigure(settings, cursorPosition: visible)
        controller.setInteractionState(.pointer, currentCursor: visible)

        _ = try XCTUnwrap(controller.processHand(sample(time: 1.000, x: 0.40, trackingID: 1)))
        let beforeIdentityChange = try XCTUnwrap(controller.processHand(
            sample(time: 1.033, x: 0.45, trackingID: 1)
        ))

        let afterIdentityChange = try XCTUnwrap(controller.processHand(
            sample(time: 1.066, x: 0.72, trackingID: 2)
        ))
        XCTAssertEqual(afterIdentityChange.x, beforeIdentityChange.x, accuracy: 1)
        XCTAssertEqual(afterIdentityChange.y, beforeIdentityChange.y, accuracy: 1)

        let identityFrame2 = try XCTUnwrap(controller.processHand(
            sample(time: 1.099, x: 0.740, trackingID: 2)
        ))
        let identityFrame3 = try XCTUnwrap(controller.processHand(
            sample(time: 1.132, x: 0.770, trackingID: 2)
        ))
        XCTAssertGreaterThan(identityFrame2.x, afterIdentityChange.x)
        XCTAssertGreaterThan(identityFrame3.x, identityFrame2.x)
        XCTAssertLessThan(identityFrame2.x - afterIdentityChange.x, 40)
        XCTAssertLessThan(identityFrame3.x - identityFrame2.x, 40)

        _ = try XCTUnwrap(controller.processHand(
            sample(time: 1.165, x: 0.735, trackingID: 2, includeStableLandmarks: false)
        ))
        let reacquired = try XCTUnwrap(controller.processHand(
            sample(time: 1.198, x: 0.90, trackingID: 2)
        ))
        XCTAssertEqual(reacquired.x, identityFrame3.x, accuracy: 1)
        XCTAssertEqual(reacquired.y, identityFrame3.y, accuracy: 1)

        let afterReacquisition = try XCTUnwrap(controller.processHand(
            sample(time: 1.231, x: 0.920, trackingID: 2)
        ))
        XCTAssertGreaterThan(afterReacquisition.x, reacquired.x)
        XCTAssertLessThan(afterReacquisition.x - reacquired.x, 40)
    }

    private func sample(
        time: Double,
        x: Double,
        trackingID: Int,
        includeStableLandmarks: Bool = true
    ) -> HandSample {
        var joints: [HandJointName: HandJoint] = [
            .indexTip: HandJoint(name: .indexTip, position: CGPoint(x: x, y: 0.70), confidence: 0.9),
            .thumbTip: HandJoint(name: .thumbTip, position: CGPoint(x: x - 0.18, y: 0.50), confidence: 0.9)
        ]
        if includeStableLandmarks {
            let stablePoints: [(HandJointName, CGPoint)] = [
                (.wrist, CGPoint(x: x - 0.08, y: 0.20)),
                (.indexMCP, CGPoint(x: x, y: 0.40)),
                (.middleMCP, CGPoint(x: x + 0.06, y: 0.40)),
                (.ringMCP, CGPoint(x: x + 0.12, y: 0.39)),
                (.littleMCP, CGPoint(x: x + 0.18, y: 0.38))
            ]
            for (name, point) in stablePoints {
                joints[name] = HandJoint(name: name, position: point, confidence: 0.9)
            }
        }
        return HandSample(
            hostTimestamp: time,
            presentationTimeSeconds: time,
            isPresentationTimeEstimated: false,
            joints: joints,
            overallConfidence: 0.9,
            estimatedHandedness: .right,
            trackingID: trackingID
        )
    }
}
