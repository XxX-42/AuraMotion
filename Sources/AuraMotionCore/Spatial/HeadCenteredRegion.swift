import Foundation
import CoreGraphics

public enum RadialRegion: Sendable, Equatable { case center, ring1, ring2, outside }
public enum AngularSector: String, Sendable, Equatable, CaseIterable {
    case north, northEast, east, southEast, south, southWest, west, northWest
}
public struct FocusedRegion: Sendable, Equatable {
    public let radial: RadialRegion
    public let sector: AngularSector?
    public let timestamp: TimeInterval
    /// Quartz global screen coordinates, with y increasing downwards.
    public let headCenter: CGPoint
    public let gazePoint: CGPoint
    public let confidence: Float
}
public struct HeadCenteredRegionConfiguration: Sendable {
    public var centerRadius: CGFloat = 0.08
    public var ring1OuterRadius: CGFloat = 0.20
    public var ring2OuterRadius: CGFloat = 0.38
    public var maximumFaceGazeDelta: TimeInterval = 0.08
    public var maximumGazeAge: TimeInterval = 0.30
    public var focusedRetention: TimeInterval = 0.30
    public init() {}
}
