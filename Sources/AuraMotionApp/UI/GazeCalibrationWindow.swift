#if DEBUG
import SwiftUI
import AppKit
import CoreGraphics
import QuartzCore
import AuraMotionCore

@MainActor
private final class GazeCalibrationWindowDelegate: NSObject, NSWindowDelegate {
    var onClose: (() -> Void)?
    func windowWillClose(_ notification: Notification) { onClose?() }
}

@MainActor
final class GazeDebugController: ObservableObject {
    static let shared = GazeDebugController()
    @Published var calibration: GazeCalibration?
    @Published var estimatorMode: GazeEstimatorMode = .irisDominant {
        didSet {
            guard estimatorMode != oldValue else { return }
            detector.reset(); fixation = .unavailable; spatial.clear()
            receive(lastFace)
        }
    }
    @Published var estimate: GazeEstimate?
    @Published var externalPoint: CGPoint?
    @Published var projectionStatus = "射线交点：未校准"
    @Published var angularRowReport = ""
    @Published var externalStatus = "CNN：请开启 GazeEstimation · Mac 并等待模型就绪"
    private var externalCalibration: AngularGazeCalibration?
    private var externalStabilizer = DebugGazeStabilizer()
    @Published var semanticInputStatus = "等待 CNN 校准与预测"
    private var externalBounds: CGRect?
    var lastExternal: (frame: UInt64, time: TimeInterval, point: CGPoint)?
    @Published var rawAnglesText = "Raw CNN：等待有效角度"
    var lastAngles: (frame: UInt64, time: TimeInterval, pitch: Double, yaw: Double)?
    var lastAngular: (frameID: UInt64, time: TimeInterval, frame: AngularGazeFrame, geometry: DebugScreenGeometry)?

