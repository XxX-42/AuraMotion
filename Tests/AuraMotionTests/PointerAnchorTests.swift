import XCTest
import CoreGraphics
@testable import AuraMotionCore

final class PointerAnchorTests: XCTestCase {
    private func sample(
        time: Double,
        shift: Double = 0,
        indexTipWobble: Double = 0,
        identity: Int = 1,
        stableConfidence: Float = 0.9,
        overallConfidence: Float = 0.9,
        omit: [HandJointName] = [],
        invalidStablePositions: Bool = false
    ) -> HandSample {
        var positions: [HandJointName: CGPoint] = [
            .wrist: CGPoint(x: 0.50 + shift, y: 0.20),
            .indexMCP: CGPoint(x: 0.40 + shift, y: 0.40),
            .middleMCP: CGPoint(x: 0.50 + shift, y: 0.40),
            .ringMCP: CGPoint(x: 0.60 + shift, y: 0.40),
            .littleMCP: CGPoint(x: 0.70 + shift, y: 0.40),
            .indexTip: CGPoint(x: 0.40 + shift + indexTipWobble, y: 0.70),
            .thumbTip: CGPoint(x: 0.20 + shift - indexTipWobble, y: 0.50)
        ]
        if invalidStablePositions {
            for name in [HandJointName.wrist, .indexMCP, .middleMCP, .ringMCP, .littleMCP] {
                positions[name] = CGPoint(x: .nan, y: .nan)
            }
        }

        var joints: [HandJointName: HandJoint] = [:]
        for (name, position) in positions where !omit.contains(name) {
            let confidence: Float = [HandJointName.wrist, .indexMCP, .middleMCP, .ringMCP, .littleMCP].contains(name)
                ? stableConfidence
                : 0.9
            joints[name] = HandJoint(name: name, position: position, confidence: confidence)
        }
        return HandSample(
            hostTimestamp: time,
            presentationTimeSeconds: time,
            isPresentationTimeEstimated: false,
            joints: joints,
            overallConfidence: overallConfidence,
            estimatedHandedness: .right,
            trackingID: identity
        )
    }

    func testPalmMCPFusionIgnoresIndexAndThumbTipWobble() throws {
        let fusion = HandCursorFusion()
        fusion.configure(strategy: .palmMCPFusion)
        let initial = try XCTUnwrap(fusion.update(sample(time: 1)))

        for frame in 1...20 {
            let wobble = sin(Double(frame) * 1.7) * 0.08
            let result = try XCTUnwrap(fusion.update(sample(
                time: 1 + Double(frame) / 30,
                indexTipWobble: wobble
            )))
            XCTAssertEqual(result.x, initial.x, accuracy: 0.000001)
            XCTAssertEqual(result.y, initial.y, accuracy: 0.000001)
        }
    }

    func testPalmCentroidLandmarkChurnPreservesOutputContinuity() throws {
        let fusion = HandCursorFusion()
        fusion.configure(strategy: .palmCentroid)
        let initial = try XCTUnwrap(fusion.update(sample(time: 1)))

        let withoutWrist = try XCTUnwrap(fusion.update(sample(time: 1.033, omit: [.wrist])))
        XCTAssertEqual(withoutWrist.x, initial.x, accuracy: 0.000001)
        XCTAssertEqual(withoutWrist.y, initial.y, accuracy: 0.000001)

        let translated = try XCTUnwrap(fusion.update(sample(time: 1.066, shift: 0.02, omit: [.wrist])))
        XCTAssertEqual(translated.x, initial.x + 0.02, accuracy: 0.000001)
    }

    func testStableAnchorRejectsInvalidConfidenceAndNonFiniteLandmarks() throws {
        let fusion = HandCursorFusion()
        fusion.configure(strategy: .palmMCPFusion)
        let initial = try XCTUnwrap(fusion.update(sample(time: 1)))

        XCTAssertNil(fusion.update(sample(time: 1.033, stableConfidence: 0.2)))
        let afterLowConfidence = try XCTUnwrap(fusion.update(sample(time: 1.066)))
        XCTAssertEqual(afterLowConfidence.x, initial.x, accuracy: 0.000001)

        XCTAssertNil(fusion.update(sample(time: 1.099, invalidStablePositions: true)))
        let afterNonFinite = try XCTUnwrap(fusion.update(sample(time: 1.132)))
        XCTAssertTrue(afterNonFinite.x.isFinite)
        XCTAssertTrue(afterNonFinite.y.isFinite)
    }

    func testStableAnchorResetsAcrossIdentityChangesAndLongGaps() throws {
        let fusion = HandCursorFusion()
        fusion.configure(strategy: .palmCentroid)
        _ = try XCTUnwrap(fusion.update(sample(time: 1)))

        let newIdentity = try XCTUnwrap(fusion.update(sample(time: 1.033, shift: 0.2, identity: 2)))
        XCTAssertEqual(newIdentity.x, 0.74, accuracy: 0.000001)

        let afterGap = try XCTUnwrap(fusion.update(sample(time: 1.4, shift: 0.3, identity: 2)))
        XCTAssertEqual(afterGap.x, 0.84, accuracy: 0.000001)
    }
}
