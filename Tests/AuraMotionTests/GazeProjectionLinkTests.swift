import XCTest
@testable import AuraMotionCore

final class GazeProjectionLinkTests: XCTestCase {
    private let target = AccessibilityTargetSnapshot(role: "AXButton", frame: CGRect(x: 100, y: 200, width: 40, height: 20), title: nil, supportsPress: true)
    func testCandidateSnapsEvenWhenGazeTemporarilyMissing() {
        XCTAssertEqual(GazeProjectionLink.position(gaze: CGPoint(x: 50, y: 70), candidate: target, hasSemanticTarget: true, enabled: true), CGPoint(x: 120, y: 210))
        XCTAssertEqual(GazeProjectionLink.position(gaze: nil, candidate: target, hasSemanticTarget: true, enabled: true), CGPoint(x: 120, y: 210))
    }
    func testNoTargetShowsGaze() {
        let gaze = CGPoint(x: 50, y: 70)
        XCTAssertEqual(GazeProjectionLink.position(gaze: gaze, candidate: nil, hasSemanticTarget: false, enabled: true), gaze)
        XCTAssertEqual(GazeProjectionLink.position(gaze: gaze, candidate: target, hasSemanticTarget: true, enabled: true), CGPoint(x: 120, y: 210))
        XCTAssertEqual(GazeProjectionLink.position(gaze: gaze, candidate: target, hasSemanticTarget: false, enabled: true), gaze)
        XCTAssertNil(GazeProjectionLink.position(gaze: nil, candidate: nil, hasSemanticTarget: false, enabled: true))
    }
    func testAllSemanticStatesSnapToTheSameTarget() {
        let gaze = CGPoint(x: 50, y: 70)
        for state in ["candidate", "candidate · 短暂保留", "focused", "locked", "locked · AXPress 成功", "locked · 无可执行 AXPress", "retained · 等待重新确认"] {
            XCTAssertEqual(GazeProjectionLink.position(gaze: gaze, candidate: target, hasSemanticTarget: GazeProjectionLink.isTargetState(state), enabled: true), CGPoint(x: 120, y: 210))
        }
        XCTAssertFalse(GazeProjectionLink.isTargetState("无目标"))
    }
    func testDisabledAlwaysHides() {
        XCTAssertNil(GazeProjectionLink.position(gaze: CGPoint(x: 50, y: 70), candidate: target, hasSemanticTarget: true, enabled: false))
    }
}
