import XCTest
import CoreGraphics
@testable import AuraMotionCore

final class RelativePointerControllerTests: XCTestCase {
    func testHotDisableKeepsLegacyMappingContinuousAcrossSteadyFrames() throws {
        let profile = CalibrationProfile(
            activeRegion: CGRect(x: 0, y: 0, width: 1, height: 1),
            displayBounds: CGRect(x: 0, y: 0, width: 1000, height: 800)
        )
        let controller = CursorController(profile: profile)
        let visible = CGPoint(x: 420, y: 310)
        var optimized = CursorExperimentSettings()
        optimized.relativeMappingEnabled = true
        optimized.mappingMode = .relativeRebased

        controller.reconfigure(optimized, cursorPosition: visible)
        controller.setInteractionState(.pointer, currentCursor: visible)
        _ = try XCTUnwrap(controller.processIndexTip(normalizedPoint: CGPoint(x: 0.5, y: 0.5), timestamp: 1.0))
        let beforeDisable = try XCTUnwrap(controller.processIndexTip(
            normalizedPoint: CGPoint(x: 0.5, y: 0.5), timestamp: 1.033
        ))
        XCTAssertEqual(beforeDisable.x, visible.x, accuracy: 0.01)
        XCTAssertEqual(beforeDisable.y, visible.y, accuracy: 0.01)

        // Recreate AppEnvironment's settings-change sequence.
        controller.freeze(at: beforeDisable)
        controller.reconfigure(CursorExperimentSettings(), cursorPosition: beforeDisable)
        let baselineFrame1 = try XCTUnwrap(controller.processIndexTip(
            normalizedPoint: CGPoint(x: 0.5, y: 0.5), timestamp: 1.066
        ))
        let baselineFrame2 = try XCTUnwrap(controller.processIndexTip(
            normalizedPoint: CGPoint(x: 0.5, y: 0.5), timestamp: 1.099
        ))
        let baselineFrame3 = try XCTUnwrap(controller.processIndexTip(
            normalizedPoint: CGPoint(x: 0.52, y: 0.5), timestamp: 1.132
        ))

        XCTAssertEqual(baselineFrame1.x, beforeDisable.x, accuracy: 0.01)
        XCTAssertEqual(baselineFrame1.y, beforeDisable.y, accuracy: 0.01)
        XCTAssertEqual(baselineFrame2.x, beforeDisable.x, accuracy: 0.01)
        XCTAssertEqual(baselineFrame2.y, beforeDisable.y, accuracy: 0.01)
        XCTAssertGreaterThan(baselineFrame3.x, baselineFrame2.x)
        XCTAssertLessThan(baselineFrame3.x - baselineFrame2.x, 10)
    }

    func testFrozenPhaseResumesAtSuppliedPhysicalCursorPosition() throws {
        let profile = CalibrationProfile(
            activeRegion: CGRect(x: 0, y: 0, width: 1, height: 1),
            displayBounds: CGRect(x: 0, y: 0, width: 1000, height: 800)
        )
        let controller = CursorController(profile: profile)
        let original = CGPoint(x: 400, y: 300)
        var settings = CursorExperimentSettings()
        settings.relativeMappingEnabled = true
        settings.mappingMode = .relativeRebased

        controller.reconfigure(settings, cursorPosition: original)
        controller.setInteractionState(.pointer, currentCursor: original)
        _ = try XCTUnwrap(controller.processIndexTip(normalizedPoint: CGPoint(x: 0.5, y: 0.5), timestamp: 2.0))

        let physicalCursor = CGPoint(x: 720, y: 510)
        controller.setInteractionState(.scrolling, currentCursor: physicalCursor)
        let frozen = try XCTUnwrap(controller.processIndexTip(
            normalizedPoint: CGPoint(x: 0.9, y: 0.9), timestamp: 2.033
        ))
        XCTAssertEqual(frozen.x, physicalCursor.x, accuracy: 0.01)
        XCTAssertEqual(frozen.y, physicalCursor.y, accuracy: 0.01)

        controller.setInteractionState(.pointer, currentCursor: physicalCursor)
        let resumed = try XCTUnwrap(controller.processIndexTip(
            normalizedPoint: CGPoint(x: 0.9, y: 0.9), timestamp: 2.066
        ))
        XCTAssertEqual(resumed.x, physicalCursor.x, accuracy: 0.01)
        XCTAssertEqual(resumed.y, physicalCursor.y, accuracy: 0.01)

        let moved = try XCTUnwrap(controller.processIndexTip(
            normalizedPoint: CGPoint(x: 0.91, y: 0.91), timestamp: 2.099
        ))
        XCTAssertGreaterThan(moved.x, physicalCursor.x)
        XCTAssertLessThan(moved.y, physicalCursor.y)
    }
}
