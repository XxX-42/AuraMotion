import XCTest
@testable import AuraMotionCore

final class AccessibilityTargetSamplingTests: XCTestCase {
    func testKnownCandidateCenterIsRecheckedWithinBound() {
        let gaze = CGPoint(x: 100, y: 100)
        let frame = CGRect(x: 109, y: 117, width: 20, height: 14)
        let points = AccessibilityTargetSampling.points(gaze: gaze, recheckFrame: frame)
        XCTAssertEqual(points.count, 14)
        XCTAssertTrue(points.contains(CGPoint(x: frame.midX, y: frame.midY)))
        XCTAssertEqual(points.first, gaze)
    }
    func testDuplicateAndInvalidCandidateDoNotExpandQueries() {
        let gaze = CGPoint(x: 100, y: 100)
        XCTAssertEqual(AccessibilityTargetSampling.points(gaze: gaze, recheckFrame: CGRect(x: 90, y: 90, width: 20, height: 20)).count, 13)
        XCTAssertEqual(AccessibilityTargetSampling.points(gaze: gaze, recheckFrame: .null).count, 13)
        XCTAssertEqual(AccessibilityTargetSampling.points(gaze: gaze, recheckFrame: nil).count, 13)
    }
}
