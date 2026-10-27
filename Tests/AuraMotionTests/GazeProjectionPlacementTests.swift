import XCTest
@testable import AuraMotionCore

final class GazeProjectionPlacementTests: XCTestCase {
    func testTopLeftQuartzBecomesTopLeftAppKit() throws {
        let display = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let frame = try XCTUnwrap(GazeProjectionPlacement.panelFrame(point: CGPoint(x: 100,y: 200), quartzDisplay: display, appKitDisplay: display, size: 32))
        XCTAssertEqual(frame.midX, 100); XCTAssertEqual(frame.midY, 600)
    }
    func testEdgesAndCornersRemainEntirelyVisible() throws {
        let display = CGRect(x: 0, y: 0, width: 1000, height: 800)
        for point in [CGPoint(x: -50,y: 400), CGPoint(x: 1100,y: 400), CGPoint(x: 500,y: -50), CGPoint(x: 500,y: 900), CGPoint(x: 1000,y: 800), CGPoint(x: 0,y: 0)] {
            let frame = try XCTUnwrap(GazeProjectionPlacement.panelFrame(point: point, quartzDisplay: display, appKitDisplay: display, size: 32))
            XCTAssertTrue(display.contains(frame), "marker must remain on the screen: \(frame)")
        }
    }
    func testLastMarkerIsVisualOnlyAndClearedWhenDisabled() {
        var visibility = GazeProjectionVisibility()
        let original = CGPoint(x: 100, y: 200)
        XCTAssertEqual(visibility.update(original, enabled: true).point, original)
        let missing = visibility.update(nil, enabled: true)
        XCTAssertEqual(missing.point, original); XCTAssertTrue(missing.stale)
        XCTAssertNil(visibility.update(nil, enabled: false).point)
        XCTAssertNil(visibility.update(nil, enabled: true).point)
    }
    func testNormalizedBoundsAndInvalidInput() {
        XCTAssertEqual(GazeProjectionPlacement.clampedNormalized(CGPoint(x: -0.2, y: 1.3)), CGPoint(x: 0, y: 1))
        XCTAssertNil(GazeProjectionPlacement.clampedNormalized(CGPoint(x: CGFloat.nan, y: 0)))
        let display = CGRect(x: 0, y: 0, width: 1000, height: 800)
        XCTAssertNil(GazeProjectionPlacement.panelFrame(point: CGPoint(x: CGFloat.nan, y: 100), quartzDisplay: display, appKitDisplay: display, size: 32))
    }
}