    func receiveExternal(_ note: Notification) {
        if let a = note.userInfo?["angles"] as? [Double], a.count == 2,
           a.allSatisfy(\.isFinite), let frame = note.userInfo?["frameID"] as? UInt64,
           let time = note.userInfo?["hostTime"] as? Double,
           CACurrentMediaTime() >= time, CACurrentMediaTime() - time < 0.5 {
            let pitch = a[0] * 180 / .pi, yaw = a[1] * 180 / .pi
            lastAngles = (frame, time, pitch, yaw)
            rawAnglesText = String(format: "Raw CNN（归一化眼坐标）：pitch %+.1f°  yaw %+.1f°", pitch, yaw)
        } else { lastAngles = nil; rawAnglesText = "Raw CNN：等待有效角度" }
        guard let angles = note.userInfo?["angles"] as? [Double], angles.count == 2,
              let eye = note.userInfo?["eyeCenter"] as? [Double], eye.count == 3,
              let rotation = note.userInfo?["eyeRotation"] as? [Double], rotation.count == 9,
              let screen = note.userInfo?["screenGeometry"] as? [Double], screen.count == 4,
              let frameID = note.userInfo?["frameID"] as? UInt64,
              let time = note.userInfo?["hostTime"] as? Double,
              angles.allSatisfy(\.isFinite), eye.allSatisfy(\.isFinite), rotation.allSatisfy(\.isFinite), screen.allSatisfy(\.isFinite),
              CACurrentMediaTime() >= time, CACurrentMediaTime() - time < 0.5 else {
            lastAngular = nil; lastExternal = nil; externalPoint = nil; projectionStatus = "射线交点：等待有效输入"; externalStabilizer.reset(); updateSemantic(nil, time: CACurrentMediaTime(), reason: "眼部帧无效或超时"); return
        }
        let frame = AngularGazeFrame(pitch: angles[0], yaw: angles[1], eye: SIMD3(eye[0],eye[1],eye[2]), rotation: rotation)
        let geometry = DebugScreenGeometry(width: screen[0], height: screen[1], offsetX: screen[2], offsetY: screen[3])
        lastAngular = (frameID, time, frame, geometry)
        guard let calibration = externalCalibration, let bounds = externalBounds else {
            externalPoint = nil; projectionStatus = "射线交点：尚未校准"; updateSemantic(nil, time: time, reason: "CNN 角度未校准"); return
        }
        guard bounds == CGDisplayBounds(CGMainDisplayID()) else {
            externalPoint = nil; projectionStatus = "射线交点：屏幕变化"; updateSemantic(nil, time: time, reason: "屏幕变化，需重新校准"); return
        }
        guard let output = calibration.project(frame) else {
            externalPoint = nil; projectionStatus = "射线交点：不可用"; updateSemantic(nil, time: time, reason: "校准射线无效"); return
        }
        projectionStatus = String(format: "射线交点（未截断）X %.2f  Y %.2f", output.x, output.y)
        // Do not paint an off-screen or invalid intersection as a screen-edge hit.
        guard (0...1).contains(output.x), (0...1).contains(output.y) else {
            externalPoint = nil; projectionStatus += "（屏幕外）"; externalStabilizer.reset(); updateSemantic(nil, time: time, reason: String(format: "射线在屏幕外 X %.2f Y %.2f", output.x, output.y)); return
        }
        externalPoint = externalStabilizer.update(output, timestamp: time)
        guard let smoothed = externalPoint else { updateSemantic(nil, time: time); return }
        let screenPoint = CGPoint(x: bounds.minX + smoothed.x * bounds.width, y: bounds.minY + smoothed.y * bounds.height)
        updateSemantic(screenPoint, time: time)
    }
    private func updateSemantic(_ point: CGPoint?, time: TimeInterval, reason: String? = nil) {
        guard AccessibilityTargetResolver.shared.isEnabled else { semanticInputStatus = "OFF"; return }
        if let point { semanticInputStatus = String(format: "平滑注视 %.0f, %.0f", point.x, point.y) }
        else { semanticInputStatus = reason ?? "等待有效 CNN 帧" }
        AccessibilityTargetResolver.shared.update(point, timestamp: time)
    }
    func expireExternal() { externalPoint = nil; lastExternal = nil; lastAngular = nil; externalStabilizer.reset(); updateSemantic(nil, time: CACurrentMediaTime()) }
    func beginExternal() {
        externalCalibration = nil; externalPoint = nil; angularRowReport = ""; externalStabilizer.reset(); externalStatus = "CNN 角度九点校准中"
    }
    func finishExternal(_ samples: [AngularGazeCalibration.Sample], geometry: DebugScreenGeometry, bounds: CGRect) throws {
        externalStabilizer.reset()
        let model = try AngularGazeCalibration.fit(samples, geometry: geometry)
        let errors = samples.compactMap { sample -> (Double, Double)? in
            guard let p = model.project(sample.frame) else { return nil }
            return (abs(p.x - sample.target.x), abs(p.y - sample.target.y))
        }
        guard errors.count == samples.count else { throw AngularGazeCalibration.Error.invalidData }
        let x = errors.reduce(0) { $0 + $1.0 } / Double(errors.count)
        let y = errors.reduce(0) { $0 + $1.1 } / Double(errors.count)
        let rows = [0.12, 0.50, 0.88].map { targetY -> String in
            let row = samples.filter { abs($0.target.y - targetY) < 0.001 }
            let values = row.compactMap { model.project($0.frame)?.y }
            guard !values.isEmpty else { return "—" }
            return String(format: "目标 %.2f → %.2f (%d帧)", targetY, values.reduce(0, +) / Double(values.count), values.count)
        }
        angularRowReport = "校准样本上下行（拟合内）：" + rows.joined(separator: "；")
        externalCalibration = model; externalBounds = bounds
        externalStatus = String(format: "CNN 角度校准完成；拟合误差 X %.1f%% Y %.1f%%（非独立验证）；屏幕 %.0f×%.0f mm 为估计值", 100*x, 100*y, geometry.width, geometry.height)
    }
    @Published var gazeDiagnostics = "Iris Base: —   Head correction: —   Final: —"
    @Published var fixation: FixationState = .unavailable
    @Published private(set) var spatial = HeadCenteredTargeting()
    @Published var status = "请先进行九点校准"
    private var detector = FixationDetector()
    private var calibratedMirroring: Bool?
    private var calibratedBounds: CGRect?
    private var window: NSWindow?
    private let windowDelegate = GazeCalibrationWindowDelegate()
    var lastFace: FaceSample?

