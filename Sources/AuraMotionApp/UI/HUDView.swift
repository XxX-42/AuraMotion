import SwiftUI
import AVFoundation
import AuraMotionCore

public struct HUDView: View {
    @ObservedObject private var localization = AppLocalization.shared
    @State private var snapshot: HUDSnapshot?
    #if DEBUG
    @State private var showAuraMotion = true
    @State private var showMediaPipe = true
    @State private var facePoints: [[Double]] = []
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
                    DebugFaceWorker.shared.setEnabled(showMediaPipe)
                    if !showMediaPipe { facePoints = []; faceStatus = "Off"; faceFPS = nil; faceLastUpdate = nil }
                } label: {
                    Text("MediaPipe · Face")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .foregroundColor(showMediaPipe ? .green : .gray)
                        .background(Color.white.opacity(showMediaPipe ? 0.16 : 0.05), in: Capsule())
                }.buttonStyle(.plain).accessibilityValue(showMediaPipe ? "On" : "Off")
            }.padding(.horizontal, 6)
            #endif

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
                        FaceLandmarksView(points: facePoints, flipHorizontally: faceOverlayMirrored)
                            .allowsHitTesting(false)
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
        .onAppear { DebugFaceWorker.shared.setEnabled(showMediaPipe) }
        .onDisappear { DebugFaceWorker.shared.setEnabled(false) }
        .onReceive(NotificationCenter.default.publisher(for: DebugFaceWorker.notification)) { note in
            guard showMediaPipe else { return }
            facePoints = note.userInfo?["points"] as? [[Double]] ?? []
            faceStatus = note.userInfo?["status"] as? String ?? "Unavailable"
            faceFPS = note.userInfo?["fps"] as? Double
            faceLastUpdate = faceStatus == "Active" || faceStatus == "No face" ? Date() : nil
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { fpsClock = $0 }
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
    let points: [[Double]]
    let flipHorizontally: Bool
    var body: some View {
        Canvas { context, size in
            for point in points where point.count == 2 && point[0].isFinite && point[1].isFinite {
                let x = (flipHorizontally ? 1 - point[0] : point[0]) * size.width
                let y = point[1] * size.height
                context.fill(Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)), with: .color(.green.opacity(0.8)))
            }
        }
    }
}
#endif
