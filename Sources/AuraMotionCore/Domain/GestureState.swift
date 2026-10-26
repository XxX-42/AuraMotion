import Foundation

/// Explicit states of the hierarchical gesture state machine.
public enum GestureState: String, Sendable, Codable, Equatable {
    case idle
    case clutch
    case pointer
    case pinchArmed
    case dragging
    case scrollCandidate
    case scrolling
    case paused
    case trackingLost
    case palmCandidate
    case palmRest
    case palmSwipeLeft
    case palmSwipeRight

    public var displayName: String {
        switch self {
        case .idle: return L10n.tr("IDLE")
        case .clutch: return L10n.tr("READY (HOLD TO ENGAGE)")
        case .pointer: return L10n.tr("TRACKING")
        case .pinchArmed: return L10n.tr("PINCH ARMED")
        case .dragging: return L10n.tr("DRAGGING")
        case .scrollCandidate: return L10n.tr("SCROLL PENDING")
        case .scrolling: return L10n.tr("SCROLLING")
        case .paused: return L10n.tr("PAUSED")
        case .trackingLost: return L10n.tr("TRACKING LOST - INPUT RELEASED")
        case .palmCandidate: return L10n.tr("PALM DETECTED")
        case .palmRest: return L10n.tr("PALM REST")
        case .palmSwipeLeft: return L10n.tr("SWIPE LEFT ◀")
        case .palmSwipeRight: return L10n.tr("SWIPE RIGHT ▶")
        }
    }

    public var isInputActive: Bool {
        switch self {
        case .pointer, .pinchArmed, .dragging, .scrollCandidate, .scrolling:
            return true
        default:
            return false
        }
    }
}
