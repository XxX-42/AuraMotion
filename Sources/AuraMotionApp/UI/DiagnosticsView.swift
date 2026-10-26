import SwiftUI
import AuraMotionCore

public struct DiagnosticsView: View {
    @ObservedObject private var localization = AppLocalization.shared
    @State private var snapshot: HUDSnapshot?
    @State private var isRecording = false
    @State private var lastSavedURL: URL?
    @State private var cursorHistory: [CGPoint] = []

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.tr("System Telemetry & Diagnostics"))
                .font(.headline)

            Divider()

            // Latency Metrics
            GroupBox(label: Text(L10n.tr("Latency & Timing"))) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(L10n.tr("Vision Inference p50:"))
                        Spacer()
                        Text(String(format: "%.2f ms", snapshot?.performance.inferenceDurationP50Ms ?? 0))
                            .monospacedDigit()
                    }
                    HStack {
                        Text(L10n.tr("Vision Inference p95:"))
                        Spacer()
                        Text(String(format: "%.2f ms", snapshot?.performance.inferenceDurationP95Ms ?? 0))
                            .monospacedDigit()
                    }
                    HStack {
                        Text(L10n.tr("Mailbox Wait Time:"))
                        Spacer()
                        Text(String(format: "%.2f ms", snapshot?.performance.mailboxWaitMs ?? 0))
                            .monospacedDigit()
                    }
                    HStack {
                        Text(L10n.tr("Capture → Vision result:"))
                        Spacer()
                        Text(String(format: "%.2f ms", snapshot?.performance.pipelineToEventMs ?? 0))
                            .monospacedDigit()
                    }
                    if snapshot?.performance.isLatencyEstimated == true {
                        Text(L10n.tr("* Presentation timestamp anchored to host arrival clock"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(4)
            }

            // Quality & System State
            GroupBox(label: Text(L10n.tr("Cursor Stability"))) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.tr("Horizontal motion: orange is raw; cyan is smoothed. Hold still to compare jitter."))
                        .font(.caption).foregroundStyle(.secondary)
                    Canvas { context, size in
                        guard cursorHistory.count > 1 else { return }
                        let values = cursorHistory.flatMap { [$0.x, $0.y] }
                        let low = (values.min() ?? 0) - 2
                        let span = max(10, (values.max() ?? 0) - low + 2)
                        for raw in [true, false] {
                            var path = Path()
                            for (i, value) in cursorHistory.enumerated() {
                                let position = CGPoint(x: CGFloat(i) / CGFloat(cursorHistory.count - 1) * size.width,
                                    y: size.height * (1 - ((raw ? value.x : value.y) - low) / span))
                                if i == 0 { path.move(to: position) } else { path.addLine(to: position) }
                            }
                            context.stroke(path, with: .color(raw ? .orange : .cyan), lineWidth: 1.5)
                        }
                    }.frame(height: 70)
                    Text(String(format: L10n.tr("Index confidence: %.0f%%"), Double(snapshot?.sample?.joints[.indexTip]?.confidence ?? 0) * 100))
                        .font(.caption).monospacedDigit()
                }.padding(4)
            }

            GroupBox(label: Text(L10n.tr("System Health"))) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(L10n.tr("Thermal Quality Stage:"))
                        Spacer()
                        Text("\(snapshot?.thermalStage.rawValue ?? 0)")
                    }
                    HStack {
                        Text(L10n.tr("Dropped Frames:"))
                        Spacer()
                        Text("\(snapshot?.performance.droppedFrames ?? 0)")
                    }
                    HStack {
                        Text(L10n.tr("Physical Arbitration Tap:"))
                        Spacer()
                        Text(L10n.tr(snapshot?.isArbitrationActive == true ? "Active" : "Disabled/Cooldown"))
                            .foregroundColor(snapshot?.isArbitrationActive == true ? .green : .orange)
                    }
                }
                .padding(4)
            }

            GroupBox(label: Text(L10n.tr("Cursor Experiments"))) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top) {
                        Text(L10n.tr("Effective cursor strategy:"))
                        Spacer()
                        Text(effectiveCursorStrategyLabel)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text(L10n.tr("Effective vision provider:"))
                        Spacer()
                        Text(effectiveProviderLabel)
                    }
                    HStack {
                        Text(L10n.tr("Vision ROI:"))
                        Spacer()
                        Text(L10n.tr(snapshot?.visionWorkerStatus?.roiEnabled == true ? "Enabled" : "Disabled"))
                    }
                    if let roi = snapshot?.visionWorkerStatus?.currentROI {
                        HStack(alignment: .top) {
                            Text(L10n.tr("Current ROI:"))
                            Spacer()
                            Text(String(format: "x %.2f, y %.2f, w %.2f, h %.2f",
                                        roi.origin.x, roi.origin.y, roi.width, roi.height))
                                .monospacedDigit()
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    if snapshot?.isVisionReconfigurationPending == true {
                        Text(L10n.tr("Reconfiguring vision provider…"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let status = snapshot?.visionWorkerStatus,
                       status.requestedMediaPipeBenchmark,
                       !status.mediaPipeBenchmarkAvailable,
                       let reason = status.mediaPipeUnavailabilityReason {
                        Text(L10n.tr("MediaPipe benchmark requested but unavailable:") + " " + L10n.tr(reason))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let diagnostics = snapshot?.visionWorkerStatus?.lastDiagnostics,
                       snapshot?.visionWorkerStatus?.roiEnabled == true,
                       diagnostics.usedFullFrame {
                        Text(L10n.tr("ROI fallback:") + " " + L10n.tr(diagnostics.detail ?? "Full-frame fallback"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(4)
            }

            // Opt-in Landmark Recording
            GroupBox(label: Text(L10n.tr("Landmark Recording (Privacy-Safe)"))) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.tr("Records anonymized 2D joint coordinates for regression testing. No camera video is ever saved."))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack {
                        Button(action: toggleRecording) {
                            Text(L10n.tr(isRecording ? "Stop & Save Recording" : "Start Recording"))
                        }
                        if isRecording {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                            Text(L10n.tr("Recording..."))
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }

                    if let url = lastSavedURL {
                        Text(L10n.tr("Saved to: {filename}", replacing: ["{filename}": url.lastPathComponent]))
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }
                .padding(4)
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 420, height: 780)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("HUDSnapshotUpdated"))) { note in
            if let snap = note.object as? HUDSnapshot {
                self.snapshot = snap
                if let raw = snap.rawCursorLocation, let filtered = snap.cursorLocation {
                    cursorHistory.append(CGPoint(x: raw.x, y: filtered.x))
                    if cursorHistory.count > 90 { cursorHistory.removeFirst(cursorHistory.count - 90) }
                } else { cursorHistory.removeAll() }
            }
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

    private func toggleRecording() {
        let env = AppEnvironment.shared
        if isRecording {
            lastSavedURL = env.landmarkRecorder.stopAndSave()
            isRecording = false
        } else {
            env.landmarkRecorder.start()
            isRecording = true
            lastSavedURL = nil
        }
    }
}
