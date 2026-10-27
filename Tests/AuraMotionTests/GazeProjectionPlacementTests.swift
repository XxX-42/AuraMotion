import XCTest
@testable import AuraMotionCore

final class GazeProjectionPlacementTests: XCTestCase {
    func testTopLeftQuartzBecomesTopLeftAppKit() throws {
        let display = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let frame = try XCTUnwrap(GazeProjectionPlacement.panelFrame(point: CGPoint(x: 100,y: 200), quartzDisplay: display, appKitDisplay: display, size: 32))
        XCTAssertEqual(frame.midX, 100); XCTAssertEqual(frame.midY, 600)
    }
    func testOutOfBoundsAndNonFiniteAreHidden() {
        let display = CGRect(x: 0, y: 0, width: 1000, height: 800)
        XCTAssertNil(GazeProjectionPlacement.panelFrame(point: CGPoint(x: -1,y: 100), quartzDisplay: display, appKitDisplay: display, size: 32))
        XCTAssertNil(GazeProjectionPlacement.panelFrame(point: CGPoint(x: CGFloat.nan,y: 100), quartzDisplay: display, appKitDisplay: display, size: 32))
    }
}
