import XCTest
import CoreGraphics
@testable import AuraMotionCore

final class FilterRuntimeTuningTests: XCTestCase {
    func testReconfigurePreservesFilterHistoryWithoutAFirstSampleJump() {
        let filter = OneEuroFilter2D(minCutoff: 0.5, beta: 0.008, dCutoff: 1.0)
        _ = filter.filter(point: CGPoint(x: 100, y: 200), timestamp: 1.0)
        let beforeConfiguration = filter.filter(point: CGPoint(x: 110, y: 210), timestamp: 1.016)

        filter.configure(minCutoff: 0.5, beta: 0, dCutoff: 10)

        XCTAssertEqual(filter.minCutoff, 0.5, accuracy: 0.0001)
        XCTAssertEqual(filter.beta, 0, accuracy: 0.0001)
        XCTAssertEqual(filter.dCutoff, 10, accuracy: 0.0001)

        let afterConfiguration = filter.filter(point: CGPoint(x: 200, y: 300), timestamp: 1.032)
        XCTAssertGreaterThan(afterConfiguration.x, beforeConfiguration.x)
        XCTAssertLessThan(afterConfiguration.x, 200, "Reconfiguration must keep the previous filter state")
        XCTAssertGreaterThan(afterConfiguration.y, beforeConfiguration.y)
        XCTAssertLessThan(afterConfiguration.y, 300, "Reconfiguration must keep the previous filter state")
    }

    func testOptimizedFilterPresetsResolveToTheirEffectiveValues() {
        let profile = CalibrationProfile()
        var settings = CursorExperimentSettings()
        settings.optimizedOneEuroEnabled = true
        settings.filterPreset = .precision
        settings.pointerMinCutoff = 8
        settings.pointerBeta = 0.09

        let precisionPointer = CursorFilterConfiguration.resolve(settings: settings, profile: profile, phase: .pointer)
        XCTAssertEqual(precisionPointer, CursorFilterConfiguration(minCutoff: 0.5, beta: 0.015, dCutoff: 1))
        let precisionDragWithoutToggle = CursorFilterConfiguration.resolve(settings: settings, profile: profile, phase: .drag)
        XCTAssertEqual(precisionDragWithoutToggle, precisionPointer)

        settings.separateDragTuningEnabled = true
        let precisionDrag = CursorFilterConfiguration.resolve(settings: settings, profile: profile, phase: .drag)
        XCTAssertEqual(precisionDrag, CursorFilterConfiguration(minCutoff: 1.1, beta: 0.018, dCutoff: 1))

        settings.filterPreset = .custom
        settings.pointerMinCutoff = 0.72
        settings.pointerBeta = 0.021
        settings.dragMinCutoff = 1.45
        settings.dragBeta = 0.031
        settings.derivativeCutoff = 2.25

        XCTAssertEqual(
            CursorFilterConfiguration.resolve(settings: settings, profile: profile, phase: .pointer),
            CursorFilterConfiguration(minCutoff: 0.72, beta: 0.021, dCutoff: 2.25)
        )
        XCTAssertEqual(
            CursorFilterConfiguration.resolve(settings: settings, profile: profile, phase: .drag),
            CursorFilterConfiguration(minCutoff: 1.45, beta: 0.031, dCutoff: 2.25)
        )
    }

    func testDragTuningToggleIsIndependentOfOptimizedPointerFilter() {
        let profile = CalibrationProfile()
        var settings = CursorExperimentSettings()
        settings.optimizedOneEuroEnabled = false
        settings.separateDragTuningEnabled = false

        let pointerBaseline = CursorFilterConfiguration.resolve(settings: settings, profile: profile, phase: .pointer)
        let dragBaseline = CursorFilterConfiguration.resolve(settings: settings, profile: profile, phase: .drag)
        XCTAssertEqual(pointerBaseline, CursorFilterConfiguration(minCutoff: 0.85, beta: 0.008, dCutoff: 1))
        XCTAssertEqual(dragBaseline, pointerBaseline)

        settings.separateDragTuningEnabled = true
        let pointerAfterToggle = CursorFilterConfiguration.resolve(settings: settings, profile: profile, phase: .pointer)
        let separatelyTunedDrag = CursorFilterConfiguration.resolve(settings: settings, profile: profile, phase: .drag)
        XCTAssertEqual(pointerAfterToggle, pointerBaseline)
        XCTAssertEqual(separatelyTunedDrag, CursorFilterConfiguration(minCutoff: 1.1, beta: 0.018, dCutoff: 1))
        XCTAssertNotEqual(separatelyTunedDrag, dragBaseline)
    }

    func testLegacyResolverClampsCalibrationToOriginalRanges() {
        var profile = CalibrationProfile()
        profile.cursorMinCutoff = 50
        profile.cursorMotionBeta = -1
        var settings = CursorExperimentSettings()
        settings.filterPreset = .legacy
        settings.optimizedOneEuroEnabled = true

        XCTAssertEqual(
            CursorFilterConfiguration.resolve(settings: settings, profile: profile, phase: .pointer),
            CursorFilterConfiguration(minCutoff: 1.5, beta: 0.004, dCutoff: 1)
        )

        profile.cursorMinCutoff = .nan
        profile.cursorMotionBeta = .infinity
        XCTAssertEqual(
            CursorFilterConfiguration.resolve(settings: settings, profile: profile, phase: .pointer),
            CursorFilterConfiguration(minCutoff: 0.85, beta: 0.008, dCutoff: 1)
        )
    }

