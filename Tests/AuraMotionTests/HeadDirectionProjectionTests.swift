import XCTest
@testable import AuraMotionCore

final class HeadDirectionProjectionTests: XCTestCase {
    private func pose(_ yaw: Float = 0, _ pitch: Float = 0) -> HeadPose {
        HeadPose(yaw: yaw, pitch: pitch, roll: 0, centerX: 0.5, centerY: 0.5, scale: 0.3)
    }
    func testNeutralAndHeadRotationMoveApproximatePoint() throws {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let neutral = try XCTUnwrap(HeadDirectionProjection.approximate(pose: pose(), mirrored: false, display: screen))
        XCTAssertEqual(neutral, CGPoint(x: 500, y: 400))
        let yaw = try XCTUnwrap(HeadDirectionProjection.approximate(pose: pose(0.1), mirrored: false, display: screen))
        let pitch = try XCTUnwrap(HeadDirectionProjection.approximate(pose: pose(0, 0.1), mirrored: false, display: screen))
        XCTAssertLessThan(yaw.x, neutral.x)
        XCTAssertGreaterThan(pitch.y, neutral.y)
        let mirrored = try XCTUnwrap(HeadDirectionProjection.approximate(pose: pose(0.1), mirrored: true, display: screen))
        XCTAssertGreaterThan(mirrored.x, neutral.x)
    }
    func testInvalidPoseIsUnavailable() {
        XCTAssertNil(HeadDirectionProjection.approximate(pose: pose(.nan), mirrored: false, display: CGRect(x: 0, y: 0, width: 100, height: 100)))
    }
}
