#if DEBUG
import AppKit
import SwiftUI
import QuartzCore
import AuraMotionCore

@MainActor
final class HeadSonarDebugController: ObservableObject {
    static let shared = HeadSonarDebugController()
    @Published private(set) var headEnabled = false
    @Published private(set) var sonarEnabled = false
    @Published private(set) var headStatus = "头部交点：关闭"
    @Published private(set) var sonarStatus = "声呐：关闭"
    private let marker = GazeProjectionWindow(color: .systemOrange)
    private var process: Process?
    private var timer: Timer?
    private var lastFace: FaceSample?
    private let output = FileManager.default.temporaryDirectory.appendingPathComponent("auramotion-sonar-\(ProcessInfo.processInfo.processIdentifier).json")

    func toggleHead() {
        headEnabled.toggle()
        updateFace(lastFace)
    }
    func updateFace(_ face: FaceSample?) {
        lastFace = face
        guard headEnabled, let face, let pose = face.headPose,
              CACurrentMediaTime() >= face.timestamp, CACurrentMediaTime() - face.timestamp < 0.5,
              let point = HeadDirectionProjection.approximate(pose: pose, mirrored: face.isMirrored, display: CGDisplayBounds(CGMainDisplayID())) else {
            marker.update(nil)
            headStatus = headEnabled ? "头部交点：等待有效面部姿态" : "头部交点：关闭"
            return
        }
        marker.update(point)
        headStatus = String(format: "头部交点（近似）：%.0f, %.0f · yaw %+.1f° pitch %+.1f°", point.x, point.y, pose.yaw * 180 / .pi, pose.pitch * 180 / .pi)
    }
    func toggleSonar() { sonarEnabled ? stopSonar() : startSonar() }
    func startSonar() {
        guard let faceScript = ProcessInfo.processInfo.environment["AURAMOTION_FACE_SCRIPT"] else {
            sonarStatus = "声呐不可用：缺少开发路径"; return
        }
        let root = URL(fileURLWithPath: faceScript).deletingLastPathComponent().deletingLastPathComponent()
        let sonarRoot = root.deletingLastPathComponent().appendingPathComponent("acoustic-sonar")
        let python = sonarRoot.appendingPathComponent(".venv/bin/python")
        let script = sonarRoot.appendingPathComponent("sonar.py")
        let bridge = root.appendingPathComponent("scripts/sonar_hud_bridge.py")
        guard FileManager.default.isExecutableFile(atPath: python.path), FileManager.default.fileExists(atPath: script.path) else {
            sonarStatus = "声呐不可用：找不到 acoustic-sonar 或虚拟环境"; return
        }
        try? FileManager.default.removeItem(at: output)
        let task = Process(); task.executableURL = python; task.arguments = [bridge.path, script.path, output.path]
        task.standardOutput = FileHandle.nullDevice; task.standardError = FileHandle.standardError
        do { try task.run() } catch { sonarStatus = "声呐启动失败：\(error.localizedDescription)"; return }
        process = task; sonarEnabled = true; sonarStatus = "声呐启动中（需要麦克风权限）"
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor in HeadSonarDebugController.shared.pollSonar() }
        }
    }
    private func pollSonar() {
        guard let process, process.isRunning else { stopSonar(); sonarStatus = "声呐进程已退出，请检查麦克风和音频设备"; return }
        guard let data = try? Data(contentsOf: output), let result = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let timestamp = result["timestamp"] as? Double, Date().timeIntervalSince1970 - timestamp < 2 else {
            sonarStatus = "声呐等待有效回波（检查麦克风权限和音频设备）"; return
        }
        if let meters = result["distance_m"] as? Double, meters.isFinite {
            sonarStatus = String(format: "声呐回波：%.1f cm（可能来自其他物体）", meters * 100)
        } else { sonarStatus = "声呐：未检测到有效回波" }
    }
    func stopSonar() {
        timer?.invalidate(); timer = nil
        if let process, process.isRunning { process.terminate() }
        process = nil; sonarEnabled = false; sonarStatus = "声呐：关闭"
        try? FileManager.default.removeItem(at: output)
    }
}
#endif
