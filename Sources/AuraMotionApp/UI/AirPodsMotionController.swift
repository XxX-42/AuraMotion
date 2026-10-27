import AppKit
import CoreMotion
import SwiftUI
import QuartzCore

struct AirPodsMotionSample: Sendable {
    let timestamp, x, y, z, w, yaw, pitch, roll: Double
}

@MainActor
final class AirPodsMotionController: ObservableObject {
    static let shared = AirPodsMotionController()
    @Published private(set) var enabled = false
    @Published private(set) var sample: AirPodsMotionSample?
    @Published private(set) var status = "AirPods：关闭"
    @Published private(set) var fps: Double?
    private let manager = CMHeadphoneMotionManager()
    private let marker = GazeProjectionWindow(color: .systemMint)
    private var center: (yaw: Double, pitch: Double)?
    private var lastReceived: CFTimeInterval = 0
    private var fpsWindowStart: CFTimeInterval = 0
    private var fpsCount = 0
    private var watchdog: Timer?
    private var generation = 0

    func toggle() { enabled ? stop() : start() }
    private func start() {
        guard manager.isDeviceMotionAvailable else { status = "AirPods 运动数据不可用：请连接并佩戴耳机"; enabled = true; return }
        enabled = true; sample = nil; center = nil; generation += 1
        let currentGeneration = generation
        status = "等待 AirPods 数据及运动权限…"
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            let message = error?.localizedDescription
            let value: AirPodsMotionSample? = motion.map { m in
                let a = m.attitude, q = a.quaternion
                return AirPodsMotionSample(timestamp: m.timestamp, x: q.x, y: q.y, z: q.z, w: q.w, yaw: a.yaw, pitch: a.pitch, roll: a.roll)
            }
            Task { @MainActor [weak self] in
                guard let self, self.enabled, self.generation == currentGeneration else { return }
                if let message { self.status = "AirPods 错误：\(message)"; self.marker.update(nil); self.sample = nil; return }
                guard let value else { return }
                self.receive(value)
            }
        }
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkFreshness() }
        }
    }
    private func receive(_ value: AirPodsMotionSample, force: Bool = false) {
        guard [value.timestamp, value.x, value.y, value.z, value.w, value.yaw, value.pitch, value.roll].allSatisfy(\.isFinite) else { return }
        let now = CACurrentMediaTime()
        lastReceived = now
        if !force {
            if fpsWindowStart == 0 { fpsWindowStart = now; fpsCount = 0 }
            fpsCount += 1
            let elapsed = now - fpsWindowStart
            if elapsed >= 1 {
                fps = Double(fpsCount) / elapsed
                fpsWindowStart = now; fpsCount = 0
            }
        }
        sample = value
        if center == nil { center = (value.yaw, value.pitch) }
        guard let center else { return }
        let yaw = atan2(sin(value.yaw - center.yaw), cos(value.yaw - center.yaw))
        let pitch = value.pitch - center.pitch
        let bounds = CGDisplayBounds(CGMainDisplayID())
        // Directional visualization with a nominal ±30° range, not a physical ray intersection.
        let x = min(max(0.5 - yaw / (.pi / 3), 0), 1)
        let y = min(max(0.5 - pitch / (.pi / 3), 0), 1)
        let point = CGPoint(x: bounds.minX + bounds.width * x, y: bounds.minY + bounds.height * y)
        marker.update(point)
        status = String(format: "AirPods 近似交点：%.0f, %.0f · 面向屏幕中心可归零", point.x, point.y)
    }
    func recenter() {
        guard let sample, CACurrentMediaTime() - lastReceived < 1 else { status = "等待新鲜数据后再归零"; return }
        center = (sample.yaw, sample.pitch); receive(sample, force: true)
    }
    private func checkFreshness() {
        guard enabled, lastReceived > 0, CACurrentMediaTime() - lastReceived > 1 else { return }
        marker.update(nil); sample = nil; fps = nil; fpsWindowStart = 0; fpsCount = 0; status = "AirPods 数据中断：请检查连接和佩戴状态"
    }
    func stop() {
        generation += 1; manager.stopDeviceMotionUpdates(); watchdog?.invalidate(); watchdog = nil
        enabled = false; sample = nil; center = nil; lastReceived = 0; fpsWindowStart = 0; fpsCount = 0; fps = nil; marker.update(nil); status = "AirPods：关闭"
    }
}
