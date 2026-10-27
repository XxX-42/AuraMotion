import XCTest
@testable import AuraMotionCore

final class DebugGazeStabilizerTests: XCTestCase {
    func testSuppressesStationaryNoiseAndFollowsMovement() throws {
        var filter = DebugGazeStabilizer()
        _ = filter.update(CGPoint(x: 0.5, y: 0.5), timestamp: 0)
        let jitter = try XCTUnwrap(filter.update(CGPoint(x: 0.51, y: 0.5), timestamp: 0.1))
        XCTAssertGreaterThan(jitter.x, 0.5)
        XCTAssertLessThan(jitter.x, 0.507)
        let moved = try XCTUnwrap(filter.update(CGPoint(x: 0.9, y: 0.5), timestamp: 0.2))
        XCTAssertGreaterThan(moved.x, 0.75)
    }
    func testGapAndInvalidInputReset() throws {
        var filter = DebugGazeStabilizer()
        _ = filter.update(.zero, timestamp: 1)
        XCTAssertEqual(filter.update(CGPoint(x: 0.8, y: 0.7), timestamp: 2), CGPoint(x: 0.8, y: 0.7))
        XCTAssertNil(filter.update(CGPoint(x: CGFloat.nan, y: 0), timestamp: 2.1))
        XCTAssertEqual(filter.update(CGPoint(x: 0.2, y: 0.3), timestamp: 2.2), CGPoint(x: 0.2, y: 0.3))
    }
}
