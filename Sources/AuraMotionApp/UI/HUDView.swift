import SwiftUI
import AVFoundation
import AuraMotionCore

public struct HUDView: View {
    @ObservedObject private var localization = AppLocalization.shared
    @State private var snapshot: HUDSnapshot?
    #if DEBUG
    @ObservedObject private var gazeController = GazeDebugController.shared
    @State private var showAuraMotion = true
    @State private var showMediaPipe = true
    @State private var showExternalGaze = true
    @State private var semanticEnabled = false
    @State private var semanticStatus = "OFF"
    @State private var externalGazeStatus = "启动中"
    @State private var externalLeft: NSImage?
    @State private var externalRight: NSImage?
    @State private var externalLastUpdate: Date?
    @State private var externalFPS: Double?
    @State private var faceSample: FaceSample?
    @State private var faceStatus = "Starting"
    @State private var showCamera = false
    @State private var faceFPS: Double?
    @State private var faceLastUpdate: Date?
    @State private var fpsClock = Date()
    #endif
    @State private var isCompact = false
    @State private var showJointNumbers = AppEnvironment.shared.currentSettings.hudShowsJointNumbers
    @State private var highlightFirstRing = AppEnvironment.shared.currentSettings.hudHighlightFirstRing
    @State private var previewMirrored = AppEnvironment.shared.currentSettings.hudPreviewMirrored
    @State private var skeletonScale = AppEnvironment.shared.currentSettings.hudSkeletonScale
    @State private var pendingScaleSave: DispatchWorkItem?
    @State private var resizeStartMouse: CGPoint?
    @State private var moveStartMouse: CGPoint?
    private let onResize: (CGSize, Bool) -> Void
    private let onMove: (CGSize, Bool) -> Void
    private let onRestoreSize: () -> Void

    public init(onResize: @escaping (CGSize, Bool) -> Void = { _, _ in },
                onMove: @escaping (CGSize, Bool) -> Void = { _, _ in },
                onRestoreSize: @escaping () -> Void = {}) {
        self.onResize = onResize
        self.onMove = onMove
        self.onRestoreSize = onRestoreSize
    }

