import XCTest
@testable import AuraMotionCore

final class GazeProjectionLinkTests: XCTestCase {
    private let target = AccessibilityTargetSnapshot(role: "AXButton", frame: CGRect(x: 100, y: 200, width: 40, height: 20), title: nil, supportsPress: true)
    func testCandidateSnapsEvenWhenGazeTemporarilyMissing() {
        XCTAssertEqual(GazeProjectionLink.position(gaze: CGPoint(x: 50, y: 70), candidate: target, isCandidate: true, enabled: true), CGPoint(x: 120, y: 210))
        XCTAssertEqual(GazeProjectionLink.position(gaze: nil, candidate: target, isCandidate: true, enabled: true), CGPoint(x: 120, y: 210))
    }
    func testNoCandidateOrConfirmedFocusShowsGaze() {
        let gaze = CGPoint(x: 50, y: 70)
        XCTAssertEqual(GazeProjectionLink.position(gaze: gaze, candidate: nil, isCandidate: false, enabled: true), gaze)
        XCTAssertEqual(GazeProjectionLink.position(gaze: gaze, candidate: target, isCandidate: false, enabled: true), gaze)
        XCTAssertNil(GazeProjectionLink.position(gaze: nil, candidate: nil, isCandidate: false, enabled: true))
    }
    func testDisabledAlwaysHides() {
        XCTAssertNil(GazeProjectionLink.position(gaze: CGPoint(x: 50, y: 70), candidate: target, isCandidate: true, enabled: false))
    }
}
