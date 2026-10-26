import XCTest
import simd
@testable import AuraMotionCore

final class GazePipelineTests: XCTestCase {
    private func face(time: Double = 1, closed: Bool = false, irisX: Float = 0.5, irisY: Float = 0.5, yaw: Float = 0, pitch: Float = 0, roll: Float = 0, faceScale: Float = 0.5) -> FaceSample {
        var p = Array(repeating: FaceLandmark(x: 0.5, y: 0.5, z: 0), count: 478)
        func set(_ i: Int, _ x: Float, _ y: Float) { p[i] = FaceLandmark(x: x, y: y, z: 0) }
        set(33,0.2,0.4); set(133,0.4,0.4); set(159,0.3,0.37); set(145,0.3,closed ? 0.371 : 0.43)
        set(362,0.6,0.4); set(263,0.8,0.4); set(386,0.7,0.37); set(374,0.7,closed ? 0.371 : 0.43)
        return FaceSample(frameID: 1, timestamp: time, isTimestampEstimated: false, isMirrored: false, landmarks: p,
            headTransform: matrix_identity_float4x4, headPose: HeadPose(yaw: yaw, pitch: pitch, roll: roll, centerX: 0.5, centerY: 0.5, scale: faceScale),
            leftIrisCenter: SIMD3(0.6 + 0.2*irisX, 0.37 + 0.06*irisY, 0), rightIrisCenter: SIMD3(0.2 + 0.2*irisX, 0.37 + 0.06*irisY, 0), confidence: nil)
    }
    private func controlledModel() -> GazeCalibration {
        GazeCalibration(featureMean: [0,0,0,0,0,0,0,0.5], featureScale: Array(repeating: 1, count: 8),
                        xWeights: [0.1,0.8,0,0,0,0.4,0,0,0], yWeights: [0.1,0,0.8,0,0,0,0.4,0,0],
                        irisXWeights: [0.1,0.8,0,0,0,0,0,0,0], irisYWeights: [0.1,0,0.8,0,0,0,0,0,0])
    }
    func testIrisDrivesScreenPointWithFixedHead() throws {
        let model = controlledModel(), bounds = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let left = try XCTUnwrap(GazeEstimator.estimate(face: face(irisX: 0.25, irisY: 0.5), calibration: model, displayBounds: bounds, mode: .irisDominant))
        let right = try XCTUnwrap(GazeEstimator.estimate(face: face(irisX: 0.75, irisY: 0.5), calibration: model, displayBounds: bounds, mode: .irisDominant))
        let up = try XCTUnwrap(GazeEstimator.estimate(face: face(irisX: 0.5, irisY: 0.25), calibration: model, displayBounds: bounds, mode: .irisDominant))
        let down = try XCTUnwrap(GazeEstimator.estimate(face: face(irisX: 0.5, irisY: 0.75), calibration: model, displayBounds: bounds, mode: .irisDominant))
        XCTAssertGreaterThan(right.screenPoint.x - left.screenPoint.x, 300)
        XCTAssertGreaterThan(down.screenPoint.y - up.screenPoint.y, 300)
    }
    func testHeadAloneIsWeakerThanLegacyAndBounded() throws {
        let model = controlledModel(), bounds = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let neutral = face(), moved = face(yaw: 1, pitch: 1)
        let i0 = try XCTUnwrap(GazeEstimator.estimate(face: neutral, calibration: model, displayBounds: bounds, mode: .irisDominant))
        let i1 = try XCTUnwrap(GazeEstimator.estimate(face: moved, calibration: model, displayBounds: bounds, mode: .irisDominant))
        let l0 = try XCTUnwrap(GazeEstimator.estimate(face: neutral, calibration: model, displayBounds: bounds, mode: .legacyFullFeature))
        let l1 = try XCTUnwrap(GazeEstimator.estimate(face: moved, calibration: model, displayBounds: bounds, mode: .legacyFullFeature))
        XCTAssertLessThan(abs(i1.screenPoint.x - i0.screenPoint.x), abs(l1.screenPoint.x - l0.screenPoint.x))
        XCTAssertLessThanOrEqual(abs(i1.screenPoint.x - i0.screenPoint.x), 50.0001)
        XCTAssertLessThanOrEqual(abs(i1.screenPoint.y - i0.screenPoint.y), 50.0001)
    }
    func testExtremeHeadCorrectionIsClampedAndScaleIsExcluded() throws {
        let model = controlledModel()
        let a = EyeFeatures([0.5,0.5,0.5,0.5,100,-100,50,0.5])
        let b = EyeFeatures([0.5,0.5,0.5,0.5,100,-100,50,50])
        let one = try XCTUnwrap(GazeEstimator.normalizedComponents(features: a, calibration: model, mode: .irisDominant))
        let two = try XCTUnwrap(GazeEstimator.normalizedComponents(features: b, calibration: model, mode: .irisDominant))
        let correction = try XCTUnwrap(one.headCorrection)
        XCTAssertEqual(correction.x, 0.05, accuracy: 1e-9)
        XCTAssertEqual(correction.y, -0.05, accuracy: 1e-9)
        XCTAssertEqual(one.final, two.final)
        XCTAssertNil(GazeEstimator.normalizedComponents(features: a, calibration: model, mode: .legacyFullFeature))
    }
    func testIrisOnlyTrainingZerosHeadAndScaleCoefficients() throws {
        let samples = GazeCalibration.nineTargets.map { p in
            GazeCalibrationPoint(features: EyeFeatures([p.x,p.y,p.x,p.y, p.x * 0.2,p.y * 0.3,(p.x-p.y)*0.1,0.4+p.x*0.05]), target: p)
        }
        let model = try GazeCalibration.fit(samples)
        XCTAssertEqual(Array(model.irisXWeights[5...8]), [0,0,0,0])
        XCTAssertEqual(Array(model.irisYWeights[5...8]), [0,0,0,0])
    }
    func testLegacyMatchesOriginalFullFeatureCalculation() throws {
        let model = controlledModel(), f = face(irisX: 0.4, irisY: 0.6, yaw: 0.25, pitch: -0.1)
        let features = try XCTUnwrap(EyeFeatureExtractor.extract(f))
        let values = [1.0] + zip(zip(features.vector, model.featureMean), model.featureScale).map { ($0.0.0 - $0.0.1) / $0.1 }
        let expectedX = zip(values, model.xWeights).reduce(0.0) { $0 + $1.0 * $1.1 }
        let expectedY = zip(values, model.yWeights).reduce(0.0) { $0 + $1.0 * $1.1 }
        let bounds = CGRect(x: 20, y: 30, width: 1000, height: 800)
        let explicit = try XCTUnwrap(GazeEstimator.estimate(face: f, calibration: model, displayBounds: bounds, mode: .legacyFullFeature))
        let implicit = try XCTUnwrap(GazeEstimator.estimate(face: f, calibration: model, displayBounds: bounds))
        XCTAssertEqual(explicit.screenPoint.x, bounds.minX + expectedX * bounds.width, accuracy: 1e-9)
        XCTAssertEqual(explicit.screenPoint.y, bounds.minY + expectedY * bounds.height, accuracy: 1e-9)
        XCTAssertEqual(explicit.screenPoint, implicit.screenPoint)
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
