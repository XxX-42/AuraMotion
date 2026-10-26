import Foundation
import simd

/// MediaPipe normalized image coordinates: x right, y down, z relative to the
/// face with approximately the same scale as x. Coordinates are not screen points.
public struct FaceLandmark: Sendable, Equatable {
    public let x: Float
    public let y: Float
    public let z: Float
    public var position: SIMD3<Float> { SIMD3(x, y, z) }
}

/// Euler angles in radians, R = Rz(roll) * Ry(yaw) * Rx(pitch), in the
/// MediaPipe transform coordinate frame of the input image. Center and scale are in
/// normalized image coordinates, not physical units.
public struct HeadPose: Sendable, Equatable {
    public let yaw: Float
    public let pitch: Float
    public let roll: Float
    public let centerX: Float
    public let centerY: Float
    public let scale: Float
}

/// A face result tied to the same host clock and capture frame as HandSample.
public struct FaceSample: Sendable {
    public let frameID: UInt64
    public let timestamp: TimeInterval
    public let isTimestampEstimated: Bool
    /// Whether the source video-data connection was mirrored for this frame.
    public let isMirrored: Bool
    public let landmarks: [FaceLandmark]
    /// MediaPipe's canonical-to-detected transform, converted from row-major
    /// JSON to SIMD columns. This is not a calibrated camera extrinsic matrix.
    public let headTransform: simd_float4x4?
    public let headPose: HeadPose?
    /// Subject-relative iris centers in MediaPipe's image coordinate system.
    public let leftIrisCenter: SIMD3<Float>?
    public let rightIrisCenter: SIMD3<Float>?
    /// The Face Landmarker API does not expose an overall detection confidence.
    public let confidence: Float?
}

/// Decodes and validates a single worker response before it can enter the app.
struct FaceWorkerResponse: Decodable {
    let frameID: UInt64
    let hostTime: Double
    let landmarks: [[Float]]
    let headTransform: [[Float]]?

    enum ValidationError: Error { case invalidFrame, invalidLandmarks, invalidTransform }

    func sample(expectedFrameID: UInt64, expectedHostTime: Double, isEstimated: Bool, isMirrored: Bool = false) throws -> FaceSample? {
        guard frameID == expectedFrameID, hostTime.isFinite, hostTime == expectedHostTime else { throw ValidationError.invalidFrame }
        guard landmarks.allSatisfy({ $0.count == 3 && $0.allSatisfy(\.isFinite) }) else { throw ValidationError.invalidLandmarks }
        let matrix: simd_float4x4?
        if let rows = headTransform {
            guard rows.count == 4, rows.allSatisfy({ $0.count == 4 && $0.allSatisfy(\.isFinite) }) else { throw ValidationError.invalidTransform }
            matrix = simd_float4x4(columns: (
                SIMD4(rows[0][0], rows[1][0], rows[2][0], rows[3][0]),
                SIMD4(rows[0][1], rows[1][1], rows[2][1], rows[3][1]),
                SIMD4(rows[0][2], rows[1][2], rows[2][2], rows[3][2]),
                SIMD4(rows[0][3], rows[1][3], rows[2][3], rows[3][3])
            ))
        } else { matrix = nil }
        guard !landmarks.isEmpty else { return nil }
        let points = landmarks.map { FaceLandmark(x: $0[0], y: $0[1], z: $0[2]) }
        let xs = points.map(\.x), ys = points.map(\.y)
        let minX = xs.min()!, maxX = xs.max()!, minY = ys.min()!, maxY = ys.max()!
        var pose: HeadPose?
        if let m = matrix {
            let a = SIMD3(m.columns.0.x, m.columns.0.y, m.columns.0.z)
            let b = SIMD3(m.columns.1.x, m.columns.1.y, m.columns.1.z)
            let c = SIMD3(m.columns.2.x, m.columns.2.y, m.columns.2.z)
            if simd_length(a) > 1e-6 && simd_length(b) > 1e-6 && simd_length(c) > 1e-6 {
                let r0 = simd_normalize(a), r1 = simd_normalize(b), r2 = simd_normalize(c)
                let yaw = asin(max(-1, min(1, -r0.z)))
                let pitch = atan2(r1.z, r2.z)
                let roll = atan2(r0.y, r0.x)
                pose = HeadPose(yaw: yaw, pitch: pitch, roll: roll, centerX: (minX + maxX) / 2,
                                centerY: (minY + maxY) / 2, scale: max(maxX - minX, maxY - minY))
            }
        }
        return FaceSample(frameID: frameID, timestamp: hostTime, isTimestampEstimated: isEstimated, isMirrored: isMirrored,
                          landmarks: points, headTransform: matrix, headPose: pose,
                          leftIrisCenter: points.count > 473 ? points[473].position : nil,
                          rightIrisCenter: points.count > 468 ? points[468].position : nil, confidence: nil)
    }
}