    func testCustomResolverAndRuntimeConfigurationRejectNonFiniteAndOutOfRangeValues() {
        let profile = CalibrationProfile()
        var settings = CursorExperimentSettings()
        settings.optimizedOneEuroEnabled = true
        settings.filterPreset = .custom
        settings.pointerMinCutoff = .nan
        settings.pointerBeta = .infinity
        settings.derivativeCutoff = -10
        settings.separateDragTuningEnabled = true
        settings.dragMinCutoff = 20
        settings.dragBeta = -.infinity

        XCTAssertEqual(
            CursorFilterConfiguration.resolve(settings: settings, profile: profile, phase: .pointer),
            CursorFilterConfiguration(minCutoff: 0.5, beta: 0.015, dCutoff: 0.1)
        )
        XCTAssertEqual(
            CursorFilterConfiguration.resolve(settings: settings, profile: profile, phase: .drag),
            CursorFilterConfiguration(minCutoff: 10, beta: 0.018, dCutoff: 0.1)
        )

        let filter = OneEuroFilter2D()
        filter.configure(minCutoff: .nan, beta: 11, dCutoff: -.infinity)
        XCTAssertEqual(filter.minCutoff, 0.5, accuracy: 0.0001)
        XCTAssertEqual(filter.beta, 10, accuracy: 0.0001)
        XCTAssertEqual(filter.dCutoff, 1, accuracy: 0.0001)
    }

    func testInvalidCoordinatesAndTimestampsHoldLastGoodOutput() {
        let filter = OneEuroFilter2D()
        let first = filter.filter(point: CGPoint(x: 100, y: 200), timestamp: 1)

        XCTAssertEqual(filter.filter(point: CGPoint(x: CGFloat.infinity, y: 210), timestamp: 1.016), first)
        XCTAssertEqual(filter.filter(point: CGPoint(x: 110, y: 210), timestamp: .nan), first)

        let afterInvalidInput = filter.filter(point: CGPoint(x: 110, y: 210), timestamp: 1.016)
        let uninterrupted = OneEuroFilter2D()
        _ = uninterrupted.filter(point: CGPoint(x: 100, y: 200), timestamp: 1)
        let expected = uninterrupted.filter(point: CGPoint(x: 110, y: 210), timestamp: 1.016)
        XCTAssertEqual(afterInvalidInput, expected)
    }

    func testLegacyDefaultsMatchOriginalOneEuroOutput() {
        let settings = CursorExperimentSettings()
        let profile = CalibrationProfile()
        let resolved = CursorFilterConfiguration.resolve(settings: settings, profile: profile, phase: .pointer)
        XCTAssertEqual(resolved, CursorFilterConfiguration(minCutoff: 0.85, beta: 0.008, dCutoff: 1))

        let filter = OneEuroFilter2D(minCutoff: resolved.minCutoff, beta: resolved.beta, dCutoff: resolved.dCutoff)
        var expectedX = ReferenceOneEuroFilter(minCutoff: 0.85, beta: 0.008, dCutoff: 1)
        var expectedY = ReferenceOneEuroFilter(minCutoff: 0.85, beta: 0.008, dCutoff: 1)
        var timestamp: TimeInterval = 20

        for index in 0..<40 {
            let x = 960 + sin(Double(index) * 0.41) * 2
            let y = 540 + cos(Double(index) * 0.37) * 2
            let expected = CGPoint(
                x: expectedX.filter(x: x, timestamp: timestamp),
                y: expectedY.filter(x: y, timestamp: timestamp)
            )
            let actual = filter.filter(point: CGPoint(x: x, y: y), timestamp: timestamp)
            XCTAssertEqual(actual.x, expected.x, accuracy: 0.000001)
            XCTAssertEqual(actual.y, expected.y, accuracy: 0.000001)
            timestamp += 1.0 / 60.0
        }
    }
}

private struct ReferenceOneEuroFilter {
    let minCutoff: Double
    let beta: Double
    let dCutoff: Double
    private var xPrev: Double?
    private var rawPrev: Double?
    private var dxPrev = 0.0
    private var tPrev: TimeInterval?

    mutating func filter(x: Double, timestamp: TimeInterval) -> Double {
        guard let previousX = xPrev, let previousTime = tPrev else {
            xPrev = x
            rawPrev = x
            tPrev = timestamp
            return x
        }

        guard timestamp > previousTime else { return previousX }
        if timestamp - previousTime > 0.25 {
            xPrev = nil
            rawPrev = nil
            dxPrev = 0
            tPrev = nil
            return filter(x: x, timestamp: timestamp)
        }

        let dt = max(timestamp - previousTime, 1e-4)
        let rate = 1.0 / dt
        let dx = (x - (rawPrev ?? x)) * rate
        rawPrev = x
        let derivativeAlpha = alpha(rate: rate, cutoff: dCutoff)
        let derivative = derivativeAlpha * dx + (1 - derivativeAlpha) * dxPrev
        dxPrev = derivative
        let cutoff = minCutoff + beta * abs(derivative)
        let positionAlpha = alpha(rate: rate, cutoff: cutoff)
        let result = positionAlpha * x + (1 - positionAlpha) * previousX
        tPrev = timestamp
        xPrev = result
        return result
    }

    private func alpha(rate: Double, cutoff: Double) -> Double {
        let tau = 1.0 / (2.0 * Double.pi * cutoff)
        let te = 1.0 / rate
        return 1.0 / (1.0 + tau / te)
    }
}
