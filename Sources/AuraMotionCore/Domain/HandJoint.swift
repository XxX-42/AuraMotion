import Foundation
import CoreGraphics

/// Strongly typed identifiers for the 21 landmarks of a human hand.
public enum HandJointName: String, CaseIterable, Sendable, Codable, CodingKeyRepresentable {
    case wrist
    // Thumb
    case thumbCMC
    case thumbMP
    case thumbIP
    case thumbTip
    // Index
    case indexMCP
    case indexPIP
    case indexDIP
    case indexTip
    // Middle
    case middleMCP
    case middlePIP
    case middleDIP
    case middleTip
    // Ring
    case ringMCP
    case ringPIP
    case ringDIP
    case ringTip
    // Little (Pinky)
    case littleMCP
    case littlePIP
    case littleDIP
    case littleTip

    /// First ring is the palm/wrist subset of the full 21-point second ring.
    public var isFirstRing: Bool {
        switch self {
        case .wrist, .thumbCMC, .thumbMP, .indexMCP, .middleMCP, .ringMCP, .littleMCP:
            return true
        default:
            return false
        }
    }

    /// Stable display numbering: wrist, then thumb through little finger.
    public var landmarkNumber: Int {
        switch self {
        case .wrist: return 0
        case .thumbCMC: return 1
        case .thumbMP: return 2
        case .thumbIP: return 3
        case .thumbTip: return 4
        case .indexMCP: return 5
        case .indexPIP: return 6
        case .indexDIP: return 7
        case .indexTip: return 8
        case .middleMCP: return 9
        case .middlePIP: return 10
        case .middleDIP: return 11
        case .middleTip: return 12
        case .ringMCP: return 13
        case .ringPIP: return 14
        case .ringDIP: return 15
        case .ringTip: return 16
        case .littleMCP: return 17
        case .littlePIP: return 18
        case .littleDIP: return 19
        case .littleTip: return 20
        }
    }
}

/// The second ring contains every landmark; the first ring is its palm subset.
public enum HandLandmarkRings {
    public static let second = HandJointName.allCases
    public static let first = second.filter(\.isFirstRing)
}

/// A single detected 2D hand joint observation.
/// Note: Apple Vision provides 2D normalized points in [0, 1] relative to the image frame.
public struct HandJoint: Sendable, Codable, Equatable {
    public let name: HandJointName
    public let position: CGPoint
    public let confidence: Float

    public init(name: HandJointName, position: CGPoint, confidence: Float) {
        self.name = name
        self.position = position
        self.confidence = confidence
    }
}