    public var body: some View {
        VStack(spacing: 8) {
            // Header Bar
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text("AuraMotion Pro")
                    .font(.system(size: 16.5, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))

                Spacer()

                Button {
                    highlightFirstRing.toggle()
                    AppEnvironment.shared.updateHUDJointDisplay(highlightFirstRing: highlightFirstRing)
                } label: {
                    Text(L10n.tr("First Ring"))
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(highlightFirstRing ? .red : .white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.tr("Highlight first ring in red above other nodes"))
                .accessibilityValue(highlightFirstRing ? L10n.tr("On") : L10n.tr("Off"))

                Button(action: { isCompact.toggle() }) {
                    Image(systemName: isCompact ? "chevron.down" : "chevron.up")
                        .font(.system(size: 13.5))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .overlay(alignment: .leading) {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 2)
                        .onChanged { _ in moveChanged() }
                        .onEnded { _ in moveStartMouse = nil; onMove(.zero, true) })
                    .simultaneousGesture(TapGesture(count: 2).onEnded { onRestoreSize() })
                    .padding(.trailing, 80)
            }

            // Status Pill
            HStack {
                Text(L10n.tr(snapshot?.feedback ?? snapshot?.state.displayName ?? "INITIALIZING"))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.25))
                    .foregroundColor(statusColor)
                    .cornerRadius(6)

                Spacer()

                if let p95 = snapshot?.performance.inferenceDurationP95Ms {
                    Text(String(format: "%.1f ms", p95))
                        .font(.system(size: 13.5, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .padding(.horizontal, 10)

            #if DEBUG
            HStack(spacing: 6) {
                Button { showAuraMotion.toggle() } label: {
                    Text("AuraMotion · Hand")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .foregroundColor(showAuraMotion ? .cyan : .gray)
                        .background(Color.white.opacity(showAuraMotion ? 0.16 : 0.05), in: Capsule())
                }.buttonStyle(.plain).accessibilityValue(showAuraMotion ? "On" : "Off")
                Button {
                    showMediaPipe.toggle()
                    FaceInferenceWorker.shared.setEnabled(showMediaPipe)
                    if !showMediaPipe { faceSample = nil; faceStatus = "Off"; faceFPS = nil; faceLastUpdate = nil; GazeDebugController.shared.receive(nil) }
                } label: {
                    Text("MediaPipe · Face")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .foregroundColor(showMediaPipe ? .green : .gray)
                        .background(Color.white.opacity(showMediaPipe ? 0.16 : 0.05), in: Capsule())
                }.buttonStyle(.plain).accessibilityValue(showMediaPipe ? "On" : "Off")
            }.padding(.horizontal, 6)
            #endif

            #if DEBUG
            HStack {
                Button {
                    showExternalGaze.toggle()
                    ExperimentalGazeEstimationWorker.shared.setEnabled(showExternalGaze)
                    externalGazeStatus = showExternalGaze ? "启动中" : "未开启"
                    externalLeft = nil; externalRight = nil; externalLastUpdate = nil; externalFPS = nil
                    if !showExternalGaze { GazeDebugController.shared.expireExternal() }
                } label: {
                    Text("GazeEstimation · Mac")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .foregroundColor(showExternalGaze ? .green : .white.opacity(0.65))
                        .background(Color.white.opacity(showExternalGaze ? 0.16 : 0.07), in: Capsule())
                }.buttonStyle(.plain).accessibilityValue(showExternalGaze ? "On" : "Off")
                Button {
                    semanticEnabled.toggle()
                    AccessibilityTargetResolver.shared.setEnabled(semanticEnabled)
                } label: {
                    Text("AX Target · \(semanticEnabled ? "ON" : "OFF")")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .foregroundColor(semanticEnabled ? .cyan : .gray)
                        .background(Color.white.opacity(0.1), in: Capsule())
                }.buttonStyle(.plain).accessibilityValue(semanticEnabled ? "On" : "Off")
                Spacer()
            }.padding(.horizontal, 10)
            if semanticEnabled {
                Text("AX Targeting: \(semanticStatus)\n\(gazeController.semanticInputStatus)").font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.cyan).padding(.horizontal, 10).frame(maxWidth: .infinity, alignment: .leading)
            }
            #endif
            HStack {
                Button { AppEnvironment.shared.toggleGestureClickAndMenu() } label: {
                    Text(L10n.tr("Gesture Click & Menu"))
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .foregroundColor(snapshot?.isGestureClickAndMenuEnabled == true ? .cyan : .white.opacity(0.65))
                        .background(Color.white.opacity(snapshot?.isGestureClickAndMenuEnabled == true ? 0.16 : 0.07), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityValue(snapshot?.isGestureClickAndMenuEnabled == true ? L10n.tr("On") : L10n.tr("Off"))
                Spacer()
            }.padding(.horizontal, 10)

            if !isCompact {
                HStack(alignment: .top, spacing: 4) {
                    Text(effectiveCursorStrategyLabel)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 2)
                    Text(effectiveProviderLabel)
                        .lineLimit(1)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.62))
                .padding(.horizontal, 10)

                #if DEBUG
                HStack {
                    Button("视线校准") { GazeDebugController.shared.show() }
                        .buttonStyle(.plain).font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.yellow)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.white.opacity(0.08), in: Capsule())
                    Button { showCamera.toggle() } label: {
                        Text(L10n.tr("Camera Preview"))
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .foregroundColor(showCamera ? .cyan : .white.opacity(0.7))
                            .background(Color.white.opacity(showCamera ? 0.16 : 0.07), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(showCamera ? L10n.tr("On") : L10n.tr("Off"))
                    Spacer()
                }.padding(.horizontal, 10)
                #endif
                HStack(spacing: 6) {
                    Button {
                        previewMirrored.toggle()
                        AppEnvironment.shared.updateHUDJointDisplay(previewMirrored: previewMirrored)
                    } label: {
                        Text(L10n.tr("Preview Mirror"))
                            .font(.system(size: 13.5, weight: .semibold))
                            .fixedSize(horizontal: true, vertical: false)
                            .foregroundColor(previewMirrored ? .cyan : .white.opacity(0.7))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(previewMirrored ? 0.16 : 0.07), in: RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    .disabled(!cameraPreviewEnabled)
                    .accessibilityValue(previewMirrored ? L10n.tr("On") : L10n.tr("Off"))

                    Button {
                        showJointNumbers.toggle()
                        AppEnvironment.shared.updateHUDJointDisplay(showNumbers: showJointNumbers)
                    } label: {
                        Text(L10n.tr("Joint Numbers"))
                            .font(.system(size: 13.5, weight: .semibold))
                            .fixedSize(horizontal: true, vertical: false)
                            .foregroundColor(showJointNumbers ? .cyan : .white.opacity(0.7))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(showJointNumbers ? 0.16 : 0.07), in: RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(showJointNumbers ? L10n.tr("On") : L10n.tr("Off"))

                    Slider(value: $skeletonScale, in: 0.5...3, step: 0.1)
                        .controlSize(.mini)
                        .accessibilityLabel(L10n.tr("Skeleton Size"))
                    Text(String(format: "%.1f×", skeletonScale))
                        .font(.system(size: 13.5, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.horizontal, 10)

                if snapshot?.isVisionReconfigurationPending == true {
                    Text(L10n.tr("Reconfiguring vision provider…"))
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.55))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                }

                // Live Hand Skeleton Canvas
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.4))

                    if snapshot?.showHUD == true && cameraPreviewEnabled {
                        CameraPreviewView(
                            session: AppEnvironment.shared.capturePipeline.previewSession,
                            isMirrored: ((snapshot?.isCameraMirrored ?? true) == (snapshot?.isVideoDataMirrored ?? false)) != previewMirrored
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    #if DEBUG
                    if showMediaPipe {
                        FaceLandmarksView(points: faceSample?.landmarks ?? [], flipHorizontally: faceOverlayMirrored)
                            .allowsHitTesting(false)
                        if cameraPreviewEnabled, let face = faceSample, let pose = face.headPose,
                           gazeController.lastFace?.frameID == face.frameID {
                            HeadCenteredRegionOverlay(center: CGPoint(x: faceOverlayMirrored ? 1 - CGFloat(pose.centerX) : CGFloat(pose.centerX), y: CGFloat(pose.centerY)),
                                                      focused: gazeController.spatial.focused, candidate: gazeController.spatial.candidate)
                                .allowsHitTesting(false)
                        }
                    }
                    #endif
                    if let sample = snapshot?.sample, handOverlayEnabled {
                        SkeletonView(sample: sample, showNumbers: showJointNumbers,
                                     scale: skeletonScale,
                                     flipHorizontally: cameraPreviewEnabled && !previewMirrored,
                                     highlightFirstRing: highlightFirstRing)
                            .allowsHitTesting(false)
                    } else if handOverlayEnabled {
                        VStack(spacing: 4) {
                            Image(systemName: "hand.raised.slash")
                                .font(.system(size: 30))
                                .foregroundColor(.white.opacity(0.3))
                            Text(L10n.tr("No Hand Detected"))
                                .font(.system(size: 15))
                                .foregroundColor(.white.opacity(0.4))
                        }
                    }
                }
                .aspectRatio(snapshot?.cameraAspectRatio ?? (16.0 / 9.0), contentMode: .fit)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)

                #if DEBUG
                if showExternalGaze {
                    HStack(spacing: 8) {
                        if let left = externalLeft {
                            VStack(spacing: 2) {
                                Text("图像左眼").font(.system(size: 9)).foregroundColor(.white.opacity(0.7))
                                Image(nsImage: left).resizable().interpolation(.none).frame(width: 120, height: 72)
                            }
                        }
                        if let right = externalRight {
                            VStack(spacing: 2) {
                                Text("图像右眼").font(.system(size: 9)).foregroundColor(.white.opacity(0.7))
                                Image(nsImage: right).resizable().interpolation(.none).frame(width: 120, height: 72)
                            }
                        }
                        Text(externalGazeStatus).font(.system(size: 11)).foregroundColor(.white.opacity(0.8))
                        Spacer(minLength: 0)
                    }.padding(.horizontal, 10)
                }
                #endif
                #if DEBUG
                if cameraPreviewEnabled && showMediaPipe {
                    Text(spatialDiagnosticsLabel)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                }
                if gazeController.calibration != nil {
                    Text(gazeFixationLabel)
                        .font(.system(size: 10)).foregroundColor(.yellow.opacity(0.85))
                }
                if showMediaPipe {
                    Text("MediaPipe Face: " + faceStatus)
                        .font(.system(size: 10)).foregroundColor(.white.opacity(0.65))
                }
                #endif
                #if DEBUG
                HStack(spacing: 12) {
                    MetricLabel(title: "AuraMotion FPS", value: String(format: "%.1f", snapshot?.performance.inferenceFPS ?? 0))
                    MetricLabel(title: "MediaPipe FPS", value: faceFPSLabel)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                #endif
                // Telemetry Footer
                HStack(spacing: 12) {
                    MetricLabel(title: L10n.tr("CAP"), value: String(format: "%.0f", snapshot?.performance.captureFPS ?? 0))
                    MetricLabel(title: L10n.tr("INF"), value: String(format: "%.0f", snapshot?.performance.inferenceFPS ?? 0))
                    MetricLabel(title: L10n.tr("DROP"), value: "\(snapshot?.performance.droppedFrames ?? 0)")
                    Spacer()
                    if let permissionLabel = snapshot?.permissions.compactStatusLabel {
                        Text(L10n.tr(permissionLabel))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.orange)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.leading, 18)
                .padding(.bottom, 8)
            }
        }
        .frame(minWidth: 220, maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
        .overlay(alignment: .bottomLeading) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.65))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
                .accessibilityLabel(L10n.tr("Drag to resize"))
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { _ in resizeChanged() }
                    .onEnded { _ in resizeStartMouse = nil; onResize(.zero, true) })
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("HUDSnapshotUpdated")).receive(on: DispatchQueue.main)) { note in
            if let snap = note.object as? HUDSnapshot {
                self.snapshot = snap
            }
        }
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: ExperimentalGazeEstimationWorker.notification)) { note in
            guard showExternalGaze else { return }
            // AX point queries must never hit AuraMotion's own interactive
            // windows. Convert their frames from AppKit to Quartz coordinates.
            if let main = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == CGMainDisplayID() }) {
                let bounds = CGDisplayBounds(CGMainDisplayID())
                let frames = NSApp.windows.filter { $0.isVisible && !$0.ignoresMouseEvents }.map { window in
                    let f = window.frame
                    return CGRect(x: bounds.minX + f.minX - main.frame.minX,
                                  y: bounds.minY + main.frame.maxY - f.maxY, width: f.width, height: f.height)
                }
                AccessibilityTargetResolver.shared.setExcludedFrames(frames)
            }
            GazeDebugController.shared.receiveExternal(note)
            let status = note.userInfo?["status"] as? String ?? "Unavailable"
            let modelLoaded = note.userInfo?["modelLoaded"] as? Bool ?? false
            func image(_ key: String) -> NSImage? {
                guard let encoded = note.userInfo?[key] as? String, let data = Data(base64Encoded: encoded) else { return nil }
                return NSImage(data: data)
            }
            externalLeft = image("leftPatch"); externalRight = image("rightPatch")
            externalFPS = note.userInfo?["fps"] as? Double
            externalLastUpdate = Date()
            let fps = externalFPS.map { String(format: " %.1f FPS", $0) } ?? ""
            if status == "preview" { externalGazeStatus = modelLoaded ? "眼部预览，模型已加载" + fps : "眼部预览，缺少训练权重" + fps }
            else if status == "uncalibrated_gaze", let gaze = note.userInfo?["gaze"] as? [Double], gaze.count == 2 {
                externalGazeStatus = String(format: "未校准预测 %.2f, %.2f%@", gaze[0], gaze[1], fps)
            } else if status == "no_face" { externalGazeStatus = "未检测到有效双眼" + fps }
            else if status == "normalization_failed" { externalGazeStatus = "眼部归一化不可用" + fps }
            else if status == "Unavailable" { externalGazeStatus = "不可用：请查看调试日志" }
            else { externalGazeStatus = status + fps }
        }
        .onReceive(NotificationCenter.default.publisher(for: AccessibilityTargetResolver.notification)) { note in
            let state = note.userInfo?["state"] as? String ?? "—"
            if let t = note.userInfo?["target"] as? AccessibilityTargetSnapshot,
               let gaze = note.userInfo?["gaze"] as? CGPoint, let score = note.userInfo?["score"] as? Double,
               let distance = note.userInfo?["distance"] as? CGFloat {
                semanticStatus = String(format: "%@ · %@ · %@\nframe %.0f %.0f %.0f %.0f  gaze %.0f %.0f  dist %.0f score %.1f  %@", state, t.role, t.title ?? "—", t.frame.minX, t.frame.minY, t.frame.width, t.frame.height, gaze.x, gaze.y, distance, score, t.supportsPress ? "AXPress" : "仅高亮")
            } else { semanticStatus = state + " · Target: —" }
        }
        .onReceive(NotificationCenter.default.publisher(for: FaceInferenceWorker.notification)) { note in
            guard showMediaPipe else { return }
            faceSample = note.userInfo?["sample"] as? FaceSample
            GazeDebugController.shared.receive(faceSample)
            faceStatus = note.userInfo?["status"] as? String ?? "Unavailable"
            faceFPS = note.userInfo?["fps"] as? Double
            faceLastUpdate = faceStatus == "Active" || faceStatus == "No face" ? Date() : nil
        }
        .onReceive(Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()) { now in
            fpsClock = now
            if showExternalGaze, let last = externalLastUpdate, now.timeIntervalSince(last) > 0.5 {
                externalLeft = nil; externalRight = nil; externalFPS = nil
                externalGazeStatus = "等待新画面"
                GazeDebugController.shared.expireExternal()
            }
            GazeDebugController.shared.clearIfStale()
        }
        #endif
        .onChange(of: skeletonScale) { _, newValue in
            pendingScaleSave?.cancel()
            let work = DispatchWorkItem { AppEnvironment.shared.updateHUDJointDisplay(scale: newValue) }
            pendingScaleSave = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        }
    }

    #if DEBUG
    // Face coordinates come from the video-data output, while the preview has
    // its own connection. Mirror only when their actual orientations differ.
    private var faceOverlayMirrored: Bool {
        let videoMirrored = snapshot?.isVideoDataMirrored ?? false
        let cameraMirrored = snapshot?.isCameraMirrored ?? true
        guard cameraPreviewEnabled else { return cameraMirrored != videoMirrored }
        let previewConnectionMirrored = (cameraMirrored == videoMirrored) != previewMirrored
        return previewConnectionMirrored != videoMirrored
    }
    #endif

    private var cameraPreviewEnabled: Bool {
        #if DEBUG
        return showCamera
        #else
        return snapshot?.hudShowsCamera == true
        #endif
    }

    #if DEBUG
    private func regionLabel(_ region: FocusedRegion?) -> String {
        guard let region else { return "—" }
        switch region.radial {
        case .center: return "CENTER"
        case .outside: return "—"
        case .ring1, .ring2:
            let labels: [AngularSector: String] = [.north: "N", .northEast: "NE", .east: "E", .southEast: "SE", .south: "S", .southWest: "SW", .west: "W", .northWest: "NW"]
            return "\(region.radial == .ring1 ? "R1" : "R2") · \(region.sector.flatMap { labels[$0] } ?? "—")"
        }
    }
    private var spatialDiagnosticsLabel: String {
        let head: String
        if let pose = gazeController.lastFace?.headPose {
            head = String(format: "Head: %.2f, %.2f  yaw %+.1f° pitch %+.1f° roll %+.1f°", pose.centerX, pose.centerY, pose.yaw * 180 / .pi, pose.pitch * 180 / .pi, pose.roll * 180 / .pi)
        } else { head = "Head: —" }
        let delta: String
        if let face = gazeController.lastFace, let gaze = gazeController.estimate { delta = String(format: "%.1f ms", abs(face.timestamp - gaze.timestamp) * 1000) } else { delta = "—" }
        let stats = gazeController.spatial.diagnostics
        let p50 = stats.ageP50Ms.map { String(format: "%.0f", $0) } ?? "—"
        let p95 = stats.ageP95Ms.map { String(format: "%.0f", $0) } ?? "—"
        let latency = stats.resolveLatencyMs.map { String(format: "%.2f", $0) } ?? "—"
        return "\(head)\n\(gazeFixationLabel)  Region: \(regionLabel(gazeController.spatial.focused))  候选: \(regionLabel(gazeController.spatial.candidate))  Face/Gaze Δ: \(delta)\nGaze: \(String(format: "%.0f", stats.gazeAvailablePercent))%  切换: \(stats.switchCount)  采集→区域 P50/P95: \(p50)/\(p95) ms  计算: \(latency) ms"
    }
    private var gazeFixationLabel: String {
        switch gazeController.fixation {
        case .unavailable: return "注视：不可用"
        case .candidate: return "注视：候选"
        case .focused: return "注视：稳定"
        }
    }
    private var faceFPSLabel: String {
        guard showMediaPipe, let last = faceLastUpdate, fpsClock.timeIntervalSince(last) < 3,
              let fps = faceFPS else { return "—" }
        return String(format: "%.1f", fps)
    }
    #endif

    private var handOverlayEnabled: Bool {
        #if DEBUG
        return showAuraMotion
        #else
        return true
        #endif
    }

    private func resizeChanged() {
        let mouse = NSEvent.mouseLocation
        if resizeStartMouse == nil { resizeStartMouse = mouse; onResize(.zero, false) }
        guard let start = resizeStartMouse else { return }
        onResize(CGSize(width: mouse.x - start.x, height: start.y - mouse.y), false)
    }

    private func moveChanged() {
        let mouse = NSEvent.mouseLocation
        if moveStartMouse == nil { moveStartMouse = mouse; onMove(.zero, false) }
        guard let start = moveStartMouse else { return }
        onMove(CGSize(width: mouse.x - start.x, height: mouse.y - start.y), false)
    }

    private var statusColor: Color {
        guard let state = snapshot?.state else { return .gray }
        switch state {
        case .pointer: return .cyan
        case .pinchArmed: return .yellow
        case .dragging: return .orange
        case .scrolling: return .purple
        case .clutch: return .blue
        case .paused: return .red
        case .trackingLost: return .pink
        case .idle, .scrollCandidate: return .gray
        case .palmCandidate: return .yellow
        case .palmRest: return .teal
        case .palmSwipeLeft, .palmSwipeRight: return .green
        }
    }

    private var effectiveCursorStrategyLabel: String {
        let settings = snapshot?.cursorExperimentSettings ?? CursorExperimentSettings()
        guard settings.hasCursorExperiments else { return L10n.tr("Baseline") }
        let anchor: String
        switch settings.effectiveAnchorStrategy {
        case .legacyTipFusion: anchor = "Legacy Tip Fusion"
        case .indexMCP: anchor = "Index MCP"
        case .palmCentroid: anchor = "Palm Centroid"
        case .palmMCPFusion: anchor = "Palm MCP Fusion"
        }
        let mapping = settings.effectiveMappingMode == .relativeRebased ? "Relative Rebased" : "Absolute Legacy"
        return "\(L10n.tr(anchor)) · \(L10n.tr(mapping))"
    }

    private var effectiveProviderLabel: String {
        let identifier = snapshot?.visionWorkerStatus?.activeProviderIdentifier ?? "vision"
        switch identifier {
        case "mediapipe": return L10n.tr("MediaPipe")
        case "vision": return L10n.tr("Vision")
        default: return identifier
        }
    }
}

