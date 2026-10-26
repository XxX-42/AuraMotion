import Foundation
import CoreGraphics
import simd

/// Image-space iris ratios and MediaPipe head pose. Values are features, not a gaze vector.
public struct EyeFeatures: Sendable, Equatable {
    public let irisLX: Double, irisLY: Double, irisRX: Double, irisRY: Double
    public let yaw: Double, pitch: Double, roll: Double, faceScale: Double
    public var vector: [Double] { [irisLX, irisLY, irisRX, irisRY, yaw, pitch, roll, faceScale] }
    public init(_ values: [Double]) {
        precondition(values.count == 8)
        irisLX = values[0]; irisLY = values[1]; irisRX = values[2]; irisRY = values[3]
        yaw = values[4]; pitch = values[5]; roll = values[6]; faceScale = values[7]
    }
}

public enum EyeFeatureExtractor {
    /// Reject a closed/degenerate eye rather than presenting a false gaze.
    public static func extract(_ face: FaceSample) -> EyeFeatures? {
        guard face.landmarks.count > 477, let pose = face.headPose,
              let left = face.leftIrisCenter, let right = face.rightIrisCenter,
              pose.scale > 0.03 else { return nil }
        func ratio(_ iris: SIMD3<Float>, _ a: Int, _ b: Int, _ top: Int, _ bottom: Int) -> (Double, Double)? {
            let p = face.landmarks
            let x0 = min(p[a].x, p[b].x), x1 = max(p[a].x, p[b].x)
            let y0 = min(p[top].y, p[bottom].y), y1 = max(p[top].y, p[bottom].y)
            let w = x1 - x0, h = y1 - y0
            guard w > 0.005, h > 0.003, h / w > 0.08 else { return nil }
            let x = (iris.x - x0) / w, y = (iris.y - y0) / h
            guard x.isFinite, y.isFinite, x >= -0.5, x <= 1.5, y >= -0.5, y <= 1.5 else { return nil }
            return (Double(x), Double(y))
        }
        guard let l = ratio(left, 362, 263, 386, 374), let r = ratio(right, 33, 133, 159, 145) else { return nil }
        let values = [l.0, l.1, r.0, r.1, Double(pose.yaw), Double(pose.pitch), Double(pose.roll), Double(pose.scale)]
        guard values.allSatisfy(\.isFinite) else { return nil }
        return EyeFeatures(values)
    }
}

public struct GazeCalibrationPoint: Sendable {
    public let features: EyeFeatures
    /// Display-local normalized coordinates, top-left origin.
    public let target: CGPoint
    public init(features: EyeFeatures, target: CGPoint) { self.features = features; self.target = target }
}

/// Regularized linear regression in normalized screen space. Head features are
/// learned from calibration samples, so compensation is only as good as data.
public struct GazeCalibration: Sendable {
    public let featureMean: [Double]
    public let featureScale: [Double]
    public let xWeights: [Double]
    public let yWeights: [Double]
    /// Iris-only weights use the same 9-column basis; columns 5...8 are zero.
    public let irisXWeights: [Double]
    public let irisYWeights: [Double]

    public static let nineTargets: [CGPoint] = [0.12, 0.5, 0.88].flatMap { y in [0.12, 0.5, 0.88].map { x in CGPoint(x: x, y: y) } }
    public enum Error: Swift.Error { case insufficientPoints, invalidData, insufficientVariation }

