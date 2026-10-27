import XCTest
@testable import AuraMotionCore

final class DebugGazeStabilizerTests: XCTestCase {
    func testSuppressesStationaryNoiseAndFollowsMovement() throws {
        var filter = DebugGazeStabilizer()
        _ = filter.update(CGPoint(x: 0.5, y: 0.5), timestamp: 0)
        let jitter = try XCTUnwrap(filter.update(CGPoint(x: 0.51, y: 0.5), timestamp: 0.1))
        XCTAssertGreaterThan(jitter.x, 0.5)
        XCTAssertLessThan(jitter.x, 0.507)
        var moved = jitter
        for frame in 1...9 {
            moved = try XCTUnwrap(filter.update(CGPoint(x: 0.9, y: 0.5), timestamp: 0.1 + Double(frame) / 30))
        }
        XCTAssertGreaterThan(moved.x, 0.8)
    }
    func testAlternatingStationaryNoiseDoesNotCauseLargeMarkerJitter() throws {
        var filter = DebugGazeStabilizer()
        _ = filter.update(CGPoint(x: 0.5, y: 0.5), timestamp: 0)
        var values: [CGFloat] = []
        for frame in 1...120 {
            let noisy = 0.5 + (frame.isMultiple(of: 2) ? 0.04 : -0.04)
            let point = try XCTUnwrap(filter.update(CGPoint(x: noisy, y: 0.5), timestamp: Double(frame) / 30))
            values.append(point.x)
        }
        XCTAssertLessThan(try XCTUnwrap(values.max()) - XCTUnwrap(values.min()), 0.025)
    }
    func testGapAndInvalidInputReset() throws {
        var filter = DebugGazeStabilizer()
        _ = filter.update(.zero, timestamp: 1)
        XCTAssertEqual(filter.update(CGPoint(x: 0.8, y: 0.7), timestamp: 2), CGPoint(x: 0.8, y: 0.7))
        XCTAssertNil(filter.update(CGPoint(x: CGFloat.nan, y: 0), timestamp: 2.1))
        XCTAssertEqual(filter.update(CGPoint(x: 0.2, y: 0.3), timestamp: 2.2), CGPoint(x: 0.2, y: 0.3))
    }
    func testSustainedMovementRespondsWithoutFollowingSingleSpike() throws {
        var filter = DebugGazeStabilizer()
        _ = filter.update(CGPoint(x: 0.5, y: 0.5), timestamp: 0)
        let spike = try XCTUnwrap(filter.update(CGPoint(x: 0.9, y: 0.5), timestamp: 1.0 / 30))
        XCTAssertLessThan(spike.x, 0.57)
        _ = filter.update(CGPoint(x: 0.5, y: 0.5), timestamp: 2.0 / 30)
        var result = CGPoint.zero
        for frame in 3...8 {
            result = try XCTUnwrap(filter.update(CGPoint(x: 0.9, y: 0.5), timestamp: Double(frame) / 30))
        }
        XCTAssertGreaterThan(result.x, 0.82)
    }
}