    func receive(_ face: FaceSample?) {
        lastFace = face
        guard let face, let calibration, let mirrored = calibratedMirroring, let bounds = calibratedBounds,
              mirrored == face.isMirrored, bounds == CGDisplayBounds(CGMainDisplayID()),
              CACurrentMediaTime() >= face.timestamp, CACurrentMediaTime() - face.timestamp < 0.3 else {
            estimate = nil; fixation = detector.update(nil)
            gazeDiagnostics = "Iris Base: —   Head correction: —   Final: —"
            spatial.update(face: face, gaze: nil, fixation: fixation, displayBounds: CGDisplayBounds(CGMainDisplayID()), now: CACurrentMediaTime())
            return
        }
        let value = GazeEstimator.estimate(face: face, calibration: calibration, displayBounds: bounds, mode: estimatorMode)
        if let value, let features = EyeFeatureExtractor.extract(face),
           let components = GazeEstimator.normalizedComponents(features: features, calibration: calibration, mode: estimatorMode) {
            let correction = components.headCorrection.map { String(format: "%+.3f, %+.3f", $0.x, $0.y) } ?? "— (Legacy)"
            let nx = (value.screenPoint.x - bounds.minX) / bounds.width
            let ny = (value.screenPoint.y - bounds.minY) / bounds.height
            gazeDiagnostics = String(format: "Iris Base: %.3f, %.3f   Head correction: %@   Final: %.3f, %.3f", components.irisBase.x, components.irisBase.y, correction, nx, ny)
        } else { gazeDiagnostics = "Iris Base: —   Head correction: —   Final: —" }
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
        AccessibilityTargetResolver.shared.setSuspended(true)
        // Let an already-running, bounded AX hit test return before the
        // full-screen SwiftUI window becomes visible to the AX server.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.showAfterAXPause() }
    }
    private func showAfterAXPause() {
        let mainID = CGMainDisplayID()
        guard let screen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == mainID }) ?? NSScreen.main else { return }
        if let existing = window { existing.makeKeyAndOrderFront(nil); return }
        let panel = NSWindow(contentRect: screen.frame, styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false, screen: screen)
        panel.isReleasedWhenClosed = false
        windowDelegate.onClose = { [weak self] in self?.close() }
        panel.delegate = windowDelegate
        panel.level = .statusBar
        panel.backgroundColor = .black
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.contentView = NSHostingView(rootView: GazeCalibrationView(controller: self, close: { [weak self] in self?.close() }))
        window = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    private func close() { window?.orderOut(nil); window = nil; AccessibilityTargetResolver.shared.setSuspended(false) }
}