    public static func fit(_ samples: [GazeCalibrationPoint]) throws -> GazeCalibration {
        guard samples.count >= 9 else { throw Error.insufficientPoints }
        guard samples.allSatisfy({ $0.features.vector.allSatisfy(\.isFinite) && $0.target.x.isFinite && $0.target.y.isFinite && (0...1).contains($0.target.x) && (0...1).contains($0.target.y) }) else { throw Error.invalidData }
        // Require all nine grid targets; repeated observations of one point do not count.
        guard nineTargets.allSatisfy({ target in samples.contains { hypot($0.target.x - target.x, $0.target.y - target.y) < 0.001 } }) else { throw Error.insufficientPoints }
        let n = Double(samples.count)
        let means = (0..<8).map { j in samples.reduce(0.0) { $0 + $1.features.vector[j] } / n }
        let deviations = (0..<8).map { j in sqrt(samples.reduce(0.0) { $0 + pow($1.features.vector[j] - means[j], 2) } / n) }
        guard deviations.prefix(4).max() ?? 0 > 0.005 else { throw Error.insufficientVariation }
        let scales = deviations.map { max($0, 0.02) }
        let rows = samples.map { sample in [1.0] + zip(zip(sample.features.vector, means), scales).map { ($0.0.0 - $0.0.1) / $0.1 } }
        var matrix = Array(repeating: Array(repeating: 0.0, count: 9), count: 9)
        var bx = Array(repeating: 0.0, count: 9), by = bx
        for (i, row) in rows.enumerated() {
            for j in 0..<9 {
                bx[j] += row[j] * samples[i].target.x; by[j] += row[j] * samples[i].target.y
                for k in 0..<9 { matrix[j][k] += row[j] * row[k] }
            }
        }
        for j in 1..<9 { matrix[j][j] += 0.5 }
        guard let x = solve(matrix, bx), let y = solve(matrix, by) else { throw Error.invalidData }
        let squaredError = rows.enumerated().reduce(0.0) { total, item in
            let (index, row) = item
            let px = zip(row, x).reduce(0.0) { $0 + $1.0 * $1.1 }
            let py = zip(row, y).reduce(0.0) { $0 + $1.0 * $1.1 }
            return total + pow(px - samples[index].target.x, 2) + pow(py - samples[index].target.y, 2)
        }
        guard sqrt(squaredError / n) < 0.22 else { throw Error.insufficientVariation }
        // Fit the same basis and solver, zeroing head and face-scale columns.
        var irisMatrix = Array(repeating: Array(repeating: 0.0, count: 9), count: 9)
        var irisBX = Array(repeating: 0.0, count: 9), irisBY = irisBX
        for (i, original) in rows.enumerated() {
            let row = Array(original.prefix(5)) + [0.0, 0.0, 0.0, 0.0]
            for j in 0..<9 {
                irisBX[j] += row[j] * samples[i].target.x; irisBY[j] += row[j] * samples[i].target.y
                for k in 0..<9 { irisMatrix[j][k] += row[j] * row[k] }
            }
        }
        for j in 1..<9 { irisMatrix[j][j] += 0.5 }
        guard let irisX = solve(irisMatrix, irisBX), let irisY = solve(irisMatrix, irisBY) else { throw Error.invalidData }
        return GazeCalibration(featureMean: means, featureScale: scales, xWeights: x, yWeights: y,
                               irisXWeights: irisX, irisYWeights: irisY)
    }

    private static func solve(_ a: [[Double]], _ b: [Double]) -> [Double]? {
        var m = zip(a, b).map { $0 + [$1] }
        for i in 0..<9 {
            guard let pivot = (i..<9).max(by: { abs(m[$0][i]) < abs(m[$1][i]) }), abs(m[pivot][i]) > 1e-10 else { return nil }
            m.swapAt(i, pivot)
            let divisor = m[i][i]
            for k in i...9 { m[i][k] /= divisor }
            for j in 0..<9 where j != i {
                let factor = m[j][i]
                for k in i...9 { m[j][k] -= factor * m[i][k] }
            }
        }
        let solution = m.map { $0[9] }
        return solution.allSatisfy(\.isFinite) ? solution : nil
    }
}

public struct GazeEstimate: Sendable {
    /// Quartz global screen coordinates, in points, top-left origin.
    public let screenPoint: CGPoint
    /// Monotonic host time of the camera frame, not inference completion.
    public let timestamp: TimeInterval
    public let direction: SIMD3<Float>?
    /// Heuristic input quality, not a calibrated probability.
    public let confidence: Float
}

