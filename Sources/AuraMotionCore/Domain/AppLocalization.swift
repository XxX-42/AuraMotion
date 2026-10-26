import Combine
import Foundation

/// Languages supported by AuraMotion's in-app interface.
public enum AppLanguage: String, Codable, Sendable, CaseIterable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    public var displayName: String {
        switch self {
        case .simplifiedChinese: return L10n.tr("Simplified Chinese")
        case .english: return L10n.tr("English")
        }
    }
}

/// Shared, thread-safe language state for core feedback and SwiftUI.
///
/// The stored language can be read and changed from any queue. Observable
/// notifications are always delivered on the main queue so SwiftUI and AppKit
/// consumers can safely rebuild their presentation.
public final class AppLocalization: ObservableObject, @unchecked Sendable {
    public static let shared = AppLocalization()
    public static let languageDidChangeNotification = Notification.Name("AuraMotionLanguageDidChange")

    public let objectWillChange = ObservableObjectPublisher()

    private let lock = NSLock()
    private var storedLanguage: AppLanguage = .simplifiedChinese

    private init() {}

    public var language: AppLanguage {
        lock.lock()
        defer { lock.unlock() }
        return storedLanguage
    }

    public func setLanguage(_ language: AppLanguage) {
        lock.lock()
        let changed = storedLanguage != language
        storedLanguage = language
        lock.unlock()
        guard changed else { return }

        let publish: @Sendable () -> Void = { [weak self] in
            guard let self else { return }
            self.objectWillChange.send()
            NotificationCenter.default.post(name: Self.languageDidChangeNotification, object: language)
        }
        if Thread.isMainThread {
            publish()
        } else {
            DispatchQueue.main.async(execute: publish)
        }
    }
}