/// Displays the existing capture session without adding another camera input or
/// consuming frames from the inference mailbox.
private struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession
    let isMirrored: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspect
        view.layer = preview
        configure(preview)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let preview = view.layer as? AVCaptureVideoPreviewLayer else { return }
        configure(preview)
    }

    static func dismantleNSView(_ view: NSView, coordinator: ()) {
        (view.layer as? AVCaptureVideoPreviewLayer)?.session = nil
    }

    private func configure(_ preview: AVCaptureVideoPreviewLayer) {
        guard let connection = preview.connection, connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = isMirrored
    }
}

struct MetricLabel: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 2) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.4))
            Text(value)
                .font(.system(size: 13.5, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
        }
    }
}

struct SkeletonView: View {
    let sample: HandSample
    let showNumbers: Bool
    let scale: Double
    let flipHorizontally: Bool
    let highlightFirstRing: Bool

    // Bone connections
    private let bones: [(HandJointName, HandJointName)] = [
        (.wrist, .thumbCMC), (.thumbCMC, .thumbMP), (.thumbMP, .thumbIP), (.thumbIP, .thumbTip),
        (.wrist, .indexMCP), (.indexMCP, .indexPIP), (.indexPIP, .indexDIP), (.indexDIP, .indexTip),
        (.wrist, .middleMCP), (.middleMCP, .middlePIP), (.middlePIP, .middleDIP), (.middleDIP, .middleTip),
        (.wrist, .ringMCP), (.ringMCP, .ringPIP), (.ringPIP, .ringDIP), (.ringDIP, .ringTip),
        (.wrist, .littleMCP), (.littleMCP, .littlePIP), (.littlePIP, .littleDIP), (.littleDIP, .littleTip),
        (.indexMCP, .middleMCP), (.middleMCP, .ringMCP), (.ringMCP, .littleMCP)
    ]