public enum GazeEstimatorMode: Sendable, Equatable {
    case legacyFullFeature
    case irisDominant
}

public enum IrisDominantGazeConfiguration {
    /// MVP tuning values; correction is bounded per screen-normalized axis.
    public static let headCompensationWeight = 0.15
    public static let maxNormalizedHeadCorrection = 0.05
}

public enum GazeEstimator {
    /// Normalized diagnostic components. A nil correction means the legacy
    /// full-feature model is active, not that head contribution is zero.
    public static func normalizedComponents(features: EyeFeatures, calibration: GazeCalibration,
                                            mode: GazeEstimatorMode) -> (irisBase: CGPoint, headCorrection: CGPoint?, final: CGPoint)? {
        let values = [1.0] + zip(zip(features.vector, calibration.featureMean), calibration.featureScale).map { ($0.0.0 - $0.0.1) / $0.1 }
        guard values.count == 9, values.allSatisfy(\.isFinite),
              calibration.xWeights.count == 9, calibration.yWeights.count == 9,
              calibration.irisXWeights.count == 9, calibration.irisYWeights.count == 9 else { return nil }
        let irisX = zip(values.prefix(5), calibration.irisXWeights.prefix(5)).reduce(0.0) { $0 + $1.0 * $1.1 }
        let irisY = zip(values.prefix(5), calibration.irisYWeights.prefix(5)).reduce(0.0) { $0 + $1.0 * $1.1 }
        let base = CGPoint(x: irisX, y: irisY)
        switch mode {
        case .legacyFullFeature:
            // Preserve the original full-feature outlier gate and calculation.
            guard values.dropFirst().allSatisfy({ abs($0) <= 5 }) else { return nil }
            let nx = zip(values, calibration.xWeights).reduce(0.0) { $0 + $1.0 * $1.1 }
            let ny = zip(values, calibration.yWeights).reduce(0.0) { $0 + $1.0 * $1.1 }
            guard nx.isFinite, ny.isFinite else { return nil }
            return (base, nil, CGPoint(x: nx, y: ny))
        case .irisDominant:
            // Head/scale outliers must not suppress eye-only tracking. The face
            // extractor still validates landmarks; only iris terms use this gate.
            guard values[1...4].allSatisfy({ abs($0) <= 5 }), irisX.isFinite, irisY.isFinite else { return nil }
            let hx = (5...7).reduce(0.0) { $0 + values[$1] * calibration.xWeights[$1] }
            let hy = (5...7).reduce(0.0) { $0 + values[$1] * calibration.yWeights[$1] }
            let limit = IrisDominantGazeConfiguration.maxNormalizedHeadCorrection
            let weight = IrisDominantGazeConfiguration.headCompensationWeight
            let dx = max(-limit, min(limit, weight * hx))
            let dy = max(-limit, min(limit, weight * hy))
            guard dx.isFinite, dy.isFinite else { return nil }
            return (base, CGPoint(x: dx, y: dy), CGPoint(x: irisX + dx, y: irisY + dy))
        }
    }

    public static func estimate(face: FaceSample, calibration: GazeCalibration, displayBounds: CGRect,
                                mode: GazeEstimatorMode = .legacyFullFeature) -> GazeEstimate? {
        guard let features = EyeFeatureExtractor.extract(face), displayBounds.width > 0, displayBounds.height > 0,
              let components = normalizedComponents(features: features, calibration: calibration, mode: mode) else { return nil }
        let nx = components.final.x, ny = components.final.y
        guard nx.isFinite, ny.isFinite, (-0.25...1.25).contains(nx), (-0.25...1.25).contains(ny) else { return nil }
        return GazeEstimate(screenPoint: CGPoint(x: displayBounds.minX + nx * displayBounds.width, y: displayBounds.minY + ny * displayBounds.height), timestamp: face.timestamp, direction: nil,
                            confidence: Float(0.5 + 0.3 * min(1, max(0, features.faceScale / 0.3))))
    }
}
