import XCTest
@testable import AuraMotionCore

final class SemanticTargetStabilizerTests: XCTestCase {
    func focused() -> SemanticTargetStabilizer<String> {
        var s = SemanticTargetStabilizer<String>()
        XCTAssertEqual(s.observeBest("A", inRetention: false, now: 0), .candidate("A"))
        XCTAssertEqual(s.observeBest("A", inRetention: false, now: 0.13), .focused("A"))
        return s
    }
    func testBriefExitRetainsButRequiresReconfirmation() {
        var s = focused()
        XCTAssertEqual(s.observeGaze(valid: true, inRetention: false, now: 0.15), .retained("A"))
        XCTAssertEqual(s.observeGaze(valid: true, inRetention: true, now: 0.30), .retained("A"))
        XCTAssertEqual(s.observeBest("A", inRetention: true, now: 0.31), .focused("A"))
    }
    func testLeavingAcquireWithinRetentionNeedsNewConfirmation() {
        var s = focused()
        XCTAssertEqual(s.observeGaze(valid: true, inRetention: true, inAcquire: false, now: 0.16), .retained("A"))
        XCTAssertEqual(s.observeBest("A", inRetention: true, now: 0.20), .focused("A"))
        XCTAssertEqual(s.observeGaze(valid: true, inRetention: true, inAcquire: false, now: 0.21), .focused("A"))
    }
    func testContinuousExitOrLostInputClearsAfter250ms() {
        var s = focused()
        _ = s.observeGaze(valid: true, inRetention: false, now: 0.15)
        XCTAssertEqual(s.observeGaze(valid: true, inRetention: false, now: 0.39), .retained("A"))
        XCTAssertEqual(s.observeGaze(valid: true, inRetention: false, now: 0.41), .unavailable)
        s = focused(); _ = s.observeGaze(valid: false, inRetention: false, now: 0.15)
        XCTAssertEqual(s.observeGaze(valid: false, inRetention: false, now: 0.41), .unavailable)
    }
    func testCompetitorMustWin150msAndCannotActDuringCompetition() {
        var s = focused()
        XCTAssertEqual(s.observeBest("B", inRetention: true, now: 0.20), .retained("A"))
        XCTAssertEqual(s.observeBest("B", inRetention: true, now: 0.30), .retained("A"))
        XCTAssertEqual(s.observeBest("B", inRetention: true, now: 0.36), .focused("B"))
    }
    func testBriefCompetingWinnerDoesNotSwitch() {
        var s = focused()
        XCTAssertEqual(s.observeBest("B", inRetention: true, now: 0.20), .retained("A"))
        XCTAssertEqual(s.observeBest("A", inRetention: true, now: 0.25), .focused("A"))
        XCTAssertEqual(s.observeBest("B", inRetention: true, now: 0.30), .retained("A"))
        XCTAssertEqual(s.observeBest("B", inRetention: true, now: 0.40), .retained("A"))
    }
    func testMissedAXResultIsNonActionableUntilFreshConfirmation() {
        var s = focused()
        XCTAssertEqual(s.observeBest(nil, inRetention: true, now: 0.20), .retained("A"))
        XCTAssertEqual(s.observeBest("A", inRetention: true, now: 0.25), .focused("A"))
        XCTAssertEqual(s.observeGaze(valid: true, inRetention: true, now: 0.66), .unavailable)
    }
    func testPinchLocksOriginalIdentityAndInvalidationPreventsAction() {
        var latch = SemanticPinchLatch<String>()
        latch.begin("A"); latch.begin("B")
        XCTAssertEqual(latch.takeAction(), "A")
        XCTAssertNil(latch.takeAction())
        latch.end(); latch.begin("B"); latch.invalidate()
        XCTAssertNil(latch.takeAction())
        latch.end(); latch.begin(nil); XCTAssertNil(latch.takeAction())
    }
}