/// Small in-app translation table. English strings are the stable lookup keys.
public enum L10n {
    private static let simplifiedChinese: [String: String] = [
        // Language names
        "Simplified Chinese": "简体中文",
        "English": "English",

        // Menu bar
        "Pause Gesture Control": "暂停手势控制",
        "Toggle Floating HUD": "切换悬浮状态面板",
        "Diagnostics & Telemetry...": "诊断与遥测…",
        "Calibration...": "手势校准…",
        "Movement Calibration...": "移动校准…",
        "Settings...": "设置…",
        "Quit AuraMotion": "退出 AuraMotion",

        // Settings view (kept here for the SettingsView owner)
        "Language": "语言",
        "Permissions Status": "权限状态",
        "Camera Access:": "相机访问权限：",
        "Granted": "已授权",
        "Denied": "未授权",
        "Open Settings": "打开设置",
        "Computer Control:": "电脑控制：",
        "Request": "请求",
        "Input Event Posting:": "输入事件发送权限：",
        "Required": "必需",
        "Requesting…": "正在请求…",
        "Open Control Settings": "打开控制权限设置",
        "Input Monitoring (optional):": "输入监控（可选）：",
        "Not granted": "未授权",
        "Interaction Preferences": "交互偏好",
        "Mirror Camera Feed": "镜像摄像头画面",
        "Enable Engagement Clutch (Ready Pose)": "启用准备姿势（保持手势以激活）",
        "Activation Delay:": "激活延迟：",
        "Enable Scroll Inertia": "启用滚动惯性",
        "Enable Palm Swipe Switching": "启用手掌滑动切换",
        "Swipe Action:": "滑动操作：",
        "Desktops / full-screen apps (Control + Arrow)": "桌面 / 全屏应用（Control + 方向键）",
        "Windows of the current app (Command + `)": "当前应用的窗口（Command + `）",
        "Different apps (Command + Tab)": "其他应用（Command + Tab）",
        "HUD & Feedback": "悬浮面板与反馈",
        "Show Floating HUD": "显示悬浮状态面板",
        "Show Click Feedback Ripples": "显示点击波纹反馈",
        "Safety & Arbitration": "安全与输入仲裁",
        "Arbitration Cooldown:": "仲裁冷却时间：",
        "Input event posting is authorized.": "输入事件发送权限已授权。",
        "Requesting input event access from macOS…": "正在向 macOS 请求输入事件权限…",
        "macOS returned from the request, but event posting is not active yet. Approve any system alert, then wait for the status to refresh.": "macOS 已返回请求结果，但输入事件发送权限尚未启用。请先允许系统提示，然后等待状态刷新。",
        "macOS has not granted computer input control. Enable AuraMotion in Privacy & Security → {pane}. If its switch is already on after an app update, turn it off and on, then quit and reopen AuraMotion.": "macOS 尚未授予电脑输入控制权限。请在“隐私与安全性”→“{pane}”中启用 AuraMotion。若应用更新后开关已开启，请先关闭再开启，然后退出并重新打开 AuraMotion。",

        // HUD and live status
        "INITIALIZING": "正在初始化",
        "IDLE": "待机",
        "READY (HOLD TO ENGAGE)": "已就绪（保持手势以激活）",
        "TRACKING": "正在跟踪",
        "PINCH ARMED": "捏合待触发",
        "DRAGGING": "拖动中",
        "SCROLL PENDING": "等待滚动",
        "SCROLLING": "滚动中",
        "PAUSED": "已暂停",
        "TRACKING LOST - INPUT RELEASED": "跟踪丢失 - 已释放输入",
        "PALM DETECTED": "检测到手掌",
        "PALM REST": "手掌静止",
        "SWIPE LEFT ◀": "向左滑动 ◀",
        "SWIPE RIGHT ▶": "向右滑动 ▶",
        "No Hand Detected": "未检测到手",
        "Camera access is required": "需要相机访问权限",
        "Accessibility control is required": "需要辅助功能控制权限",
        "Input control permission is required": "需要输入控制权限",
        "NO CAMERA": "无相机权限",
        "Baseline": "基准模式",
        "NO ACCESSIBILITY": "无辅助功能权限",
        "NO INPUT CONTROL": "无输入控制权限",
        "Calibration — control paused": "正在校准 — 控制已暂停",
        "Input control is blocked": "输入控制受阻",
        "Mouse in use — gesture control waiting": "正在使用鼠标 — 手势控制等待中",
        "Hold steady, then separate fingertips": "请保持手部稳定，然后分开指尖",
        "Point to a command, then pinch": "指向命令，然后捏合确认",
        "Hold palm still to open commands": "保持手掌静止以打开命令菜单",
        "Click recognized": "已识别点击",
        "Left swipe recognized": "已识别向左滑动",
        "Right swipe recognized": "已识别向右滑动",
        "Right click recognized": "已识别右键单击",
        "Double click recognized": "已识别双击",
        "All windows recognized": "已识别调度中心",
        "Previous app recognized": "已识别切换到上一个应用",
        "Next app recognized": "已识别切换到下一个应用",
        "Minimize recognized": "已识别最小化",
        "Full screen recognized": "已识别进入全屏",
        "Left half recognized": "已识别移动到左半屏",
        "Right half recognized": "已识别移动到右半屏",
        "Copy recognized": "已识别复制",
        "Paste recognized": "已识别粘贴",

        // Calibration instructions, errors, and success messages
        "Personal Gesture Calibration": "个性化手势校准",
        "Six short recordings personalize Click, Copy and Paste. Gesture control pauses during setup. Camera video is never saved.": "通过六段简短采集个性化设置点击、复制和粘贴。设置期间手势控制会暂停；摄像头视频不会被保存。",
        "Start guided setup": "开始引导设置",
        "Step {current} of 6": "第 {current} 步，共 6 步",
        "Hold steady: {count} / 30 clear samples": "保持稳定：{count} / 30 个有效样本",
        "Get into position, then start recording.": "摆好手势后开始采集。",
        "Recording…": "正在采集…",
        "Record this pose": "采集此姿势",
        "Start again": "重新开始",
        "Cursor Gain:": "光标增益：",
        "Pinch Sensitivity:": "捏合灵敏度：",
        "Save and finish": "保存并完成",
        "Save adjustments": "保存调整",
        "Complete all six steps. If open and touching poses overlap, start again with your fingertips clearly separated for the open poses.": "请完成全部六个步骤。如果张开与接触姿势的数据重叠，请重新开始，并在张开姿势时让指尖保持明显分开。",
        "Calibration saved. Gesture control restored.": "校准已保存，手势控制已恢复。",
        "Cancel setup": "取消设置",
        "Your finger contacts are distinguishable. Save to use these thresholds.": "已成功区分手指接触状态。保存后即可使用这些阈值。",
        "Open and touching poses overlap. Start again and separate the fingertips more during the open steps.": "张开与接触姿势的数据重叠。请重新开始，并在张开步骤中让指尖分得更开。",
        "Hold your thumb and index fingertip comfortably apart.": "让拇指与食指指尖保持舒适的距离。",
        "Touch your thumb tip to your index fingertip.": "用拇指指尖轻触食指指尖。",
        "Hold your thumb and middle fingertip comfortably apart.": "让拇指与中指指尖保持舒适的距离。",
        "Touch your thumb tip to your middle fingertip.": "用拇指指尖轻触中指指尖。",
        "Hold your thumb and ring fingertip comfortably apart.": "让拇指与无名指指尖保持舒适的距离。",
        "Touch your thumb tip to your ring fingertip.": "用拇指指尖轻触无名指指尖。",
        "The hand moved too much. Hold steady and try this step again.": "手部移动幅度过大。请保持稳定并重试此步骤。",
        "Personalize Cursor Movement": "个性化光标移动",
        "Three short recordings learn your resting tremor and movement speeds. Control pauses during setup; camera video is not saved.": "通过三段简短采集学习静止时的手部抖动和移动速度。设置期间控制会暂停；摄像头视频不会被保存。",
        "Start movement setup": "开始移动设置",
        "Step {current} of 3": "第 {current} 步，共 3 步",
        "{count} / 60 clear observations": "{count} / 60 个有效观测",
        "Record this movement": "采集此动作",
        "Your movement profile is ready.": "移动配置已就绪。",
        "Save movement profile": "保存移动配置",
        "Saved. Your personalized cursor response is active.": "已保存，个性化光标响应已启用。",
        "Cancel": "取消",
        "Point with your index finger and hold comfortably still.": "伸出食指，并保持舒适静止。",
        "Keep pointing and sweep your hand slowly from side to side.": "保持指向姿势，将手缓慢地左右移动。",
        "Keep pointing and make quicker, comfortable side-to-side sweeps.": "保持指向姿势，以舒适的幅度更快地左右移动。",
        "Keep only the index finger extended, with thumb comfortably apart.": "只伸出食指，并让拇指保持舒适距离。",
        "Too much movement. Try holding still again.": "移动幅度过大。请重新尝试保持静止。",
        "Use a wider sweep; the quick sweep must be faster than the slow one.": "请增大移动幅度；快速移动必须比慢速移动更快。",

        // Diagnostics
        "System Telemetry & Diagnostics": "系统遥测与诊断",
        "Latency & Timing": "延迟与计时",
        "Vision Inference p50:": "视觉推理 p50：",
        "Vision Inference p95:": "视觉推理 p95：",
        "Mailbox Wait Time:": "帧队列等待时间：",
        "Capture → Vision result:": "采集 → 视觉结果：",
        "* Presentation timestamp anchored to host arrival clock": "* 展示时间戳以主机到达时钟为基准",
        "Cursor Stability": "光标稳定性",
        "Horizontal motion: orange is raw; cyan is smoothed. Hold still to compare jitter.": "水平移动：橙色为原始数据，青色为平滑数据。保持静止以比较抖动。",
        "Index confidence: %.0f%%": "食指置信度：%.0f%%",
        "System Health": "系统状态",
        "Thermal Quality Stage:": "热管理质量等级：",
        "Dropped Frames:": "丢帧数：",
        "Physical Arbitration Tap:": "物理输入仲裁监听：",
        "Active": "运行中",
        "Disabled/Cooldown": "已停用 / 冷却中",
        "Landmark Recording (Privacy-Safe)": "关键点记录（保护隐私）",
        "Records anonymized 2D joint coordinates for regression testing. No camera video is ever saved.": "记录匿名化的二维关节点坐标以进行回归测试。摄像头视频绝不会被保存。",
        "Stop & Save Recording": "停止并保存记录",
        "Start Recording": "开始记录",
        "Recording...": "正在记录…",
        "Saved to: {filename}": "已保存到：{filename}",

        // Hand command palette
        "HAND COMMANDS": "手势命令",
        "Point · Pinch": "指向 · 捏合",
        "Raise your index finger to begin": "伸出食指以开始",
        "Move your hand to choose. Pinch to confirm.": "移动手部进行选择，捏合以确认。",
        "Lower or withdraw your hand to dismiss · Closes automatically after 12 seconds": "放下或移开手部以关闭 · 12 秒后自动关闭",
        "Right click": "右键单击",
        "Double click": "双击",
        "All windows": "调度中心",
        "Previous app": "上一个应用",
        "Next app": "下一个应用",
        "Minimize": "最小化",
        "Full screen": "全屏",
        "Left half": "左半屏",
        "Right half": "右半屏"
    ]

    /// English copy remains the key and fallback for strings not yet translated.
    public static func tr(_ english: String) -> String {
        guard AppLocalization.shared.language == .simplifiedChinese else { return english }
        return simplifiedChinese[english] ?? english
    }

    /// Translate a sentence containing runtime values, such as a Settings pane name.
    public static func tr(_ english: String, replacing values: [String: String]) -> String {
        values.reduce(tr(english)) { result, replacement in
            result.replacingOccurrences(of: replacement.key, with: replacement.value)
        }
    }

    static var translatedEnglishKeys: Set<String> { Set(simplifiedChinese.keys) }
}

public extension SwipeActionType {
    /// Localized UI label while keeping the model's established English display name.
    var localizedDisplayName: String { L10n.tr(displayName) }
}