    var body: some View {
        GeometryReader { geo in
            Path { path in
                for (fromName, toName) in bones {
                    if let fromPt = sample.joint(fromName, minConfidence: 0.2),
                       let toPt = sample.joint(toName, minConfidence: 0.2) {
                        let p1 = convert(fromPt, size: geo.size)
                        let p2 = convert(toPt, size: geo.size)
                        path.move(to: p1)
                        path.addLine(to: p2)
                    }
                }
            }
            .stroke(
                LinearGradient(
                    colors: [Color.cyan.opacity(0.8), Color.purple.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 2 * scale
            )

            // Landmarks
            ForEach(HandLandmarkRings.second.filter { !highlightFirstRing || !$0.isFirstRing }, id: \.self) { name in
                landmark(name, in: geo.size, highlighted: false)
            }
            if highlightFirstRing {
                ForEach(HandLandmarkRings.first, id: \.self) { name in
                    landmark(name, in: geo.size, highlighted: true)
                }
            }
        }
    }

    @ViewBuilder
    private func landmark(_ name: HandJointName, in size: CGSize, highlighted: Bool) -> some View {
        if let pt = sample.joint(name, minConfidence: 0.25) {
            ZStack {
                Circle()
                    .fill(highlighted ? Color.red : (name == .indexTip || name == .thumbTip ? .yellow : .cyan))
                    .frame(width: (name == .indexTip ? 6 : 4) * scale,
                           height: (name == .indexTip ? 6 : 4) * scale)
                if showNumbers {
                    Text("\(name.landmarkNumber)")
                        .font(.system(size: 13.5 * scale, weight: .bold, design: .monospaced))
                        .foregroundColor(highlighted ? .red : .white)
                        .shadow(color: .black, radius: 2)
                        .fixedSize()
                        .offset(x: 8 * scale, y: -8 * scale)
                }
            }
            .position(convert(pt, size: size))
        }
    }

    private func convert(_ pt: CGPoint, size: CGSize) -> CGPoint {
        // Vision coordinates: [0, 1] bottom-left origin
        return CGPoint(x: (flipHorizontally ? 1 - pt.x : pt.x) * size.width,
                       y: (1.0 - pt.y) * size.height)
    }
}

#if DEBUG
private struct FaceLandmarksView: View {
    let points: [FaceLandmark]
    let flipHorizontally: Bool
    var body: some View {
        Canvas { context, size in
            for point in points {
                let x = CGFloat(flipHorizontally ? 1 - point.x : point.x) * size.width
                let y = CGFloat(point.y) * size.height
                context.fill(Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)), with: .color(.green.opacity(0.8)))
            }
        }
    }
}
#endif
