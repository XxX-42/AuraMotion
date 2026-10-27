import XCTest
import simd
@testable import AuraMotionCore

final class AngularGazeCalibrationTests: XCTestCase {
    let geometry = DebugScreenGeometry(width: 340, height: 190, offsetX: 0, offsetY: 10)
    let rotation = [1.0,0,0, 0,1,0, 0,0,1]
    func sample(_ target: CGPoint) -> AngularGazeCalibration.Sample {
        let eye = SIMD3<Double>(0, 40, 600)
        let v = simd_normalize(SIMD3(170 - target.x * 340, 10 + target.y * 190 - eye.y, -600))
        let p = asin(-v.y), y = atan2(-v.x, -v.z)
        let frame = AngularGazeFrame(pitch: (p-0.04)/1.4, yaw: (y+0.03)/0.8, eye: eye, rotation: rotation)
        return .init(frame: frame, target: target)
    }
    func testNineTargetsFitAnglesThenProjectToScreen() throws {
        let samples = GazeCalibration.nineTargets.map(sample)
        let calibration = try AngularGazeCalibration.fit(samples, geometry: geometry)
        for sample in samples {
            let result = try XCTUnwrap(calibration.project(sample.frame))
            XCTAssertEqual(result.x, sample.target.x, accuracy: 0.01)
            XCTAssertEqual(result.y, sample.target.y, accuracy: 0.01)
        }
        XCTAssertLessThan(try XCTUnwrap(calibration.project(samples[1].frame)).y, try XCTUnwrap(calibration.project(samples[7].frame)).y)
        XCTAssertLessThan(try XCTUnwrap(calibration.project(samples[3].frame)).x, try XCTUnwrap(calibration.project(samples[5].frame)).x)
    }
    func testRepeatedFramesAtOneTargetDoNotChangeFit() throws {
        let samples = GazeCalibration.nineTargets.map(sample)
        let baseline = try AngularGazeCalibration.fit(samples, geometry: geometry)
        let repeated = samples + Array(repeating: samples[8], count: 100)
        let balanced = try AngularGazeCalibration.fit(repeated, geometry: geometry)
        for sample in samples {
            let a = try XCTUnwrap(baseline.project(sample.frame))
            let b = try XCTUnwrap(balanced.project(sample.frame))
            XCTAssertEqual(a.x, b.x, accuracy: 1e-8)
            XCTAssertEqual(a.y, b.y, accuracy: 1e-8)
        }
    }
    func testInvalidAndInsufficientVariationRejected() throws {
        let flat = GazeCalibration.nineTargets.map { AngularGazeCalibration.Sample(frame: AngularGazeFrame(pitch: 0, yaw: 0, eye: SIMD3(0, 0, 600), rotation: rotation), target: $0) }
        XCTAssertThrowsError(try AngularGazeCalibration.fit(flat, geometry: geometry))
        let model = try AngularGazeCalibration.fit(GazeCalibration.nineTargets.map(sample), geometry: geometry)
        XCTAssertNil(model.project(AngularGazeFrame(pitch: 0, yaw: 0, eye: SIMD3(0, 0, -1), rotation: rotation)))
        XCTAssertNil(model.project(AngularGazeFrame(pitch: 0, yaw: 0, eye: SIMD3(0, 0, 600), rotation: [])))
    }
}
