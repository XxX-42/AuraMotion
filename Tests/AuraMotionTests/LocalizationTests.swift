import XCTest
@testable import AuraMotionCore

final class LocalizationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AppLocalization.shared.setLanguage(.simplifiedChinese)
    }

    override func tearDown() {
        AppLocalization.shared.setLanguage(.simplifiedChinese)
        super.tearDown()
    }

    func testSimplifiedChineseTranslationAcrossUISurfaces() {
        XCTAssertEqual(L10n.tr("Camera Access:"), "相机访问权限：")
        XCTAssertEqual(L10n.tr("Step {current} of 6", replacing: ["{current}": "2"]), "第 2 步，共 6 步")
        XCTAssertEqual(GestureState.paused.displayName, "已暂停")
        XCTAssertEqual(PersonalCalibration().step.instruction, "让拇指与食指指尖保持舒适的距离。")
        XCTAssertEqual(MovementCalibration().step.instruction, "伸出食指，并保持舒适静止。")
        XCTAssertEqual(GestureCommand.rightClick.localizedTitle, "右键单击")
        XCTAssertEqual(SwipeActionType.switchApp.localizedDisplayName, "其他应用（Command + Tab）")
        XCTAssertEqual(L10n.tr("Baseline"), "基准模式")
    }

    func testEnglishUsesStableSourceCopyAndFallback() {
        AppLocalization.shared.setLanguage(.english)

        XCTAssertEqual(L10n.tr("Camera Access:"), "Camera Access:")
        XCTAssertEqual(L10n.tr("Step {current} of 6", replacing: ["{current}": "2"]), "Step 2 of 6")
        XCTAssertEqual(GestureState.paused.displayName, "PAUSED")
        XCTAssertEqual(GestureCommand.rightClick.localizedTitle, "Right click")
        XCTAssertEqual(L10n.tr("Future untranslated copy"), "Future untranslated copy")
    }

    func testTranslationTableCoversSettingsAndFeedbackKeys() {
        let requiredKeys: Set<String> = [
            "Language", "Simplified Chinese", "English",
            "Permissions Status", "Camera Access:", "Computer Control:",
            "Input Event Posting:", "Input Monitoring (optional):",
            "Interaction Preferences", "Mirror Camera Feed",
            "Enable Engagement Clutch (Ready Pose)", "Activation Delay:",
            "Enable Scroll Inertia", "Enable Palm Swipe Switching", "Swipe Action:",
            "HUD & Feedback", "Show Floating HUD", "Show Click Feedback Ripples",
            "Safety & Arbitration", "Arbitration Cooldown:",
            "READY (HOLD TO ENGAGE)", "TRACKING LOST - INPUT RELEASED",
            "Calibration — control paused", "Hold steady, then separate fingertips",
            "System Telemetry & Diagnostics", "Latency & Timing", "Cursor Stability",
            "System Health", "Landmark Recording (Privacy-Safe)",
            "Personal Gesture Calibration", "Personalize Cursor Movement",
            "HAND COMMANDS", "Raise your index finger to begin", "Right click", "Baseline"
        ]
        let missingKeys = requiredKeys.subtracting(L10n.translatedEnglishKeys)

        XCTAssertTrue(missingKeys.isEmpty, "Missing Simplified Chinese translations: \(missingKeys.sorted())")
        XCTAssertGreaterThan(L10n.translatedEnglishKeys.count, 100)
    }
}
