import SwiftUI
import AVFoundation
import AuraMotionCore

public struct HUDView: View {
    @ObservedObject private var localization = AppLocalization.shared
    @State private var snapshot: HUDSnapshot?
    @State private var isCompact = false
    @State private var showJointNumbers = AppEnvironment.shared.currentSettings.hudShowsJointNumbers
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
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))

                Spacer()

                Button(action: { isCompact.toggle() }) {
                    Image(systemName: isCompact ? "chevron.down" : "chevron.up")
                        .font(.system(size: 9))
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
                    .padding(.trailing, 35)
            }

            // Status Pill
            HStack {
                Text(L10n.tr(snapshot?.feedback ?? snapshot?.state.displayName ?? "INITIALIZING"))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.25))
                    .foregroundColor(statusColor)
                    .cornerRadius(6)

                Spacer()

                if let p95 = snapshot?.performance.inferenceDurationP95Ms {
                    Text(String(format: "%.1f ms", p95))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .padding(.horizontal, 10)

            if !isCompact {
                HStack(alignment: .top, spacing: 4) {
                    Text(effectiveCursorStrategyLabel)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 2)
                    Text(effectiveProviderLabel)
                        .lineLimit(1)
                }
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.white.opacity(0.62))
                .padding(.horizontal, 10)

                HStack(spacing: 6) {
                    Button {
                        showJointNumbers.toggle()
                        AppEnvironment.shared.updateHUDJointDisplay(showNumbers: showJointNumbers)
                    } label: {
                        Text(L10n.tr("Joint Numbers"))
                            .font(.system(size: 9, weight: .semibold))
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
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.horizontal, 10)

                if snapshot?.isVisionReconfigurationPending == true {
                    Text(L10n.tr("Reconfiguring vision provider…"))
                        .font(.system(size: 8))
                        .foregroundColor(.white.opacity(0.55))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                }

                // Live Hand Skeleton Canvas
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.4))

                    if snapshot?.showHUD == true && snapshot?.hudShowsCamera == true {
                        CameraPreviewView(
                            session: AppEnvironment.shared.capturePipeline.previewSession,
                            // Preview layers and Vision's point coordinates use opposite
                            // horizontal conventions on the built-in camera. Match the
                            // video to the already-mirrored gesture landmarks.
                            isMirrored: (snapshot?.isCameraMirrored ?? true) == (snapshot?.isVideoDataMirrored ?? false)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    if let sample = snapshot?.sample {
                        SkeletonView(sample: sample, showNumbers: showJointNumbers,
                                     scale: skeletonScale,
                                     flipHorizontally: snapshot?.hudShowsCamera == true)
                            .allowsHitTesting(false)
                    } else {
                        VStack(spacing: 4) {
                            Image(systemName: "hand.raised.slash")
                                .font(.system(size: 20))
                                .foregroundColor(.white.opacity(0.3))
                            Text(L10n.tr("No Hand Detected"))
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.4))
                        }
                    }
                }
                .aspectRatio(snapshot?.cameraAspectRatio ?? (16.0 / 9.0), contentMode: .fit)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)

                // Telemetry Footer
                HStack(spacing: 12) {
                    MetricLabel(title: L10n.tr("CAP"), value: String(format: "%.0f", snapshot?.performance.captureFPS ?? 0))
                    MetricLabel(title: L10n.tr("INF"), value: String(format: "%.0f", snapshot?.performance.inferenceFPS ?? 0))
                    MetricLabel(title: L10n.tr("DROP"), value: "\(snapshot?.performance.droppedFrames ?? 0)")
                    Spacer()
                    if let permissionLabel = snapshot?.permissions.compactStatusLabel {
                        Text(L10n.tr(permissionLabel))
                            .font(.system(size: 8, weight: .bold))
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
                .font(.system(size: 8, weight: .semibold))
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
        .onChange(of: skeletonScale) { _, newValue in
            pendingScaleSave?.cancel()
            let work = DispatchWorkItem { AppEnvironment.shared.updateHUDJointDisplay(scale: newValue) }
            pendingScaleSave = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        }
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
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(.white.opacity(0.4))
            Text(value)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
        }
    }
}

struct SkeletonView: View {
    let sample: HandSample
    let showNumbers: Bool
    let scale: Double
    let flipHorizontally: Bool

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
            ForEach(HandJointName.allCases, id: \.self) { name in
                if let pt = sample.joint(name, minConfidence: 0.25) {
                    ZStack {
                        Circle()
                            .fill(name == .indexTip || name == .thumbTip ? Color.yellow : Color.cyan)
                            .frame(width: (name == .indexTip ? 6 : 4) * scale,
                                   height: (name == .indexTip ? 6 : 4) * scale)
                        if showNumbers {
                            Text("\(name.landmarkNumber)")
                                .font(.system(size: 9 * scale, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                                .shadow(color: .black, radius: 2)
                                .fixedSize()
                                .offset(x: 8 * scale, y: -8 * scale)
                        }
                    }
                    .position(convert(pt, size: geo.size))
                }
            }
        }
    }

    private func convert(_ pt: CGPoint, size: CGSize) -> CGPoint {
        // Vision coordinates: [0, 1] bottom-left origin
        return CGPoint(x: (flipHorizontally ? 1 - pt.x : pt.x) * size.width,
                       y: (1.0 - pt.y) * size.height)
    }
}
