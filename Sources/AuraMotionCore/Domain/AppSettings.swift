import Foundation

public enum SwipeActionType: String, Sendable, Codable, CaseIterable {
    case switchSpace = "switchSpace"
    case switchWindow = "switchWindow"
    case switchApp = "switchApp"

    public var displayName: String {
        switch self {
        case .switchSpace: return "Desktops / full-screen apps (Control + Arrow)"
        case .switchWindow: return "Windows of the current app (Command + `)"
        case .switchApp: return "Different apps (Command + Tab)"
        }
    }
}

/// User preferences with safety defaults.
public struct AppSettings: Sendable, Codable, Equatable {
    public var isCameraMirrored: Bool
    public var isClutchEnabled: Bool
    public var clutchDwellTime: TimeInterval
    public var preferredHandedness: EstimatedHandedness
    public var showHUD: Bool
    public var hudShowsCamera: Bool
    public var hudPreviewMirrored: Bool
    public var hudShowsJointNumbers: Bool
    public var hudHighlightFirstRing: Bool
    public var hudSkeletonScale: Double
    public var isGestureClickAndMenuEnabled: Bool
    public var showClickFeedback: Bool
    public var hudSkeletonFPS: Int
    public var scrollInertiaEnabled: Bool
    public var arbitrationCooldownSeconds: TimeInterval
    public var isPalmSwipeEnabled: Bool
    public var swipeAction: SwipeActionType
    public var cursorExperiment: CursorExperimentSettings
    public var language: AppLanguage

    public init(
        isCameraMirrored: Bool = true,
        isClutchEnabled: Bool = true,
        clutchDwellTime: TimeInterval = 0.08,
        preferredHandedness: EstimatedHandedness = .right,
        showHUD: Bool = true,
        hudShowsCamera: Bool = false,
        hudPreviewMirrored: Bool = true,
        hudShowsJointNumbers: Bool = false,
        hudHighlightFirstRing: Bool = false,
        hudSkeletonScale: Double = 1,
        isGestureClickAndMenuEnabled: Bool = false,
        showClickFeedback: Bool = true,
        hudSkeletonFPS: Int = 30,
        scrollInertiaEnabled: Bool = true,
        arbitrationCooldownSeconds: TimeInterval = 1.5,
        isPalmSwipeEnabled: Bool = true,
        swipeAction: SwipeActionType = .switchApp,
        cursorExperiment: CursorExperimentSettings = .init(),
        language: AppLanguage = .simplifiedChinese
    ) {
        self.isCameraMirrored = isCameraMirrored
        self.isClutchEnabled = isClutchEnabled
        self.clutchDwellTime = clutchDwellTime
        self.preferredHandedness = preferredHandedness
        self.showHUD = showHUD
        self.hudShowsCamera = hudShowsCamera
        self.hudPreviewMirrored = hudPreviewMirrored
        self.hudShowsJointNumbers = hudShowsJointNumbers
        self.hudHighlightFirstRing = hudHighlightFirstRing
        self.hudSkeletonScale = hudSkeletonScale
        self.isGestureClickAndMenuEnabled = isGestureClickAndMenuEnabled
        self.showClickFeedback = showClickFeedback
        self.hudSkeletonFPS = hudSkeletonFPS
        self.scrollInertiaEnabled = scrollInertiaEnabled
        self.arbitrationCooldownSeconds = arbitrationCooldownSeconds
        self.isPalmSwipeEnabled = isPalmSwipeEnabled
        self.swipeAction = swipeAction
        self.cursorExperiment = cursorExperiment
        self.language = language
    }
}
