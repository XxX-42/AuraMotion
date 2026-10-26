#if DEBUG
import SwiftUI
import AppKit
import CoreGraphics
import QuartzCore
import AuraMotionCore

@MainActor
final class GazeDebugController: ObservableObject {
    static let shared = GazeDebugController()
    @Published var calibration: GazeCalibration?
    @Published var estimate: GazeEstimate?
    @Published var fixation: FixationState = .unavailable
    @Published private(set) var spatial = HeadCenteredTargeting()
    @Published var status = "请先进行九点校准"
    private var detector = FixationDetector()
    private var calibratedMirroring: Bool?
    private var calibratedBounds: CGRect?
    private var window: NSWindow?
    var lastFace: FaceSample?

    func receive(_ face: FaceSample?) {
        lastFace = face
        guard let face, let calibration, let mirrored = calibratedMirroring, let bounds = calibratedBounds,
              mirrored == face.isMirrored, bounds == CGDisplayBounds(CGMainDisplayID()),
              CACurrentMediaTime() >= face.timestamp, CACurrentMediaTime() - face.timestamp < 0.3 else {
            estimate = nil; fixation = detector.update(nil)
            spatial.update(face: face, gaze: nil, fixation: fixation, displayBounds: CGDisplayBounds(CGMainDisplayID()), now: CACurrentMediaTime())
            return
        }
        let value = GazeEstimator.estimate(face: face, calibration: calibration, displayBounds: bounds)
        estimate = value
        fixation = detector.update(value)
        spatial.update(face: face, gaze: value, fixation: fixation, displayBounds: bounds, now: CACurrentMediaTime())
    }
    func clearIfStale() {
        if let face = lastFace, CACurrentMediaTime() - face.timestamp >= 0.3 { receive(nil) }
        spatial.expire(now: CACurrentMediaTime())
    }
    func begin() {
        calibration = nil; calibratedMirroring = nil; calibratedBounds = nil
        estimate = nil; fixation = detector.update(nil); spatial.clear(); status = "正在校准"
    }
    func cancel() {
        if calibration == nil { status = "请先进行九点校准" }
    }
    func finish(_ samples: [GazeCalibrationPoint], mirroring: Bool, bounds: CGRect) throws {
        let model = try GazeCalibration.fit(samples)
        calibratedMirroring = mirroring; calibratedBounds = bounds
        calibration = model; status = "校准完成，点击目标检查预测"
    }
    func show() {
        let mainID = CGMainDisplayID()
        guard let screen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == mainID }) ?? NSScreen.main else { return }
        if let existing = window { existing.makeKeyAndOrderFront(nil); return }
        let panel = NSWindow(contentRect: screen.frame, styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false, screen: screen)
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.backgroundColor = .black
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.contentView = NSHostingView(rootView: GazeCalibrationView(controller: self, close: { [weak self] in self?.close() }))
        window = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    private func close() { window?.orderOut(nil); window = nil }
}

private struct GazeCalibrationView: View {
    @ObservedObject var controller: GazeDebugController
    let close: () -> Void
    @State private var active = false
    @State private var index = 0
    @State private var pointStart = Date()
    @State private var samples: [GazeCalibrationPoint] = []
    @State private var bucket: [EyeFeatures] = []
    @State private var lastFrame: UInt64?
    @State private var lastGoodTime: TimeInterval?
    @State private var mirror: Bool?
    @State private var bounds = CGDisplayBounds(CGMainDisplayID())
    @State private var message = "请面向摄像头，开始后依次注视每个圆点。"
    private let timer = Timer.publish(every: 0.08, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.95).ignoresSafeArea()
                ForEach(0..<GazeCalibration.nineTargets.count, id: \.self) { i in
                    let point = GazeCalibration.nineTargets[i]
                    Circle().fill(i == index ? Color.yellow : Color.gray.opacity(0.3))
                        .frame(width: i == index ? 20 : 8, height: i == index ? 20 : 8)
                        .position(x: geo.size.width * point.x, y: geo.size.height * point.y)
                        .onTapGesture { if !active { index = i } }
                }
                if let gaze = controller.estimate {
                    let x = (gaze.screenPoint.x - bounds.minX) / bounds.width * geo.size.width
                    let y = (gaze.screenPoint.y - bounds.minY) / bounds.height * geo.size.height
                    Image(systemName: "xmark").font(.system(size: 20, weight: .bold)).foregroundColor(.cyan)
                        .position(x: x, y: y)
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Button(active ? "校准中…" : "开始九点校准") { start() }.disabled(active)
                        Button("关闭") { if active { controller.cancel() }; active = false; close() }
                        Text(controller.status).foregroundColor(.white.opacity(0.8))
                    }
                    Text(message).foregroundColor(.white)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(24)
            }
        }
        .onReceive(timer) { now in tick(now) }
    }
    private func start() {
        controller.begin(); bounds = CGDisplayBounds(CGMainDisplayID())
        samples = []; bucket = []; index = 0; lastFrame = nil; lastGoodTime = nil; mirror = nil
        pointStart = Date(); active = true
        message = "请注视黄色圆点，保持头部稳定。"
    }
    private func tick(_ now: Date) {
        guard active else { return }
        let elapsed = now.timeIntervalSince(pointStart)
        if elapsed >= 0.7, let face = controller.lastFace, face.frameID != lastFrame,
           CACurrentMediaTime() >= face.timestamp, CACurrentMediaTime() - face.timestamp < 0.25,
           let feature = EyeFeatureExtractor.extract(face) {
            if let mirror, mirror != face.isMirrored { active = false; message = "摄像头方向改变，请重新校准。"; return }
            if let lastGoodTime, face.timestamp <= lastGoodTime || face.timestamp - lastGoodTime > 0.3 { bucket = [] }
            mirror = face.isMirrored; lastFrame = face.frameID; lastGoodTime = face.timestamp; bucket.append(feature)
        }
        if let lastGoodTime, CACurrentMediaTime() - lastGoodTime > 0.3 { bucket = [] }
        guard elapsed >= 1.6 else { return }
        guard bucket.count >= 5 else { message = "无法稳定识别双眼，请注视当前圆点并调整摄像头。"; return }
        let means = (0..<8).map { j in bucket.reduce(0.0) { $0 + $1.vector[j] } / Double(bucket.count) }
        samples.append(GazeCalibrationPoint(features: EyeFeatures(means), target: GazeCalibration.nineTargets[index]))
        bucket = []; lastGoodTime = nil; index += 1; pointStart = now
        if index >= GazeCalibration.nineTargets.count {
            active = false; index = 4
            do {
                guard let mirror else { throw GazeCalibration.Error.invalidData }
                try controller.finish(samples, mirroring: mirror, bounds: bounds)
                message = "黄色圆点为目标，青色 × 为预测位置。可点击灰点切换目标。"
            } catch {
                message = "校准失败：眼部数据变化不足或无效，请重新开始。"
            }
        } else { message = "校准 \(index + 1)/9：请注视黄色圆点。" }
    }
}
#endif
