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
    @Published private(set) var boundaryCalibration = HeadBoundaryCalibration()
    @Published private(set) var boundaryStatus = "转头朝向屏幕边界，保持姿势并点击对应按钮"
    private struct SavedBoundaries: Codable { let context: String; let calibration: HeadBoundaryCalibration }
    private let boundaryKey = "headBoundaryCalibration.v1"
    private var boundaryContext: String?
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
              CACurrentMediaTime() >= face.timestamp, CACurrentMediaTime() - face.timestamp < 0.5 else {
            marker.update(nil)
            headStatus = headEnabled ? "头部交点：等待有效面部姿态" : "头部交点：关闭"
            return
        }
        guard let camera = AppEnvironment.shared.capturePipeline.calibrationCameraIdentity else {
            marker.update(nil); headStatus = "头部交点：等待摄像头信息"; return
        }
        let bounds = CGDisplayBounds(CGMainDisplayID())
        let context = "\(camera.id)|\(camera.width)x\(camera.height)|\(face.isMirrored)|\(CGMainDisplayID())|\(bounds.width)x\(bounds.height)"
        if boundaryContext != context {
            boundaryContext = context
            if let data = UserDefaults.standard.data(forKey: boundaryKey), let saved = try? JSONDecoder().decode(SavedBoundaries.self, from: data), saved.context == context {
                boundaryCalibration = saved.calibration; boundaryStatus = "已恢复本机头部边界校准"
            } else { boundaryCalibration = HeadBoundaryCalibration(); boundaryStatus = "转头朝向屏幕边界，保持姿势并点击对应按钮" }
        }
        guard let point = boundaryCalibration.project(pose: pose, mirrored: face.isMirrored, display: bounds) else {
            marker.update(nil); headStatus = "头部交点：方向不可用"; return
        }
        marker.update(point)
        headStatus = String(format: "头部交点（近似）：%.0f, %.0f · yaw %+.1f° pitch %+.1f°", point.x, point.y, pose.yaw * 180 / .pi, pose.pitch * 180 / .pi)
    }
    func recordBoundary(_ edge: HeadBoundaryCalibration.Edge) {
        guard headEnabled, let face = lastFace, let pose = face.headPose, let context = boundaryContext,
              CACurrentMediaTime() >= face.timestamp, CACurrentMediaTime() - face.timestamp < 0.5 else {
            boundaryStatus = "未检测到新鲜面部数据，请面向摄像头"; return
        }
        var updated = boundaryCalibration
        guard updated.record(edge, yaw: pose.yaw, pitch: pose.pitch) else {
            boundaryStatus = "与对侧角度太近，请转向该边缘后重试"; return
        }
        boundaryCalibration = updated
        if let data = try? JSONEncoder().encode(SavedBoundaries(context: context, calibration: updated)) {
            UserDefaults.standard.set(data, forKey: boundaryKey)
            boundaryStatus = "已保存；同一方向可随时重新绑定"
        } else { boundaryStatus = "仅本次会话生效，保存失败" }
        updateFace(face)
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
