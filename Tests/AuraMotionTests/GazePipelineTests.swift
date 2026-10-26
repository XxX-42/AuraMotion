import XCTest
import simd
@testable import AuraMotionCore

final class GazePipelineTests: XCTestCase {
    private func face(time: Double = 1, closed: Bool = false) -> FaceSample {
        var p = Array(repeating: FaceLandmark(x: 0.5, y: 0.5, z: 0), count: 478)
        func set(_ i: Int, _ x: Float, _ y: Float) { p[i] = FaceLandmark(x: x, y: y, z: 0) }
        set(33,0.2,0.4); set(133,0.4,0.4); set(159,0.3,0.37); set(145,0.3,closed ? 0.371 : 0.43)
        set(362,0.6,0.4); set(263,0.8,0.4); set(386,0.7,0.37); set(374,0.7,closed ? 0.371 : 0.43)
        return FaceSample(frameID: 1, timestamp: time, isTimestampEstimated: false, isMirrored: false, landmarks: p,
            headTransform: matrix_identity_float4x4, headPose: HeadPose(yaw: 0, pitch: 0, roll: 0, centerX: 0.5, centerY: 0.5, scale: 0.5),
            leftIrisCenter: SIMD3(0.7,0.4,0), rightIrisCenter: SIMD3(0.3,0.4,0), confidence: nil)
    }
    func testEyeNormalizationAndClosedEyeQualityGate() throws {
        let f = try XCTUnwrap(EyeFeatureExtractor.extract(face()))
        XCTAssertEqual(f.irisLX, 0.5, accuracy: 0.001)
        XCTAssertEqual(f.irisRY, 0.5, accuracy: 0.001)
        XCTAssertNil(EyeFeatureExtractor.extract(face(closed: true)))
    }
    func testNinePointFitAndDataValidation() throws {
        let samples = GazeCalibration.nineTargets.map { p in
            GazeCalibrationPoint(features: EyeFeatures([p.x,p.y,p.x,p.y,0,0,0,0.5]), target: p)
        }
        let model = try GazeCalibration.fit(samples)
        XCTAssertEqual(model.xWeights.count, 9)
        let result = try XCTUnwrap(GazeEstimator.estimate(face: face(), calibration: model, displayBounds: CGRect(x: 100, y: 50, width: 1000, height: 600)))
        XCTAssertEqual(result.screenPoint.x, 600, accuracy: 5)
        XCTAssertEqual(result.screenPoint.y, 350, accuracy: 5)
        XCTAssertEqual(result.timestamp, 1)
        XCTAssertNil(result.direction)
        XCTAssertNil(GazeEstimator.estimate(face: face(closed: true), calibration: model, displayBounds: CGRect(x: 0, y: 0, width: 1000, height: 600)))
        XCTAssertThrowsError(try GazeCalibration.fit(Array(samples.prefix(8))))
        XCTAssertThrowsError(try GazeCalibration.fit(Array(repeating: samples[0], count: 9)))
        let noVerticalSignal = GazeCalibration.nineTargets.map { p in
            GazeCalibrationPoint(features: EyeFeatures([p.x,0.5,p.x,0.5,0,0,0,0.5]), target: p)
        }
        XCTAssertThrowsError(try GazeCalibration.fit(noVerticalSignal))
    }
    func testFixationDwellHysteresisAndLostQuality() {
        var detector = FixationDetector()
        func estimate(_ x: CGFloat, _ t: Double, _ q: Float = 0.8) -> GazeEstimate {
            GazeEstimate(screenPoint: CGPoint(x:x,y:100), timestamp:t, direction:nil, confidence:q)
        }
        if case .candidate = detector.update(estimate(100, 1.0)) {} else { XCTFail() }
        if case .candidate = detector.update(estimate(102, 1.1)) {} else { XCTFail() }
        if case .focused = detector.update(estimate(103, 1.14)) {} else { XCTFail() }
        if case .focused = detector.update(estimate(160, 1.17)) {} else { XCTFail() }
        if case .candidate = detector.update(estimate(180, 1.18)) {} else { XCTFail() }
        XCTAssertEqual(detector.update(estimate(180, 1.19, 0.1)), .unavailable)
        if case .candidate = detector.update(estimate(180, 2)) {} else { XCTFail() }
        if case .candidate = detector.update(estimate(180, 2.3)) {} else { XCTFail() }
    }
}
