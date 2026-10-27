import XCTest
import simd
@testable import AuraMotionCore

final class IrisSeparabilityBenchmarkTests: XCTestCase {
    private func face(id: UInt64, t: Double, x: Float, y: Float) -> FaceSample {
        var p = Array(repeating: FaceLandmark(x: 0.5, y: 0.5, z: 0), count: 478)
        func set(_ i: Int, _ x: Float, _ y: Float) { p[i] = FaceLandmark(x: x, y: y, z: 0) }
        set(33,0.2,0.4); set(133,0.4,0.4); set(159,0.3,0.37); set(145,0.3,0.43)
        set(362,0.6,0.4); set(263,0.8,0.4); set(386,0.7,0.37); set(374,0.7,0.43)
        return FaceSample(frameID: id, timestamp: t, isTimestampEstimated: false, isMirrored: false, landmarks: p,
            headTransform: matrix_identity_float4x4, headPose: HeadPose(yaw: 0, pitch: 0, roll: 0, centerX: 0.5, centerY: 0.5, scale: 0.5),
            leftIrisCenter: SIMD3(0.6 + 0.2*x,0.37 + 0.06*y,0), rightIrisCenter: SIMD3(0.2 + 0.2*x,0.37 + 0.06*y,0), confidence: nil)
    }
    func testPairedNineTargetSeparabilityAndTiming() throws {
        var bench = IrisSeparabilityBenchmark()
        for target in 0..<9 {
            for frame in 0..<8 {
                let id = UInt64(target * 8 + frame + 1), t = Double(target * 10) + Double(frame) * 0.1
                let x = Float(target % 3) * 0.3 + 0.2 + Float(frame % 2) * 0.001
                let y = Float(target / 3) * 0.3 + 0.2 + Float(frame % 2) * 0.001
                let sample = face(id: id, t: t, x: x, y: y)
                bench.append(IrisBenchmarkFrame(frameID: id, timestamp: t, small: sample, large: sample, ms320: 10, ms640: 20, width: 640, height: 360), target: target)
            }
        }
        let report = try bench.report()
        XCTAssertEqual(report.attemptedPairs, 72)
        XCTAssertEqual(report.validPairs, 72)
        XCTAssertEqual(report.normalized320.heldOutAccuracy, 1)
        XCTAssertEqual(report.normalized640.heldOutAccuracy, 1)
        XCTAssertGreaterThan(try XCTUnwrap(report.normalized640.separationRatio), 20)
        XCTAssertEqual(try XCTUnwrap(report.pairedFPS), 10, accuracy: 0.001)
        XCTAssertEqual(report.meanInferenceMs320, 10)
    }
    func testIndistinguishableTargetsDoNotAppearSeparable() throws {
        var bench = IrisSeparabilityBenchmark()
        for target in 0..<9 {
            for frame in 0..<8 {
                let id = UInt64(target * 8 + frame + 1), time = Double(target * 10) + Double(frame) * 0.1
                let x: Float = frame.isMultiple(of: 2) ? 0.49 : 0.51
                let sample = face(id: id, t: time, x: x, y: 0.5)
                bench.append(IrisBenchmarkFrame(frameID: id, timestamp: time, small: sample, large: sample, ms320: 1, ms640: 2, width: 640, height: 360), target: target)
            }
        }
        let result = try bench.report()
        XCTAssertEqual(result.normalized320.minimumCentroidDistance, 0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(result.normalized320.separationRatio), 0, accuracy: 1e-9)
        XCTAssertEqual(result.normalized320.heldOutAccuracy, 1.0 / 9, accuracy: 1e-9)
    }

    func testMismatchDuplicatesAndMissingDataCannotMakePairs() {
        var bench = IrisSeparabilityBenchmark()
        let small = face(id: 2, t: 1, x: 0.5, y: 0.5)
        let wrong = face(id: 3, t: 1, x: 0.5, y: 0.5)
        let f = IrisBenchmarkFrame(frameID: 2, timestamp: 1, small: small, large: wrong, ms320: 1, ms640: 2, width: 640, height: 360)
        bench.append(f, target: 0); bench.append(f, target: 0)
        XCTAssertEqual(bench.observations.count, 1)
        XCTAssertEqual(bench.validCount(target: 0), 0)
        XCTAssertThrowsError(try bench.report())
    }
    func testRejectsUpscaledSource() {
        var bench = IrisSeparabilityBenchmark()
        let sample = face(id: 1, t: 1, x: 0.5, y: 0.5)
        bench.append(IrisBenchmarkFrame(frameID: 1, timestamp: 1, small: sample, large: sample, ms320: 1, ms640: 2, width: 320, height: 180), target: 0)
        XCTAssertThrowsError(try bench.report()) { XCTAssertTrue($0 is IrisSeparabilityBenchmark.Error) }
    }
}
