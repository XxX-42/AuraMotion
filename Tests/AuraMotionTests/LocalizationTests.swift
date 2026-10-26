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

    func testEveryStaticUiKeyHasChineseCopy() {
        // Inventory all literal L10n lookups, the dynamic labels passed to
        // CursorExperimentPanel's helper methods, and core-generated HUD text.
        let requiredKeys: Set<String> = [
            "%.0f ms", "%.1f s", "* Presentation timestamp anchored to host arrival clock",
            "A/B Metrics", "Absolute Legacy", "Accessibility control is required",
            "Activation Delay:", "Adaptive Deadzone", "Advanced Tuning", "All windows",
            "All windows recognized", "An opt-in camera sample runs for 15 seconds. No camera video is saved.",
            "Arbitration Cooldown:", "AuraMotion Calibration", "AuraMotion Diagnostics",
            "AuraMotion Movement Calibration", "AuraMotion Settings", "Baseline", "CAP",
            "Calibration...", "Camera Access:", "Camera access is required", "Cancel", "Cancel Sample", "Cancel setup",
            "Capture → Vision result:", "Click recognized", "Computer Control:", "Copy recognized",
            "Cursor Experiment Settings", "Cursor Gain:", "Cursor Stability", "Custom", "DRAGGING",
            "DROP", "Deadzone Velocity (px/s)", "Derivative Cutoff",
            "Desktops / full-screen apps (Control + Arrow)", "Diagnostics & Telemetry...",
            "Different apps (Command + Tab)", "Double click", "Double click recognized", "Drag Beta",
            "Drag Min Cutoff", "Dropped Frames:", "Enable Engagement Clutch (Ready Pose)",
            "Enable Palm Swipe Switching", "Enable Scroll Inertia",
            "Experimental settings are opt-in. Baseline keeps the legacy cursor path.",
            "Raise your hand, extend only your index finger, and keep your thumb away from your middle and ring fingers. Recording starts when the HUD says TRACKING.",
            "Export A/B Metrics", "Fast Gain", "Fast Speed (px/s)", "Filter Preset:", "Full screen",
            "Full screen recognized", "Get into position, then start recording.", "HAND COMMANDS",
            "HUD & Feedback", "Hold steady: {count} / 30 clear samples",
            "Hold your thumb and index fingertip comfortably apart.",
            "Hold your thumb and middle fingertip comfortably apart.",
            "Hold your thumb and ring fingertip comfortably apart.",
            "Horizontal motion: orange is raw; cyan is smoothed. Hold still to compare jitter.", "IDLE",
            "INF", "Index MCP", "Index confidence: %.0f%%", "Input Event Posting:",
            "Input Monitoring (optional):", "Input control permission is required",
            "Input event posting is authorized.", "Interaction Preferences",
            "Keep pointing and make quicker, comfortable side-to-side sweeps.",
            "Keep pointing and sweep your hand slowly from side to side.",
            "Landmark Recording (Privacy-Safe)", "Language", "Latency & Timing", "Left half",
            "Left half recognized", "Left swipe recognized", "Legacy", "Legacy Tip Fusion",
            "Low-Speed Quantization", "Lower or withdraw your hand to dismiss · Closes automatically after 12 seconds",
            "Mailbox Wait Time:", "Mapping Mode:", "MediaPipe Benchmark", "MediaPipe hand tracking is unavailable.",
            "Metrics export failed.", "Metrics exported.", "Metrics reset.", "Metrics sample complete.", "Minimize", "Minimize recognized",
            "Mirror Camera Feed", "Movement Calibration...", "Moving Deadzone (px)", "NO ACCESSIBILITY",
            "NO CAMERA", "NO INPUT CONTROL", "Next app", "Next app recognized", "No Hand Detected",
            "No tracked pointer was detected within 30 seconds.",
            "Normal Gain", "Normal Speed (px/s)", "Open Control Settings", "Open Settings", "Optimized",
            "Optimized One Euro Filter", "PALM DETECTED", "PALM REST", "PAUSED", "PINCH ARMED",
            "Palm Centroid", "Palm MCP Fusion", "Paste recognized", "Pause Gesture Control",
            "Permissions Status", "Personal Gesture Calibration", "Personalize Cursor Movement",
            "Physical Arbitration Tap:", "Pinch Sensitivity:",
            "Point with your index finger and hold comfortably still.", "Point · Pinch", "Pointer Anchor:",
            "Pointer Beta", "Pointer Min Cutoff", "Precision", "Precision Gain", "Precision Speed (px/s)",
            "Preset:", "Previous app", "Previous app recognized", "Preparing camera sample… {seconds}", "Quantization Speed Threshold (px/s)",
            "Quit AuraMotion", "READY (HOLD TO ENGAGE)", "ROI Minimum Size", "ROI Scale",
            "Recording camera sample…", "Recording...",
            "Recording camera sample… {seconds}",
            "Records anonymized 2D joint coordinates for regression testing. No camera video is ever saved.",
            "Relative Rebased", "Relative Rebased Mapping", "Request", "Requesting input event access from macOS…",
            "Reset Experiment Metrics", "Rest Deadzone (px)", "Right click", "Right click recognized",
            "Right half", "Right half recognized", "Right swipe recognized",
            "Run one sample per preset to compare baseline and optimized results.", "SCROLL PENDING", "SCROLLING",
            "Reveal in Finder",
            "SWIPE LEFT ◀", "SWIPE RIGHT ▶", "Safety & Arbitration", "Save movement profile",
            "Sample cancelled.", "Saved to: {filename}", "Separate Drag Filter Tuning", "Settings...", "Show Click Feedback Ripples",
            "Show Floating HUD",
            "Six short recordings personalize Click, Copy and Paste. Gesture control pauses during setup. Camera video is never saved.",
            "Stable Pointer Anchor", "Start 15s Camera A/B Sample", "Start again", "Start guided setup",
            "Start movement setup", "Step {current} of 3", "Step {current} of 6", "Stop Sample", "Swipe Action:",
            "System Health", "System Telemetry & Diagnostics", "TRACKING", "TRACKING LOST - INPUT RELEASED",
            "Waiting for a tracked pointer…",
            "Thermal Quality Stage:",
            "Three short recordings learn your resting tremor and movement speeds. Control pauses during setup; camera video is not saved.",
            "Toggle Floating HUD", "Touch your thumb tip to your index fingertip.",
            "Touch your thumb tip to your middle fingertip.", "Touch your thumb tip to your ring fingertip.",
            "Velocity-Based Gain", "Vision Inference p50:", "Vision Inference p95:",
            "Vision Region of Interest (ROI)", "Vision remains active; no MediaPipe benchmark will run.",
            "Windows of the current app (Command + `)", "Your movement profile is ready.",
            "Input event posting is authorized.",
            "Requesting input event access from macOS…",
            "macOS returned from the request, but event posting is not active yet. Approve any system alert, then wait for the status to refresh.",
            "macOS has not granted computer input control. Enable AuraMotion in Privacy & Security → {pane}. If its switch is already on after an app update, turn it off and on, then quit and reopen AuraMotion.",
            "Camera access is required", "Baseline", "Desktops / full-screen apps (Control + Arrow)",
            "Windows of the current app (Command + `)", "Different apps (Command + Tab)",
            "Right click", "Double click", "All windows", "Previous app", "Next app", "Minimize", "Full screen", "Left half", "Right half",
            "Click recognized", "Left swipe recognized", "Right swipe recognized", "Copy recognized", "Paste recognized",
            "Right click recognized", "Double click recognized", "All windows recognized", "Previous app recognized",
            "Next app recognized", "Minimize recognized", "Full screen recognized", "Left half recognized", "Right half recognized"
        ]
        let otherDictionaryKeys: Set<String> = [
            "Accessibility", "Active", "Calibration saved. Gesture control restored.",
            "Calibration — control paused",
            "Complete all six steps. If open and touching poses overlap, start again with your fingertips clearly separated for the open poses.",
            "Current ROI:", "Cursor Experiments", "Denied", "Device Control & Data Access", "Disabled",
            "Disabled/Cooldown", "Enabled", "Fast movement", "Full-frame fallback",
            "Effective cursor strategy:", "Effective vision provider:", "English", "Granted",
            "Hold palm still to open commands", "Hold steady, then separate fingertips", "INITIALIZING",
            "Input control is blocked", "Keep only the index finger extended, with thumb comfortably apart.",
            "MediaPipe benchmark requested but unavailable:",
            "MediaPipe Tasks Vision is unavailable on macOS: the current upstream binary provides iOS and iOS Simulator slices only, with no macOS slice.",
            "Mouse in use — gesture control waiting", "Move your hand to choose. Pinch to confirm.",
            "Open Pointer Test Surface", "Pointer Target & Drag Test",
            "Click three targets with the gesture pointer. Then test dragging inside this window.",
            "Start Target Test", "Start Drag Test", "Export Task Results", "FSM state:",
            "Tagged events: move {move}, down {down}, drag {drag}, up {up}; external {external}",
            "Ready", "Target",
            "Drag from the left circle to the right circle.", "Task complete", "Results exported",
            "No task results yet", "Input source", "Gesture", "External",
            "Not granted", "Open and touching poses overlap. Start again and separate the fingertips more during the open steps.",
            "Point to a command, then pinch", "ROI fallback:", "Raise your index finger to begin",
            "Reconfiguring vision provider…", "Record this movement", "Record this pose", "Recording…", "Requesting…",
            "Required", "Save adjustments", "Save and finish", "Saved. Your personalized cursor response is active.",
            "Simplified Chinese", "Start Recording", "Stop & Save Recording",
            "The hand moved too much. Hold steady and try this step again.",
            "Too much movement. Try holding still again.", "Use a wider sweep; the quick sweep must be faster than the slow one.",
            "Vision ROI:", "Vision", "MediaPipe", "Sample purpose:", "Slow movement", "Stationary hold",
            "Unlabelled", "Purpose labels the full sample; target metrics still need target coordinates.",
            "Your finger contacts are distinguishable. Save to use these thresholds.",
            "{count} / 60 clear observations"
        ]
        let allKeys = requiredKeys.union(otherDictionaryKeys)
        let missingKeys = allKeys.subtracting(L10n.translatedEnglishKeys)

        XCTAssertTrue(missingKeys.isEmpty, "Missing Simplified Chinese translations: \(missingKeys.sorted())")
        XCTAssertTrue(L10n.translatedEnglishKeys.isSubset(of: allKeys), "Every dictionary entry must be listed in localization coverage tests")
        for key in allKeys {
            XCTAssertFalse(L10n.tr(key).isEmpty, "Empty Simplified Chinese translation for: \(key)")
        }
    }

    func testExperimentAndVisionStatusCopyIsLocalized() {
        XCTAssertEqual(
            L10n.tr("Run one sample per preset to compare baseline and optimized results."),
            "每个预设各运行一次采样，以比较基准与优化结果。"
        )
        XCTAssertEqual(L10n.tr("Vision ROI:"), "Vision 感兴趣区域（ROI）：")
        XCTAssertEqual(L10n.tr("Current ROI:"), "当前感兴趣区域（ROI）：")
        XCTAssertEqual(L10n.tr("ROI fallback:"), "感兴趣区域回退：")
        XCTAssertEqual(L10n.tr("Reconfiguring vision provider…"), "正在重新配置视觉后端…")
        XCTAssertEqual(L10n.tr("MediaPipe benchmark requested but unavailable:"), "已请求 MediaPipe 对比实验，但当前不可用：")
        XCTAssertEqual(
            L10n.tr("MediaPipe Tasks Vision is unavailable on macOS: the current upstream binary provides iOS and iOS Simulator slices only, with no macOS slice."),
            "MediaPipe Tasks Vision 在 macOS 上不可用：当前上游二进制仅提供 iOS 和 iOS 模拟器架构，不包含 macOS 架构。"
        )
    }

    func testPointerValidationSurfaceCopyIsLocalized() {
        XCTAssertEqual(L10n.tr("Open Pointer Test Surface"), "打开指针测试界面")
        XCTAssertEqual(L10n.tr("Start Target Test"), "开始目标测试")
        XCTAssertEqual(L10n.tr("Start Drag Test"), "开始拖动测试")
        XCTAssertEqual(L10n.tr("Drag from the left circle to the right circle."), "从左侧圆圈拖动到右侧圆圈。")
        XCTAssertEqual(L10n.tr("Results exported"), "结果已导出")
        XCTAssertEqual(L10n.tr("Input source"), "输入来源")
    }
}
