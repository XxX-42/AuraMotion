import XCTest
import CoreGraphics
@testable import AuraMotionCore

final class CursorDynamicsTests: XCTestCase {
    func testSlowDriftAccumulatesThroughAdaptiveDeadzone() throws {
        var settings = CursorExperimentSettings()
        settings.adaptiveDeadzoneEnabled = true
        let controller = CursorDynamicsController(settings: settings)

        _ = try XCTUnwrap(controller.process(target: CGPoint(x: 100, y: 200), timestamp: 1, phase: .pointer))
        var result: CursorDynamicsResult?
        for frame in 1...120 {
            result = controller.process(
                target: CGPoint(x: 100 + Double(frame) * 0.1, y: 200),
                timestamp: 1 + Double(frame) / 60,
                phase: .pointer
            )
        }

        let final = try XCTUnwrap(result)
        XCTAssertEqual(final.deadzone, 4, accuracy: 0.05, "Slow drift should use nearly the resting zone")
        XCTAssertGreaterThan(final.point.x, 106, "Sub-deadzone steps should accumulate instead of locking the cursor")
        XCTAssertLessThan(final.point.x, 109, "The output should remain continuously bounded by the zone")
    }

    func testPhaseChangesAndConfigurationPreserveVisiblePoint() throws {
        var settings = CursorExperimentSettings()
        settings.adaptiveDeadzoneEnabled = true
        settings.lowSpeedQuantizationEnabled = true
        settings.velocityGainEnabled = true
        settings.separateDragTuningEnabled = true
        let controller = CursorDynamicsController(settings: settings)

        let initial = try XCTUnwrap(controller.process(
            target: CGPoint(x: 10.4, y: 20.4), timestamp: 1, phase: .pointer
        ))
        XCTAssertEqual(initial.point, CGPoint(x: 10, y: 20))
        _ = try XCTUnwrap(controller.process(
            target: CGPoint(x: 12, y: 20.4), timestamp: 1.1, phase: .pointer
        ))
        let visibleBeforeConfigure = try XCTUnwrap(controller.process(
            target: CGPoint(x: 12, y: 20.4), timestamp: 1.2, phase: .pointer
        )).point

        controller.configure(CursorExperimentSettings())
        let afterConfigure = try XCTUnwrap(controller.process(
            target: CGPoint(x: 12, y: 20.4), timestamp: 1.3, phase: .pointer
        ))
        XCTAssertEqual(afterConfigure.point, visibleBeforeConfigure)

        let afterPhaseChange = try XCTUnwrap(controller.process(
            target: CGPoint(x: 12, y: 20.4), timestamp: 1.4, phase: .drag
        ))
        XCTAssertEqual(afterPhaseChange.point, afterConfigure.point)
    }

    func testVelocityGainIsContinuousMonotoneAndBounded() throws {
        var settings = CursorExperimentSettings()
        settings.velocityGainEnabled = true
        let speeds = [0.0, 30.0, 59.9, 60.0, 100.0, 299.9, 300.0, 500.0, 899.9, 900.0, 2_000.0]
        var gains: [Double] = []

        for speed in speeds {
            let controller = CursorDynamicsController(settings: settings)
            _ = controller.process(target: .zero, timestamp: 0, phase: .pointer)
            let result = try XCTUnwrap(controller.process(
                target: CGPoint(x: speed * 0.01, y: 0),
                timestamp: 0.01,
                phase: .pointer
            ))
            gains.append(result.gain)
            XCTAssertGreaterThanOrEqual(result.gain, settings.precisionGain)
            XCTAssertLessThanOrEqual(result.gain, settings.fastGain)
        }

        XCTAssertEqual(gains[3], 0.4, accuracy: 0.0001)
        XCTAssertEqual(gains[6], 1.0, accuracy: 0.0001)
        XCTAssertEqual(gains[9], 1.7, accuracy: 0.0001)
        for index in 1..<gains.count {
            XCTAssertGreaterThanOrEqual(gains[index], gains[index - 1])
        }
        XCTAssertLessThan(gains[3] - gains[2], 0.01, "Samples immediately around 60 px/s should remain continuous")
        XCTAssertLessThan(gains[6] - gains[5], 0.01, "Samples immediately around 300 px/s should remain continuous")
        XCTAssertLessThan(gains[9] - gains[8], 0.01, "Samples immediately around 900 px/s should remain continuous")
    }

