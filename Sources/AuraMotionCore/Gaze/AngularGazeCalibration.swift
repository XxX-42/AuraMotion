import Foundation
import CoreGraphics
import simd

/// Camera coordinates: x image-right, y down, z away from camera. The screen
/// is approximated as z=0, and camera x is opposite to display x.
public struct AngularGazeFrame {
    public let pitch: Double, yaw: Double
    public let eye: SIMD3<Double>
    /// Real-camera to normalized-eye rotation, row-major.
    public let rotation: [Double]
    public init(pitch: Double, yaw: Double, eye: SIMD3<Double>, rotation: [Double]) {
        self.pitch = pitch; self.yaw = yaw; self.eye = eye; self.rotation = rotation
    }
}
public struct DebugScreenGeometry {
    public let width: Double, height: Double, offsetX: Double, offsetY: Double
    public init(width: Double, height: Double, offsetX: Double, offsetY: Double) {
        self.width = width; self.height = height; self.offsetX = offsetX; self.offsetY = offsetY
    }
    var valid: Bool { [width,height,offsetX,offsetY].allSatisfy(\.isFinite) && width > 0 && height > 0 }
}
public struct AngularGazeCalibration {
    public struct Sample {
        public let frame: AngularGazeFrame
        /// Top-left normalized display coordinate.
        public let target: CGPoint
        public init(frame: AngularGazeFrame, target: CGPoint) { self.frame = frame; self.target = target }
    }
    public enum Error: Swift.Error { case invalidData, insufficientVariation }
    private let mean: SIMD2<Double>, scale: SIMD2<Double>
    private let pitchWeights: SIMD3<Double>, yawWeights: SIMD3<Double>
    public let geometry: DebugScreenGeometry
    private static func rotate(_ r: [Double], _ v: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(r[0]*v.x+r[1]*v.y+r[2]*v.z, r[3]*v.x+r[4]*v.y+r[5]*v.z, r[6]*v.x+r[7]*v.y+r[8]*v.z)
    }
    private static func valid(_ f: AngularGazeFrame) -> Bool {
        f.rotation.count == 9 && f.rotation.allSatisfy(\.isFinite) && f.pitch.isFinite && f.yaw.isFinite &&
        f.eye.x.isFinite && f.eye.y.isFinite && f.eye.z.isFinite && f.eye.z > 0
    }
    private static func targetAngles(_ s: Sample, _ g: DebugScreenGeometry) -> SIMD2<Double>? {
        let target = SIMD3(g.width/2 - g.offsetX - s.target.x*g.width, g.offsetY + s.target.y*g.height, 0)
        let v = rotate(s.frame.rotation, target - s.frame.eye)
        let length = simd_length(v)
        guard length > 1e-9 else { return nil }
        return SIMD2(asin(max(-1, min(1, -v.y/length))), atan2(-v.x, -v.z))
    }
    public static func fit(_ samples: [Sample], geometry: DebugScreenGeometry) throws -> Self {
        guard geometry.valid, samples.count >= 9, samples.allSatisfy({ valid($0.frame) && (0...1).contains($0.target.x) && (0...1).contains($0.target.y) }),
              GazeCalibration.nineTargets.allSatisfy({ t in samples.contains { hypot($0.target.x-t.x, $0.target.y-t.y) < 0.001 } }) else { throw Error.invalidData }
        // Each target is one independent constraint: many adjacent frames
        // from a slower target must not give that target extra influence.
        let groups = GazeCalibration.nineTargets.map { target in
            samples.filter { hypot($0.target.x-target.x, $0.target.y-target.y) < 0.001 }
        }
        guard groups.allSatisfy({ !$0.isEmpty }), groups.reduce(0, { $0 + $1.count }) == samples.count else { throw Error.invalidData }
        let n = Double(groups.count)
        let mean = SIMD2(groups.reduce(0) { $0 + $1.reduce(0) { $0 + $1.frame.pitch } / Double($1.count) } / n,
                         groups.reduce(0) { $0 + $1.reduce(0) { $0 + $1.frame.yaw } / Double($1.count) } / n)
        let deviation = SIMD2(sqrt(groups.reduce(0) { $0 + $1.reduce(0) { $0 + pow($1.frame.pitch-mean.x,2) } / Double($1.count) } / n),
                              sqrt(groups.reduce(0) { $0 + $1.reduce(0) { $0 + pow($1.frame.yaw-mean.y,2) } / Double($1.count) } / n))
        guard deviation.x > 0.002, deviation.y > 0.002 else { throw Error.insufficientVariation }
        let scale = SIMD2(max(deviation.x,0.01),max(deviation.y,0.01))
        var matrix = [[Double]](repeating: [Double](repeating: 0, count: 3), count: 3)
        var bp = [Double](repeating: 0, count: 3), by = bp
        for group in groups {
            let weight = 1.0 / Double(group.count)
            for sample in group {
                guard let target = targetAngles(sample, geometry) else { throw Error.invalidData }
                let row = [1.0, (sample.frame.pitch-mean.x)/scale.x, (sample.frame.yaw-mean.y)/scale.y]
                for i in 0..<3 {
                    bp[i] += weight * row[i] * target.x; by[i] += weight * row[i] * target.y
                    for j in 0..<3 { matrix[i][j] += weight * row[i] * row[j] }
                }
            }
        }
        matrix[1][1] += 0.05; matrix[2][2] += 0.05
        func solve(_ rhs: [Double]) -> SIMD3<Double>? {
            var m = zip(matrix,rhs).map { $0 + [$1] }
            for i in 0..<3 {
                guard let pivot = (i..<3).max(by: { abs(m[$0][i]) < abs(m[$1][i]) }), abs(m[pivot][i]) > 1e-10 else { return nil }
                m.swapAt(i,pivot); let divisor = m[i][i]
                for j in i...3 { m[i][j] /= divisor }
                for k in 0..<3 where k != i { let factor = m[k][i]; for j in i...3 { m[k][j] -= factor*m[i][j] } }
            }
            let a = SIMD3(m[0][3],m[1][3],m[2][3]); return a.x.isFinite && a.y.isFinite && a.z.isFinite ? a : nil
        }
        guard let pw = solve(bp), let yw = solve(by) else { throw Error.invalidData }
        return Self(mean: mean, scale: scale, pitchWeights: pw, yawWeights: yw, geometry: geometry)
    }
    /// Returns an unclamped top-left normalized intersection; nil for invalid rays.
    public func project(_ frame: AngularGazeFrame) -> CGPoint? {
        guard Self.valid(frame), geometry.valid else { return nil }
        let row = SIMD3(1, (frame.pitch-mean.x)/scale.x, (frame.yaw-mean.y)/scale.y)
        guard abs(row.y) <= 8, abs(row.z) <= 8 else { return nil }
        let pitch = simd_dot(row,pitchWeights), yaw = simd_dot(row,yawWeights)
        guard pitch.isFinite, yaw.isFinite, abs(pitch) < 1.4, abs(yaw) < 1.4 else { return nil }
        let virtual = SIMD3(-cos(pitch)*sin(yaw), -sin(pitch), -cos(pitch)*cos(yaw))
        let r = frame.rotation
        let d = SIMD3(r[0]*virtual.x+r[3]*virtual.y+r[6]*virtual.z,
                      r[1]*virtual.x+r[4]*virtual.y+r[7]*virtual.z,
                      r[2]*virtual.x+r[5]*virtual.y+r[8]*virtual.z)
        guard d.z < -1e-6 else { return nil }
        let t = -frame.eye.z/d.z
        guard t > 0 else { return nil }
        let hit = frame.eye + t*d
        let x = (geometry.width/2-geometry.offsetX-hit.x)/geometry.width
        let y = (hit.y-geometry.offsetY)/geometry.height
        guard x.isFinite, y.isFinite else { return nil }
        return CGPoint(x:x,y:y)
    }
}