private struct GazeCalibrationView: View {
    @ObservedObject var controller: GazeDebugController
    let close: () -> Void
    @State private var active = false
    @State private var runningBenchmark = false
    @State private var runningDirection = false
    @State private var directionStep = 0
    @State private var directionBucket: [(Double, Double)] = []
    @State private var directionResults: [(Double, Double, Double, Double)] = []
    @State private var directionReport: String?
    private let directionIndices = [3, 4, 5, 1, 4, 7]
    private let directionNames = ["LEFT", "CENTER", "RIGHT", "UP", "CENTER", "DOWN"]
    @State private var runningExternal = false
    @State private var externalBucket: [AngularGazeFrame] = []
    @State private var angularSamples: [AngularGazeCalibration.Sample] = []
    @State private var angularGeometry: DebugScreenGeometry?
    @State private var benchmark = IrisSeparabilityBenchmark()
    @State private var benchmarkTargetHostTime: TimeInterval = 0
    @State private var benchmarkReport: String?
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
                if !runningBenchmark && !runningDirection && directionReport == nil, let point = controller.externalPoint, !active {
                    Image(systemName: "xmark").font(.system(size: 22, weight: .bold)).foregroundColor(.green)
                        .position(x: point.x * geo.size.width, y: point.y * geo.size.height)
                }
                if !runningBenchmark && !runningDirection && directionReport == nil, let gaze = controller.estimate {
                    let x = (gaze.screenPoint.x - bounds.minX) / bounds.width * geo.size.width
                    let y = (gaze.screenPoint.y - bounds.minY) / bounds.height * geo.size.height
                    Image(systemName: "xmark").font(.system(size: 20, weight: .bold)).foregroundColor(.cyan)
                        .position(x: x, y: y)
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Button(active ? "校准中…" : "开始九点校准") { start() }.disabled(active)
                        Button("CNN 角度九点校准") { startExternal() }.disabled(active)
                        Button("CNN 方向诊断") { startDirection() }.disabled(active)
                        Button("320/640 虹膜基准") { startBenchmark() }.disabled(active)
                        Button("关闭") {
                            if runningBenchmark { FaceInferenceWorker.shared.setIrisBenchmarkEnabled(false) }
                            else if active { controller.cancel() }
                            runningBenchmark = false; active = false; close()
                        }
                        Text(controller.status).foregroundColor(.white.opacity(0.8))
                    }
                    if !active {
                        HStack {
                            Text("Gaze Mode:").foregroundColor(.white)
                            Picker("Gaze Mode", selection: $controller.estimatorMode) {
                                Text("Legacy").tag(GazeEstimatorMode.legacyFullFeature)
                                Text("Iris").tag(GazeEstimatorMode.irisDominant)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 150)
                        }
                        Text(controller.rawAnglesText).foregroundColor(.yellow).font(.system(size: 13, design: .monospaced))
                        if runningDirection || directionReport != nil {
                            Text(runningDirection ? "Looking: \(directionNames[directionStep])" : "方向采样完成").foregroundColor(.yellow)
                            if let directionReport { Text(directionReport).foregroundColor(.cyan).font(.system(size: 12, design: .monospaced)).textSelection(.enabled) }
                        } else {
                            Text(controller.externalStatus + "；绿色 × 为 CNN 预测").foregroundColor(.green)
                            Text(controller.projectionStatus).foregroundColor(.white.opacity(0.85))
                            if !controller.angularRowReport.isEmpty { Text(controller.angularRowReport).foregroundColor(.cyan) }
                        }
                        if !runningDirection && directionReport == nil {
                            Text(controller.gazeDiagnostics).foregroundColor(.white.opacity(0.85))
                                .font(.system(size: 12, design: .monospaced))
                        }
                    } else if runningDirection {
                        Text(controller.rawAnglesText).foregroundColor(.yellow).font(.system(size: 13, design: .monospaced))
                    }
                    Text(message).foregroundColor(.white)
                    if let benchmarkReport {
                        Text(benchmarkReport).foregroundColor(.cyan)
                            .font(.system(size: 13, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(24)
            }
        }
        .onReceive(timer) { now in tick(now) }
        .onReceive(NotificationCenter.default.publisher(for: FaceInferenceWorker.notification)) { note in
            guard active, runningBenchmark, let frame = note.userInfo?["irisBenchmark"] as? IrisBenchmarkFrame,
                  frame.timestamp >= benchmarkTargetHostTime + 0.7 else { return }
            benchmark.append(frame, target: index)
        }
        .onDisappear {
            if runningBenchmark { FaceInferenceWorker.shared.setIrisBenchmarkEnabled(false) }
        }
    }
    private func startDirection() {
        runningBenchmark = false; runningExternal = false; runningDirection = true
        directionStep = 0; directionBucket = []; directionResults = []; directionReport = nil
        lastFrame = nil; index = directionIndices[0]; pointStart = Date(); active = true
        message = "固定头部，注视黄色目标：LEFT；采样后自动切换。"
    }
    private func startExternal() {
        runningDirection = false; directionReport = nil
        controller.beginExternal(); runningBenchmark = false; runningExternal = true
        bounds = CGDisplayBounds(CGMainDisplayID()); samples = []; angularSamples = []; angularGeometry = nil; externalBucket = []
        index = 0; lastFrame = nil; pointStart = Date(); active = true
        message = "CNN 角度校准 1/9：请注视黄色圆点；等待模型与摄像头就绪。"
    }
    private func startBenchmark() {
        runningDirection = false; directionReport = nil
        runningExternal = false
        benchmark = IrisSeparabilityBenchmark(); benchmarkReport = nil
        samples = []; bucket = []; index = 0; pointStart = Date(); benchmarkTargetHostTime = CACurrentMediaTime()
        runningBenchmark = true; active = true
        FaceInferenceWorker.shared.setIrisBenchmarkEnabled(true)
        message = "基准 1/9：保持头部稳定，注视黄色圆点。每帧同时比较 320 与 640。"
    }
    private func start() {
        runningDirection = false; directionReport = nil
        runningBenchmark = false; runningExternal = false
        controller.begin(); bounds = CGDisplayBounds(CGMainDisplayID())
        samples = []; bucket = []; index = 0; lastFrame = nil; lastGoodTime = nil; mirror = nil
        pointStart = Date(); active = true
        message = "请注视黄色圆点，保持头部稳定。"
    }
    private func formatBenchmark(_ r: IrisBenchmarkReport) -> String {
        func line(_ name: String, _ m: IrisSeparabilityMetrics) -> String {
            let ratio = m.separationRatio.map { String(format: "%.2f", $0) } ?? "—"
            return String(format: "%@: 点内 RMS %.4f  最小中心间距 %.4f  间距/噪声 %@  分时准确率 %.1f%%", name, m.withinTargetRMS, m.minimumCentroidDistance, ratio, m.heldOutAccuracy * 100)
        }
        let fps = r.pairedFPS.map { String(format: "%.1f", $0) } ?? "—"
        let pose = r.headPoseSpanDegrees.map { String(format: "yaw/pitch/roll %.1f° / %.1f° / %.1f°", $0[0], $0[1], $0[2]) } ?? "无数据"
        return "成对有效/尝试：\(r.validPairs)/\(r.attemptedPairs)；成对 FPS：\(fps)；平均推理：320 \(String(format: "%.1f", r.meanInferenceMs320)) ms / 640 \(String(format: "%.1f", r.meanInferenceMs640)) ms\n头姿变化范围：\(pose)\n" +
            [line("原始 320", r.raw320), line("原始 640", r.raw640), line("眼内归一化 320", r.normalized320), line("眼内归一化 640", r.normalized640)].joined(separator: "\n")
    }
    private func saveBenchmark(_ report: IrisBenchmarkReport) throws -> String {
        guard let script = ProcessInfo.processInfo.environment["AURAMOTION_FACE_SCRIPT"] else { throw CocoaError(.fileNoSuchFile) }
        let root = URL(fileURLWithPath: script).deletingLastPathComponent().deletingLastPathComponent()
        let folder = root.appendingPathComponent("build/iris-benchmarks", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let path = folder.appendingPathComponent("iris-\(UUID().uuidString).json")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: path, options: .atomic)
        return path.path
    }