    func testLowSpeedQuantizesAndHighSpeedKeepsFractionalCoordinates() throws {
        var settings = CursorExperimentSettings()
        settings.lowSpeedQuantizationEnabled = true
        let controller = CursorDynamicsController(settings: settings)

        let slow = try XCTUnwrap(controller.process(
            target: CGPoint(x: 10.2, y: 20.4), timestamp: 1, phase: .pointer
        ))
        XCTAssertEqual(slow.point, CGPoint(x: 10, y: 20))

        let fast = try XCTUnwrap(controller.process(
            target: CGPoint(x: 12.5, y: 22.75), timestamp: 1.016, phase: .pointer
        ))
        XCTAssertEqual(fast.point.x, 12.5, accuracy: 0.0001)
        XCTAssertEqual(fast.point.y, 22.75, accuracy: 0.0001)
        XCTAssertGreaterThan(fast.speed, settings.quantizationSpeedThreshold)
    }

    func testDragUsesSmallerDeadzoneAndSkipsQuantizationWhenSeparated() throws {
        var settings = CursorExperimentSettings()
        settings.adaptiveDeadzoneEnabled = true
        settings.lowSpeedQuantizationEnabled = true
        settings.separateDragTuningEnabled = true
        let pointer = CursorDynamicsController(settings: settings)
        let drag = CursorDynamicsController(settings: settings)

        _ = pointer.process(target: CGPoint(x: 100, y: 0), timestamp: 0, phase: .pointer)
        _ = drag.process(target: CGPoint(x: 100, y: 0), timestamp: 0, phase: .pointer)
        var pointerResult: CursorDynamicsResult?
        var dragResult: CursorDynamicsResult?
        for frame in 1...60 {
            let target = CGPoint(x: 100 + Double(frame) * 0.05, y: 0)
            let timestamp = Double(frame) / 60
            pointerResult = pointer.process(target: target, timestamp: timestamp, phase: .pointer)
            dragResult = drag.process(target: target, timestamp: timestamp, phase: .drag)
        }
        let pointerFinal = try XCTUnwrap(pointerResult)
        let dragFinal = try XCTUnwrap(dragResult)

        XCTAssertEqual(pointerFinal.point.x, 100, accuracy: 0.001)
        XCTAssertGreaterThan(dragFinal.point.x, 101)
        XCTAssertNotEqual(dragFinal.point.x.rounded(), dragFinal.point.x, accuracy: 0.001)
        XCTAssertLessThan(dragFinal.deadzone, pointerFinal.deadzone)
    }

    func testDisabledModulesTrackTargetsExactlyAndInvalidSamplesDoNotPoisonState() throws {
        let controller = CursorDynamicsController()
        let firstTarget = CGPoint(x: 101.25, y: 202.75)
        let first = try XCTUnwrap(controller.process(target: firstTarget, timestamp: 1, phase: .pointer))
        XCTAssertEqual(first.point, firstTarget)
        XCTAssertEqual(first.deadzone, 0)
        XCTAssertEqual(first.gain, 1)

        let duplicate = try XCTUnwrap(controller.process(
            target: CGPoint(x: 900, y: 900), timestamp: 1, phase: .pointer
        ))
        XCTAssertEqual(duplicate.point, first.point)

        let target = CGPoint(x: 105.5, y: 205.25)
        let result = try XCTUnwrap(controller.process(target: target, timestamp: 1.1, phase: .pointer))
        XCTAssertEqual(result.point.x, target.x, accuracy: 0.0001)
        XCTAssertEqual(result.point.y, target.y, accuracy: 0.0001)
        XCTAssertEqual(controller.process(
            target: CGPoint(x: CGFloat.nan, y: 0), timestamp: 1.2, phase: .pointer
        )?.point, result.point)

        let afterGap = try XCTUnwrap(controller.process(
            target: CGPoint(x: 700, y: 500), timestamp: 2, phase: .pointer
        ))
        XCTAssertEqual(afterGap.point, result.point, "A long gap should reanchor input without moving output")
        XCTAssertEqual(afterGap.speed, 0)
    }
}
