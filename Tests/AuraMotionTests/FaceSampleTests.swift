import XCTest
import simd
@testable import AuraMotionCore

final class FaceSampleTests: XCTestCase {
    private func response(id: UInt64 = 42, time: Double = 12345.817, points: [[Float]], matrix: [[Float]]? = nil) -> FaceWorkerResponse {
        FaceWorkerResponse(frameID: id, hostTime: time, landmarks: points, headTransform: matrix)
    }

    func testFrameIdentityAndHostTimeAreRequired() throws {
        let value = response(points: [[0.2, 0.3, -0.1]])
        let sample = try XCTUnwrap(value.sample(expectedFrameID: 42, expectedHostTime: 12345.817, isEstimated: true))
        XCTAssertEqual(sample.timestamp, 12345.817)
        XCTAssertEqual(sample.frameID, 42)
        XCTAssertTrue(sample.isTimestampEstimated)
        XCTAssertEqual(sample.landmarks[0].z, -0.1)
        XCTAssertNil(sample.confidence)
        XCTAssertNil(sample.leftIrisCenter)
        XCTAssertThrowsError(try value.sample(expectedFrameID: 43, expectedHostTime: 12345.817, isEstimated: false))
        XCTAssertThrowsError(try value.sample(expectedFrameID: 42, expectedHostTime: 12345.818, isEstimated: false))
    }

    func testMatrixRowOrderAndPose() throws {
        let matrix: [[Float]] = [[0, -1, 0, 4], [1, 0, 0, 5], [0, 0, 1, 6], [0, 0, 0, 1]]
        let value = response(points: [[0.2, 0.3, 0], [0.8, 0.7, 0]], matrix: matrix)
        let sample = try XCTUnwrap(value.sample(expectedFrameID: 42, expectedHostTime: 12345.817, isEstimated: false))
        let transform = try XCTUnwrap(sample.headTransform)
        XCTAssertEqual(transform.columns.3, SIMD4<Float>(4, 5, 6, 1))
        let pose = try XCTUnwrap(sample.headPose)
        XCTAssertEqual(pose.roll, .pi / 2, accuracy: 0.0001)
        XCTAssertEqual(pose.yaw, 0, accuracy: 0.0001)
        XCTAssertEqual(pose.centerX, 0.5, accuracy: 0.0001)
        XCTAssertEqual(pose.scale, 0.6, accuracy: 0.0001)
    }

    func testIrisAndMissingOrMalformedResults() throws {
        var points = Array(repeating: [Float(0), 0, 0], count: 478)
        points[468] = [0.1, 0.2, 0.3]
        points[473] = [0.4, 0.5, 0.6]
        let value = response(points: points)
        let sample = try XCTUnwrap(value.sample(expectedFrameID: 42, expectedHostTime: 12345.817, isEstimated: false))
        XCTAssertEqual(sample.rightIrisCenter, SIMD3<Float>(0.1, 0.2, 0.3))
        XCTAssertEqual(sample.leftIrisCenter, SIMD3<Float>(0.4, 0.5, 0.6))
        XCTAssertNil(try response(points: []).sample(expectedFrameID: 42, expectedHostTime: 12345.817, isEstimated: false))
        XCTAssertThrowsError(try response(points: [[0, 1]]).sample(expectedFrameID: 42, expectedHostTime: 12345.817, isEstimated: false))
        XCTAssertThrowsError(try response(points: [[0, 1, 2]], matrix: [[1]]).sample(expectedFrameID: 42, expectedHostTime: 12345.817, isEstimated: false))
    }
}
