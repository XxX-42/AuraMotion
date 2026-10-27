import XCTest
@testable import AuraMotionCore

final class HeadBoundaryCalibrationTests: XCTestCase {
    private func pose(_ yaw: Float, _ pitch: Float) -> HeadPose {
        HeadPose(yaw: yaw, pitch: pitch, roll: 0, centerX: 0.5, centerY: 0.5, scale: 0.3)
    }
    func testBoundariesMapIndependentlyAndRemainStableForHeadTranslation() throws {
        var c = HeadBoundaryCalibration()
        XCTAssertTrue(c.record(.left, yaw: 0.3, pitch: 0))
        XCTAssertTrue(c.record(.right, yaw: -0.3, pitch: 0))
        XCTAssertTrue(c.record(.top, yaw: 0, pitch: -0.2))
        XCTAssertTrue(c.record(.bottom, yaw: 0, pitch: 0.2))
        let screen = CGRect(x: 10, y: 20, width: 1000, height: 800)
        let leftTop = try XCTUnwrap(c.project(pose: pose(0.3, -0.2), mirrored: false, display: screen))
        XCTAssertEqual(leftTop.x, 10, accuracy: 0.01)
        XCTAssertEqual(leftTop.y, 20, accuracy: 0.01)
        let rightBottom = try XCTUnwrap(c.project(pose: pose(-0.3, 0.2), mirrored: true, display: screen))
        XCTAssertEqual(rightBottom.x, 1010, accuracy: 0.01)
        XCTAssertEqual(rightBottom.y, 820, accuracy: 0.01)
        let center = try XCTUnwrap(c.project(pose: pose(0, 0), mirrored: false, display: screen))
        XCTAssertEqual(center.x, 510, accuracy: 0.01)
        XCTAssertEqual(center.y, 420, accuracy: 0.01)
        XCTAssertEqual(try JSONDecoder().decode(HeadBoundaryCalibration.self, from: JSONEncoder().encode(c)), c)
    }
    func testRejectsNearIdenticalOppositeBoundaryWithoutReplacingPriorValue() {
        var c = HeadBoundaryCalibration()
        XCTAssertTrue(c.record(.left, yaw: 0.2, pitch: 0))
        XCTAssertTrue(c.record(.right, yaw: -0.2, pitch: 0))
        XCTAssertFalse(c.record(.right, yaw: 0.201, pitch: 0))
        XCTAssertEqual(c.right, -0.2)
    }
}
