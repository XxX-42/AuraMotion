import Foundation
import CoreGraphics
import QuartzCore

public enum HeadReferenceProjector {
    /// MVP/debug approximation only. This is not a calibrated camera-to-display projection.
    /// MediaPipe coordinates are video-data image coordinates (x right, y down).
    /// Undo source mirroring before the linear map to Quartz screen coordinates.
    public static func debugApproximation(pose: HeadPose, isMirrored: Bool, displayBounds: CGRect) -> CGPoint? {
        let x = CGFloat(pose.centerX), y = CGFloat(pose.centerY)
        guard x.isFinite, y.isFinite, (0...1).contains(x), (0...1).contains(y),
              displayBounds.minX.isFinite, displayBounds.minY.isFinite,
              displayBounds.width.isFinite, displayBounds.height.isFinite,
              displayBounds.width > 0, displayBounds.height > 0 else { return nil }
        return CGPoint(x: displayBounds.minX + (isMirrored ? 1 - x : x) * displayBounds.width,
                       y: displayBounds.minY + y * displayBounds.height)
    }
}

public struct HeadCenteredRegionResolver: Sendable {
    public let configuration: HeadCenteredRegionConfiguration
    public init(configuration: HeadCenteredRegionConfiguration = .init()) { self.configuration = configuration }
    public func resolve(face: FaceSample, gaze: GazeEstimate, displayBounds: CGRect, now: TimeInterval) -> FocusedRegion? {
        guard let pose = face.headPose, face.timestamp.isFinite, gaze.timestamp.isFinite, now.isFinite,
              abs(face.timestamp - gaze.timestamp) <= configuration.maximumFaceGazeDelta,
              now >= gaze.timestamp, now - gaze.timestamp <= configuration.maximumGazeAge,
              now >= face.timestamp, now - face.timestamp <= configuration.maximumGazeAge,
              gaze.confidence.isFinite, gaze.confidence >= 0.5,
              gaze.screenPoint.x.isFinite, gaze.screenPoint.y.isFinite,
              configuration.centerRadius >= 0, configuration.ring1OuterRadius > configuration.centerRadius,
              configuration.ring2OuterRadius > configuration.ring1OuterRadius,
              let head = HeadReferenceProjector.debugApproximation(pose: pose, isMirrored: face.isMirrored, displayBounds: displayBounds) else { return nil }
        let dx = gaze.screenPoint.x - head.x, dy = gaze.screenPoint.y - head.y
        let normalized = hypot(dx, dy) / min(displayBounds.width, displayBounds.height)
        let radial: RadialRegion = normalized <= configuration.centerRadius ? .center : normalized <= configuration.ring1OuterRadius ? .ring1 : normalized <= configuration.ring2OuterRadius ? .ring2 : .outside
        let sector: AngularSector?
        if radial == .ring1 || radial == .ring2 {
            // Quartz y grows down: atan2(dy, dx) advances clockwise from east.
            let sectors: [AngularSector] = [.east, .southEast, .south, .southWest, .west, .northWest, .north, .northEast]
            let index = (Int((atan2(dy, dx) / (.pi / 4)).rounded()) + 8) % 8
            sector = sectors[index]
        } else { sector = nil }
        return FocusedRegion(radial: radial, sector: sector, timestamp: gaze.timestamp,
                             headCenter: head, gazePoint: gaze.screenPoint, confidence: gaze.confidence)
    }
}

public struct SpatialDiagnostics: Sendable {
    public var totalFrames = 0
    public var gazeAvailableFrames = 0
    public var switchCount = 0
    public var ageP50Ms: Double?
    public var ageP95Ms: Double?
    public var resolveLatencyMs: Double?
    public var gazeAvailablePercent: Double { totalFrames == 0 ? 0 : 100 * Double(gazeAvailableFrames) / Double(totalFrames) }
}

/// Consumes the existing fixation state; this type does not implement a second dwell detector.
public struct HeadCenteredTargeting: Sendable {
    public private(set) var focused: FocusedRegion?
    public private(set) var candidate: FocusedRegion?
    public private(set) var diagnostics = SpatialDiagnostics()
    private var ages: [Double] = []
    private let resolver: HeadCenteredRegionResolver
    public init(configuration: HeadCenteredRegionConfiguration = .init()) { resolver = .init(configuration: configuration) }
    public mutating func clear() { focused = nil; candidate = nil }
    public mutating func expire(now: TimeInterval) {
        if let focused, now - focused.timestamp > resolver.configuration.focusedRetention || now < focused.timestamp { self.focused = nil }
        if let candidate, now - candidate.timestamp > resolver.configuration.focusedRetention || now < candidate.timestamp { self.candidate = nil }
        if focused == nil && candidate == nil { diagnostics.resolveLatencyMs = nil }
    }
    public mutating func update(face: FaceSample?, gaze: GazeEstimate?, fixation: FixationState, displayBounds: CGRect, now: TimeInterval) {
        diagnostics.totalFrames += 1
        expire(now: now)
        diagnostics.resolveLatencyMs = nil
        guard let face, let gaze else { candidate = nil; return }
        if gaze.timestamp.isFinite, now >= gaze.timestamp,
           now - gaze.timestamp <= resolver.configuration.maximumGazeAge,
           abs(face.timestamp - gaze.timestamp) <= resolver.configuration.maximumFaceGazeDelta {
            diagnostics.gazeAvailableFrames += 1
            ages.append((now - gaze.timestamp) * 1000)
            if ages.count > 300 { ages.removeFirst() }
            let sorted = ages.sorted()
            diagnostics.ageP50Ms = sorted[Int(Double(sorted.count - 1) * 0.50)]
            diagnostics.ageP95Ms = sorted[Int(Double(sorted.count - 1) * 0.95)]
        }
        let start = CACurrentMediaTime()
        let fixationPoint: CGPoint
        let commit: Bool
        switch fixation {
        case .unavailable: candidate = nil; return
        case .candidate(let point): fixationPoint = point; commit = false
        case .focused(let point): fixationPoint = point; commit = true
        }
        let fixedGaze = GazeEstimate(screenPoint: fixationPoint, timestamp: gaze.timestamp, direction: gaze.direction, confidence: gaze.confidence)
        let result = resolver.resolve(face: face, gaze: fixedGaze, displayBounds: displayBounds, now: now)
        diagnostics.resolveLatencyMs = (CACurrentMediaTime() - start) * 1000
        guard let result else { candidate = nil; return }
        if commit {
            candidate = nil
            if result.radial == .outside { focused = nil; return }
            if focused?.radial != result.radial || focused?.sector != result.sector { diagnostics.switchCount += 1 }
            focused = result
        } else { candidate = result.radial == .outside ? nil : result }
    }
}