    private func tick(_ now: Date) {
        if let raw = controller.lastAngular, CACurrentMediaTime() - raw.time > 0.5 { controller.expireExternal() }
        if let angles = controller.lastAngles, CACurrentMediaTime() - angles.time > 0.5 {
            controller.lastAngles = nil; controller.rawAnglesText = "Raw CNN：等待有效角度"
        }
        guard active else { return }
        let elapsed = now.timeIntervalSince(pointStart)
        if runningDirection {
            if elapsed >= 0.8, let raw = controller.lastAngles, raw.frame != lastFrame,
               CACurrentMediaTime() >= raw.time, CACurrentMediaTime() - raw.time < 0.5 {
                lastFrame = raw.frame; directionBucket.append((raw.pitch, raw.yaw))
            }
            guard elapsed >= 2.5 else { return }
            guard directionBucket.count >= 5 else {
                message = "等待有效 CNN 角度：请保持双眼可见，注视 \(directionNames[directionStep])。"; return
            }
            func median(_ values: [Double]) -> Double {
                let sorted = values.sorted(), n = values.count
                return n % 2 == 1 ? sorted[n / 2] : (sorted[n / 2 - 1] + sorted[n / 2]) / 2
            }
            let pitch = directionBucket.map { $0.0 }, yaw = directionBucket.map { $0.1 }
            let p = median(pitch), y = median(yaw)
            directionResults.append((p, y, median(pitch.map { abs($0 - p) }), median(yaw.map { abs($0 - y) })))
            directionBucket = []; directionStep += 1; pointStart = now
            if directionStep == directionIndices.count {
                active = false; runningDirection = false; index = 4
                directionReport = zip(directionNames, directionResults).map { name, value in
                    String(format: "%@: pitch %+.1f° ±%.1f  yaw %+.1f° ±%.1f", name, value.0, value.2, value.1, value.3)
                }.joined(separator: "\n") + "\n± 为点内角度中位绝对偏差；请比较 yaw 左/中/右、pitch 上/中/下。"
                message = "方向诊断完成；显示归一化眼坐标中的原始 CNN 输出，并未判定准确度。"
            } else {
                index = directionIndices[directionStep]
                message = "固定头部，注视黄色目标：\(directionNames[directionStep])；采样后自动切换。"
            }
            return
        }
        if runningExternal {
            if elapsed >= 1.0, let raw = controller.lastAngular, raw.frameID != lastFrame,
               CACurrentMediaTime() >= raw.time, CACurrentMediaTime() - raw.time < 0.5 {
                lastFrame = raw.frameID; externalBucket.append(raw.frame); angularGeometry = raw.geometry
            }
            guard elapsed >= 2.6 else { return }
            guard externalBucket.count >= 5 else {
                message = "CNN 角度校准 \(index + 1)/9：等待有效眼部姿态，请保持双眼可见。"; return
            }
            let target = GazeCalibration.nineTargets[index]
            angularSamples.append(contentsOf: externalBucket.map { AngularGazeCalibration.Sample(frame: $0, target: target) })
            externalBucket = []; index += 1; pointStart = now
            if index == 9 {
                active = false; runningExternal = false; index = 4
                do {
                    guard let geometry = angularGeometry else { throw AngularGazeCalibration.Error.invalidData }
                    try controller.finishExternal(angularSamples, geometry: geometry, bounds: bounds)
                    message = "角度校准完成：绿色 × 为射线与屏幕交点；注视九点检查。"
                } catch {
                    message = "CNN 角度校准失败：角度变化不足或数据无效，请重新校准。"
                    controller.externalStatus = "CNN 角度校准失败"
                }
            } else { message = "CNN 角度校准 \(index + 1)/9：请注视黄色圆点。" }
            return
        }
        if runningBenchmark {
            guard elapsed >= 1.6 else { return }
            guard benchmark.validCount(target: index) >= 6 else {
                message = "基准 \(index + 1)/9：有效成对帧不足，请注视圆点并保持双眼可见。"
                return
            }
            index += 1; pointStart = now; benchmarkTargetHostTime = CACurrentMediaTime()
            if index == 9 {
                active = false; runningBenchmark = false
                FaceInferenceWorker.shared.setIrisBenchmarkEnabled(false)
                index = 4
                do {
                    let report = try benchmark.report()
                    let path = try saveBenchmark(report)
                    benchmarkReport = formatBenchmark(report) + "\n已保存：\(path)"
                    message = "基准完成：仅为一次九点采样；请勿把这当作独立试次的精度。"
                } catch IrisSeparabilityBenchmark.Error.sourceTooSmall {
                    message = "基准失败：摄像头原始画面不足 640 像素，无法公平比较。"
                } catch { message = "基准失败：有效成对数据不足或无法保存结果。" }
            } else { message = "基准 \(index + 1)/9：保持头部稳定，注视黄色圆点。" }
            return
        }
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
