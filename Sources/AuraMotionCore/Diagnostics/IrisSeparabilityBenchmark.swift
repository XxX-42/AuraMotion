import Foundation

/// One paired result; both resolutions refer to the same original camera frame.
public struct IrisBenchmarkFrame: Sendable {
    public let frameID: UInt64
    public let timestamp: TimeInterval
    public let small: FaceSample?
    public let large: FaceSample?
    public let ms320: Double
    public let ms640: Double
    public let width: Int
    public let height: Int
    public init(frameID: UInt64, timestamp: TimeInterval, small: FaceSample?, large: FaceSample?, ms320: Double, ms640: Double, width: Int, height: Int) {
        self.frameID = frameID; self.timestamp = timestamp; self.small = small; self.large = large
        self.ms320 = ms320; self.ms640 = ms640; self.width = width; self.height = height
    }
}

public struct IrisBenchmarkObservation: Codable, Sendable {
    public let target: Int
    public let frameID: UInt64
    public let timestamp: TimeInterval
    /// 4D: left x/y, right x/y in the source image coordinate system.
    public let raw320: [Double]?
    public let raw640: [Double]?
    /// 4D: per-eye normalized x/y, using the existing feature extractor.
    public let normalized320: [Double]?
    public let normalized640: [Double]?
    /// z is recorded separately; the comparability metrics use x/y only.
    public let irisZ320: [Double]?
    public let irisZ640: [Double]?
    /// yaw, pitch, roll (radians), and normalized face scale for audit.
    public let head320: [Double]?
    public let head640: [Double]?
    public let isMirrored: Bool?
    public let isTimestampEstimated: Bool?
    public let ms320: Double
    public let ms640: Double
    public let width: Int
    public let height: Int
}

public struct IrisSeparabilityMetrics: Codable, Sendable {
    public let withinTargetRMS: Double
    public let minimumCentroidDistance: Double
    public let separationRatio: Double?
    /// Time-ordered first-half/second-half centroid cross-validation; one trial per target.
    public let heldOutAccuracy: Double
}

public struct IrisBenchmarkReport: Codable, Sendable {
    public let observations: [IrisBenchmarkObservation]
    /// Ordered target coordinates, normalized to the display with y down.
    public let targets: [[Double]]
    public let validPairs: Int
    public let attemptedPairs: Int
    public let meanInferenceMs320: Double
    public let meanInferenceMs640: Double
    /// Effective paired processing rate within targets, including both inferences and transport.
    public let pairedFPS: Double?
    /// Peak-to-peak yaw/pitch/roll, in degrees, across valid paired frames.
    public let headPoseSpanDegrees: [Double]?
    public let raw320: IrisSeparabilityMetrics
    public let raw640: IrisSeparabilityMetrics
    public let normalized320: IrisSeparabilityMetrics
    public let normalized640: IrisSeparabilityMetrics
}

