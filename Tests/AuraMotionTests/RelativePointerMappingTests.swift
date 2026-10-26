import XCTest
import CoreGraphics
@testable import AuraMotionCore

final class RelativePointerMappingTests: XCTestCase {
    func testFirstHandSampleAnchorsAtVisibleCursorThenAppliesDeltas() {
        var mapping = RelativePointerMapping()
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        mapping.rebase(to: CGPoint(x: 240, y: 360))

        let first = mapping.map(
            target: CGPoint(x: 700, y: 250),
            currentCursor: CGPoint(x: 250, y: 350),
            displayBounds: bounds
        )
        XCTAssertEqual(first, CGPoint(x: 240, y: 360))

        let moved = mapping.map(
            target: CGPoint(x: 715, y: 230),
            currentCursor: nil,
            displayBounds: bounds
        )
        XCTAssertEqual(moved, CGPoint(x: 255, y: 340))
        XCTAssertEqual(mapping.lastHandDelta, CGPoint(x: 15, y: -20))
        XCTAssertEqual(mapping.lastCursorDelta, CGPoint(x: 15, y: -20))
    }

    func testFreezeAndResumeRebaseWithoutJump() {
        var mapping = RelativePointerMapping()
        let bounds = CGRect(x: -500, y: 0, width: 1500, height: 900)
        mapping.rebase(to: CGPoint(x: 200, y: 300))
        _ = mapping.map(target: CGPoint(x: 400, y: 400), currentCursor: nil, displayBounds: bounds)
        let beforeFreeze = mapping.map(target: CGPoint(x: 430, y: 380), currentCursor: nil, displayBounds: bounds)
        XCTAssertEqual(beforeFreeze, CGPoint(x: 230, y: 280))

        mapping.freeze(at: CGPoint(x: 810, y: 610))
        let held = mapping.map(target: CGPoint(x: 900, y: 100), currentCursor: nil, displayBounds: bounds)
        XCTAssertEqual(held, CGPoint(x: 810, y: 610))

        mapping.rebase(to: CGPoint(x: 810, y: 610))
        let resumed = mapping.map(target: CGPoint(x: -100, y: 850), currentCursor: nil, displayBounds: bounds)
        XCTAssertEqual(resumed, CGPoint(x: 810, y: 610))
        let resumedMove = mapping.map(target: CGPoint(x: -125, y: 840), currentCursor: nil, displayBounds: bounds)
        XCTAssertEqual(resumedMove, CGPoint(x: 785, y: 600))
    }

    func testRelativeOutputClampsToNegativeOriginDisplayBounds() {
        var mapping = RelativePointerMapping()
        let bounds = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        mapping.rebase(to: CGPoint(x: -10, y: 500))

        _ = mapping.map(target: CGPoint(x: 0, y: 0), currentCursor: nil, displayBounds: bounds)
        let beyondRight = mapping.map(target: CGPoint(x: 200, y: 20), currentCursor: nil, displayBounds: bounds)
        XCTAssertEqual(beyondRight, CGPoint(x: 0, y: 520))

        let movingBack = mapping.map(target: CGPoint(x: 10, y: 20), currentCursor: nil, displayBounds: bounds)
        XCTAssertEqual(movingBack, CGPoint(x: 0, y: 520))
    }

    func testRelativeMappingPreservesRebaseOnAnActiveSecondaryDisplay() {
        let displays = [
            CGRect(x: 0, y: 0, width: 2048, height: 1280),
            CGRect(x: 161, y: -1024, width: 1366, height: 1024)
        ]
        let sidecarCursor = CGPoint(x: 800, y: -770)
        var mapping = RelativePointerMapping()
        mapping.rebase(to: sidecarCursor)

        let first = mapping.map(
            target: CGPoint(x: 400, y: 500),
            currentCursor: sidecarCursor,
            displayBounds: displays
        )
        XCTAssertEqual(first, sidecarCursor, "The first tracked sample must preserve the visible Sidecar cursor.")

        let next = mapping.map(
            target: CGPoint(x: 410, y: 510),
            currentCursor: first,
            displayBounds: displays
        )
        XCTAssertEqual(next, CGPoint(x: 810, y: -760))
        XCTAssertTrue(displays.contains { $0.contains(next ?? .zero) })
    }
}
