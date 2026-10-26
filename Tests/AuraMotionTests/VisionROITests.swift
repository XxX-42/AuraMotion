import CoreGraphics
import XCTest
@testable import AuraMotionCore

final class VisionROITests: XCTestCase {
    func testROIIsDisabledAndDoesNotRetainLandmarksByDefault() {
        var controller = VisionROIController()
        controller.configure(settings: CursorExperimentSettings())

        XCTAssertFalse(controller.isEnabled)
        XCTAssertEqual(controller.nextRequest(at: 0).region, VisionROI.fullFrame)
        controller.completeRequest(with: sample(points: [
            .wrist: CGPoint(x: 0.2, y: 0.3),
            .indexTip: CGPoint(x: 0.4, y: 0.5)
        ]))

        XCTAssertNil(controller.trackedBounds)
        XCTAssertEqual(controller.nextRequest(at: 0.1), VisionROIRequest(region: VisionROI.fullFrame, usedFullFrame: true))
    }

    func testExpandedRegionUsesScaleMinimumSizeAndClampsToImageBounds() {
        let region = VisionROI.expanded(
            around: CGRect(x: 0.8, y: 0.78, width: 0.2, height: 0.2),
            scale: 2,
            minimumSize: 0.35
        )

        XCTAssertEqual(region.origin.x, 0.6, accuracy: 0.0001)
        XCTAssertEqual(region.origin.y, 0.6, accuracy: 0.0001)
        XCTAssertEqual(region.width, 0.4, accuracy: 0.0001)
        XCTAssertEqual(region.height, 0.4, accuracy: 0.0001)
        XCTAssertGreaterThanOrEqual(region.minX, 0)
        XCTAssertGreaterThanOrEqual(region.minY, 0)
        XCTAssertLessThanOrEqual(region.maxX, 1)
        XCTAssertLessThanOrEqual(region.maxY, 1)
    }

    func testROIRegionRelativeCoordinatesMapBackToFullImage() {
        let roi = CGRect(x: 0.4, y: 0.2, width: 0.5, height: 0.6)
        let point = VisionROI.fullImagePoint(
            fromVisionPoint: CGPoint(x: 0.6, y: 0.5),
            region: roi,
            usedFullFrame: false,
            isMirrored: false
        )

        XCTAssertEqual(point.x, 0.7, accuracy: 0.0001)
        XCTAssertEqual(point.y, 0.5, accuracy: 0.0001)
    }

    func testMirroredROIUsesRawVisionCoordinatesThenMirrorsOnce() {
        let roi = CGRect(x: 0.4, y: 0.2, width: 0.5, height: 0.6)
        let rawVisionPoint = CGPoint(x: 0.4, y: 0.5)
        let unmirrored = VisionROI.fullImagePoint(
            fromVisionPoint: rawVisionPoint,
            region: roi,
            usedFullFrame: false,
            isMirrored: false
        )
        let mirrored = VisionROI.fullImagePoint(
            fromVisionPoint: rawVisionPoint,
            region: roi,
            usedFullFrame: false,
            isMirrored: true
        )

        XCTAssertEqual(unmirrored.x, 0.6, accuracy: 0.0001)
        XCTAssertEqual(mirrored.x, 1 - unmirrored.x, accuracy: 0.0001)
        XCTAssertEqual(mirrored.y, unmirrored.y, accuracy: 0.0001)
    }

    func testFullFrameCoordinatesKeepTheExistingMirrorMappingExactly() {
        let point = CGPoint(x: 0.63, y: 0.27)
        let unmirrored = VisionROI.fullImagePoint(
            fromVisionPoint: point,
            region: VisionROI.fullFrame,
            usedFullFrame: true,
            isMirrored: false
        )
        let mirrored = VisionROI.fullImagePoint(
            fromVisionPoint: point,
            region: VisionROI.fullFrame,
            usedFullFrame: true,
            isMirrored: true
        )

        XCTAssertEqual(unmirrored, point)
        XCTAssertEqual(mirrored, CGPoint(x: 0.37, y: 0.27))
    }

