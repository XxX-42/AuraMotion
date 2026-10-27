import XCTest
@testable import AuraMotionCore

final class TargetFocusStabilizerTests: XCTestCase {
    func testSameTargetFocusesWithoutRequiringStablePoint() {
        var s = TargetFocusStabilizer<String>()
        XCTAssertEqual(s.update("A", timestamp: 1.00), .candidate("A"))
        XCTAssertEqual(s.update("A", timestamp: 1.05), .candidate("A"))
        XCTAssertEqual(s.update("A", timestamp: 1.10), .candidate("A"))
        XCTAssertEqual(s.update("A", timestamp: 1.15), .focused("A"))
    }
    func testNewTargetIsCandidateAndCannotInheritOldDwell() {
        var s = TargetFocusStabilizer<String>()
        _ = s.update("A", timestamp: 0)
        XCTAssertEqual(s.update("A", timestamp: 0.15), .focused("A"))
        XCTAssertEqual(s.update("B", timestamp: 0.20), .candidate("B"))
        XCTAssertEqual(s.update("B", timestamp: 0.30), .candidate("B"))
        XCTAssertEqual(s.update("B", timestamp: 0.34), .focused("B"))
    }
    func testShortMissIsNeverActionableAndLongMissClearsIdentity() {
        var s = TargetFocusStabilizer<String>()
        _ = s.update("A", timestamp: 1.0)
        XCTAssertEqual(s.update("A", timestamp: 1.15), .focused("A"))
        XCTAssertEqual(s.temporarilyMissing(timestamp: 1.25), .candidate("A"))
        XCTAssertEqual(s.update("A", timestamp: 1.30), .focused("A"))
        XCTAssertEqual(s.temporarilyMissing(timestamp: 1.51), .unavailable)
        XCTAssertEqual(s.update("A", timestamp: 1.55), .candidate("A"))
    }
    func testLostInputGapAndReorderedFramesClearDwell() {
        var s = TargetFocusStabilizer<String>()
        _ = s.update("A", timestamp: 0)
        XCTAssertEqual(s.update(nil, timestamp: 0.1), .unavailable)
        XCTAssertEqual(s.update("A", timestamp: 0.2), .candidate("A"))
        XCTAssertEqual(s.update("A", timestamp: 0.8), .candidate("A"))
        XCTAssertEqual(s.update("A", timestamp: 0.7), .candidate("A"))
    }
}