public struct IrisSeparabilityBenchmark: Sendable {
    public private(set) var observations: [IrisBenchmarkObservation] = []
    public init() {}
    public mutating func append(_ frame: IrisBenchmarkFrame, target: Int) {
        guard (0..<9).contains(target), frame.timestamp.isFinite,
              frame.ms320.isFinite, frame.ms640.isFinite, frame.ms320 >= 0, frame.ms640 >= 0,
              frame.width > 0, frame.height > 0 else { return }
        guard !observations.contains(where: { $0.frameID == frame.frameID }) else { return }
        func raw(_ face: FaceSample?) -> [Double]? {
            guard let face, let l = face.leftIrisCenter, let r = face.rightIrisCenter else { return nil }
            let values = [Double(l.x), Double(l.y), Double(r.x), Double(r.y)]
            return values.allSatisfy(\.isFinite) ? values : nil
        }
        func norm(_ face: FaceSample?) -> [Double]? {
            guard let face, let f = EyeFeatureExtractor.extract(face) else { return nil }
            return [f.irisLX, f.irisLY, f.irisRX, f.irisRY]
        }
        func z(_ face: FaceSample?) -> [Double]? {
            guard let l = face?.leftIrisCenter, let r = face?.rightIrisCenter else { return nil }
            let values = [Double(l.z), Double(r.z)]
            return values.allSatisfy(\.isFinite) ? values : nil
        }
        func head(_ face: FaceSample?) -> [Double]? {
            guard let h = face?.headPose else { return nil }
            let values = [Double(h.yaw), Double(h.pitch), Double(h.roll), Double(h.scale)]
            return values.allSatisfy(\.isFinite) ? values : nil
        }
        // Never compare results from distinct camera frames or host timestamps.
        let small = frame.small.flatMap { $0.frameID == frame.frameID && $0.timestamp == frame.timestamp ? $0 : nil }
        let large = frame.large.flatMap { $0.frameID == frame.frameID && $0.timestamp == frame.timestamp ? $0 : nil }
        observations.append(IrisBenchmarkObservation(target: target, frameID: frame.frameID, timestamp: frame.timestamp,
            raw320: raw(small), raw640: raw(large), normalized320: norm(small), normalized640: norm(large),
            irisZ320: z(small), irisZ640: z(large), head320: head(small), head640: head(large),
            isMirrored: small?.isMirrored, isTimestampEstimated: small?.isTimestampEstimated,
            ms320: frame.ms320, ms640: frame.ms640, width: frame.width, height: frame.height))
    }
    public func validCount(target: Int) -> Int {
        observations.filter { $0.target == target && $0.normalized320 != nil && $0.normalized640 != nil && $0.raw320 != nil && $0.raw640 != nil }.count
    }
    public enum Error: Swift.Error { case insufficientSamples, sourceTooSmall }
    public func report() throws -> IrisBenchmarkReport {
        guard observations.allSatisfy({ max($0.width, $0.height) >= 640 }) else { throw Error.sourceTooSmall }
        let paired = observations.filter { $0.raw320 != nil && $0.raw640 != nil && $0.normalized320 != nil && $0.normalized640 != nil }
        guard (0..<9).allSatisfy({ target in paired.filter { $0.target == target }.count >= 6 }) else { throw Error.insufficientSamples }
        let groups = (0..<9).map { target in paired.filter { $0.target == target }.sorted { $0.timestamp < $1.timestamp } }
        let durations = groups.reduce((frames: 0, seconds: 0.0)) { total, group in
            guard let first = group.first, let last = group.last, last.timestamp > first.timestamp else { return total }
            return (total.frames + group.count - 1, total.seconds + last.timestamp - first.timestamp)
        }
        return IrisBenchmarkReport(observations: observations,
            targets: GazeCalibration.nineTargets.map { [Double($0.x), Double($0.y)] }, validPairs: paired.count, attemptedPairs: observations.count,
            meanInferenceMs320: observations.map(\.ms320).reduce(0,+) / Double(observations.count),
            meanInferenceMs640: observations.map(\.ms640).reduce(0,+) / Double(observations.count),
            pairedFPS: durations.seconds > 0 ? Double(durations.frames) / durations.seconds : nil,
            headPoseSpanDegrees: poseSpan(paired),
            raw320: metrics(groups.map { $0.map { $0.raw320! } }), raw640: metrics(groups.map { $0.map { $0.raw640! } }),
            normalized320: metrics(groups.map { $0.map { $0.normalized320! } }), normalized640: metrics(groups.map { $0.map { $0.normalized640! } }))
    }
    private func poseSpan(_ observations: [IrisBenchmarkObservation]) -> [Double]? {
        let poses = observations.compactMap(\.head320)
        guard !poses.isEmpty else { return nil }
        return (0..<3).map { i in
            let values = poses.map { $0[i] }
            return ((values.max() ?? 0) - (values.min() ?? 0)) * 180 / .pi
        }
    }
    private func metrics(_ groups: [[[Double]]]) -> IrisSeparabilityMetrics {
        func mean(_ group: [[Double]]) -> [Double] { (0..<4).map { j in group.reduce(0) { $0 + $1[j] } / Double(group.count) } }
        func dist2(_ a: [Double], _ b: [Double]) -> Double { zip(a,b).reduce(0) { $0 + pow($1.0 - $1.1, 2) } }
        let centers = groups.map(mean)
        let within = sqrt(groups.enumerated().reduce(0.0) { sum, entry in
            sum + entry.element.reduce(0.0) { $0 + dist2($1, centers[entry.offset]) }
        } / Double(groups.reduce(0) { $0 + $1.count }))
        let minimum = (0..<9).flatMap { i in ((i+1)..<9).map { sqrt(dist2(centers[i], centers[$0])) } }.min() ?? 0
        var correct = 0, total = 0
        for fold in 0..<2 {
            let split = groups.map { group -> (train: [[Double]], test: [[Double]]) in
                let middle = group.count / 2
                return fold == 0 ? (Array(group[..<middle]), Array(group[middle...])) : (Array(group[middle...]), Array(group[..<middle]))
            }
            let trained = split.map { mean($0.train) }
            for i in 0..<9 { for point in split[i].test {
                let best = (0..<9).min { dist2(point, trained[$0]) < dist2(point, trained[$1]) }!
                if best == i { correct += 1 }; total += 1
            } }
        }
        return IrisSeparabilityMetrics(withinTargetRMS: within, minimumCentroidDistance: minimum,
            separationRatio: within > 1e-12 ? minimum / within : nil, heldOutAccuracy: Double(correct) / Double(total))
    }
}