    func testROIUsesFullImageLandmarksAndFallsBackImmediatelyAfterLoss() {
        var settings = CursorExperimentSettings()
        settings.visionROIEnabled = true
        settings.roiScale = 1.8
        settings.roiMinimumSize = 0.35

        var controller = VisionROIController()
        controller.configure(settings: settings)
        XCTAssertTrue(controller.nextRequest(at: 0).usedFullFrame)

        let hand = sample(points: [
            .wrist: CGPoint(x: 0.2, y: 0.3),
            .indexTip: CGPoint(x: 0.4, y: 0.5)
        ])
        controller.completeRequest(with: hand)
        let roiRequest = controller.nextRequest(at: 0.05)

        XCTAssertFalse(roiRequest.usedFullFrame)
        XCTAssertEqual(roiRequest.region.origin.x, 0.12, accuracy: 0.0001)
        XCTAssertEqual(roiRequest.region.origin.y, 0.22, accuracy: 0.0001)
        XCTAssertEqual(roiRequest.region.width, 0.36, accuracy: 0.0001)
        XCTAssertEqual(roiRequest.region.height, 0.36, accuracy: 0.0001)

        controller.completeRequest(with: nil)
        XCTAssertEqual(controller.nextRequest(at: 0.1), VisionROIRequest(region: VisionROI.fullFrame, usedFullFrame: true))

        controller.completeRequest(with: hand)
        XCTAssertFalse(controller.nextRequest(at: 0.2).usedFullFrame, "A full-frame detection should reacquire ROI tracking.")
    }

    func testROIRefreshUsesElapsedTimeAcrossVariableFrameIntervals() {
        var settings = CursorExperimentSettings()
        settings.visionROIEnabled = true
        var controller = VisionROIController(fullFrameRefreshInterval: 1.0)
        controller.configure(settings: settings)

        let hand = sample(points: [
            .wrist: CGPoint(x: 0.25, y: 0.25),
            .indexTip: CGPoint(x: 0.45, y: 0.45)
        ])
        XCTAssertTrue(controller.nextRequest(at: 0).usedFullFrame)
        controller.completeRequest(with: hand)
        XCTAssertFalse(controller.nextRequest(at: 0.05).usedFullFrame)
        controller.completeRequest(with: hand)
        XCTAssertFalse(controller.nextRequest(at: 0.48).usedFullFrame)
        controller.completeRequest(with: hand)
        XCTAssertFalse(controller.nextRequest(at: 0.99).usedFullFrame)
        controller.completeRequest(with: hand)

        XCTAssertTrue(controller.nextRequest(at: 1.05).usedFullFrame)
    }

    func testMirroredLandmarksAreConvertedBackToCameraCoordinatesForROI() {
        var settings = CursorExperimentSettings()
        settings.visionROIEnabled = true
        var controller = VisionROIController()
        controller.configure(settings: settings)

        let mirroredSample = sample(points: [
            .wrist: CGPoint(x: 0.8, y: 0.3),
            .indexTip: CGPoint(x: 0.6, y: 0.5)
        ])
        XCTAssertTrue(controller.nextRequest(at: 0).usedFullFrame)
        controller.completeRequest(with: mirroredSample, isMirrored: true)

        let request = controller.nextRequest(at: 0.1)
        XCTAssertEqual(request.region.origin.x, 0.12, accuracy: 0.0001)
        XCTAssertEqual(request.region.width, 0.36, accuracy: 0.0001)
    }

    private func sample(points: [HandJointName: CGPoint]) -> HandSample {
        var joints: [HandJointName: HandJoint] = [:]
        for (name, point) in points {
            joints[name] = HandJoint(name: name, position: point, confidence: 0.9)
        }
        return HandSample(
            hostTimestamp: 1,
            presentationTimeSeconds: 1,
            isPresentationTimeEstimated: false,
            joints: joints,
            overallConfidence: 0.9,
            estimatedHandedness: .unknown,
            trackingID: 1
        )
    }
}
