import XCTest
@testable import AuraMotionCore

final class AccessibilityTargetScorerTests: XCTestCase {
    func testExpandedRegionAndPriority() throws {
        let button = AccessibilityTargetSnapshot(role: "AXButton", frame: CGRect(x: 100,y: 100,width: 20,height: 20), title: "Test", supportsPress: true)
        XCTAssertNotNil(AccessibilityTargetScorer.score(button, gaze: CGPoint(x: 135,y: 110), current: false))
        XCTAssertNil(AccessibilityTargetScorer.score(button, gaze: CGPoint(x: 180,y: 110), current: false))
        let near = try XCTUnwrap(AccessibilityTargetScorer.score(button, gaze: CGPoint(x: 110,y: 110), current: false))
        let expanded = try XCTUnwrap(AccessibilityTargetScorer.score(button, gaze: CGPoint(x: 135,y: 110), current: false))
        XCTAssertGreaterThan(near, expanded)
        XCTAssertGreaterThan(try XCTUnwrap(AccessibilityTargetScorer.score(button, gaze: CGPoint(x: 135,y: 110), current: true)), expanded)
    }
    func testVisualRetentionDoesNotExpandActionableHitArea() {
        let frame = CGRect(x: 100, y: 100, width: 20, height: 20)
        let target = AccessibilityTargetSnapshot(role: "AXButton", frame: frame, title: nil, supportsPress: true)
        let point = CGPoint(x: 175, y: 110)
        XCTAssertTrue(AccessibilityTargetScorer.visualRetentionFrame(frame).contains(point))
        XCTAssertNil(AccessibilityTargetScorer.score(target, gaze: point, current: false))
    }
    func testCloseSliderBeatsDistantButton() throws {
        let slider = AccessibilityTargetSnapshot(role: "AXSlider", frame: CGRect(x: 100,y: 100,width: 40,height: 20), title: nil, supportsPress: false)
        let button = AccessibilityTargetSnapshot(role: "AXButton", frame: CGRect(x: 170,y: 100,width: 20,height: 20), title: nil, supportsPress: true)
        let gaze = CGPoint(x: 139,y: 110)
        XCTAssertGreaterThan(try XCTUnwrap(AccessibilityTargetScorer.score(slider, gaze: gaze, current: false)), try XCTUnwrap(AccessibilityTargetScorer.score(button, gaze: gaze, current: false)))
    }
}
