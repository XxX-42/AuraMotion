import XCTest
@testable import AuraMotionCore

final class GazeSpotlightGeometryTests: XCTestCase {
    func testCircleAndOpacityValues() throws {
        let frame = try XCTUnwrap(GazeSpotlightGeometry.circle(center: CGPoint(x: 150, y: 250)))
        XCTAssertEqual(frame.width, 1000); XCTAssertEqual(frame.height, 1000)
        XCTAssertEqual(frame.midX, 150); XCTAssertEqual(frame.midY, 250)
        XCTAssertEqual(GazeSpotlightGeometry.highlightOpacity, 0.05)
        XCTAssertEqual(GazeSpotlightGeometry.dimOpacity, 0.20)
    }
    func testInvalidPointRejected() {
        XCTAssertNil(GazeSpotlightGeometry.circle(center: CGPoint(x: CGFloat.nan, y: 0)))
    }
}
