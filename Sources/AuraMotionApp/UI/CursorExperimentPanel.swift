import AppKit
import QuartzCore
import SwiftUI
import AuraMotionCore

struct CursorExperimentPanel: View {
    @Binding private var settings: CursorExperimentSettings
    private let isCameraAuthorized: Bool
    @ObservedObject private var localization = AppLocalization.shared
    @State private var isPreparingSample = false
    @State private var isWaitingForTracking = false
    @State private var isRecordingSample = false
    @State private var sampleSecondsRemaining = 0
    @State private var isExportingMetrics = false
    @State private var metricsStatusKey: String?
    @State private var lastExportURL: URL?
    @State private var recordingID = UUID()
    @State private var samplePurpose: CursorExperimentTaskPhase = .other

    init(settings: Binding<CursorExperimentSettings>, isCameraAuthorized: Bool) {
        self._settings = settings
        self.isCameraAuthorized = isCameraAuthorized
    }

    var body: some View {
        let _ = localization.language
        VStack(alignment: .leading, spacing: 12) {
            GroupBox(label: Text(L10n.tr("Cursor Experiment Settings"))) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker(L10n.tr("Preset:"), selection: presetBinding) {
                        Text(L10n.tr("Baseline")).tag(CursorExperimentPreset.baseline)
                        Text(L10n.tr("Optimized")).tag(CursorExperimentPreset.optimized)
                        Text(L10n.tr("Custom")).tag(CursorExperimentPreset.custom)
                    }
                    .pickerStyle(.segmented)

                    Text(L10n.tr("Experimental settings are opt-in. Baseline keeps the legacy cursor path."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 6) {
                        experimentToggle("Stable Pointer Anchor", keyPath: \.stableAnchorEnabled)
                        experimentToggle("Relative Rebased Mapping", keyPath: \.relativeMappingEnabled)
                        experimentToggle("Adaptive Deadzone", keyPath: \.adaptiveDeadzoneEnabled)
                        experimentToggle("Low-Speed Quantization", keyPath: \.lowSpeedQuantizationEnabled)
                        experimentToggle("Velocity-Based Gain", keyPath: \.velocityGainEnabled)
                        experimentToggle("Separate Drag Filter Tuning", keyPath: \.separateDragTuningEnabled)
                        experimentToggle("Optimized One Euro Filter", keyPath: \.optimizedOneEuroEnabled)
                        experimentToggle("Vision Region of Interest (ROI)", keyPath: \.visionROIEnabled)

                        Toggle(
                            L10n.tr("MediaPipe Benchmark"),
                            isOn: MediaPipeHandPoseProvider.isAvailable
                                ? experimentBinding(\.mediaPipeBenchmarkEnabled)
                                : .constant(false)
                        )
                        .disabled(!MediaPipeHandPoseProvider.isAvailable)

                        if !MediaPipeHandPoseProvider.isAvailable {
                            Text(L10n.tr("MediaPipe hand tracking is unavailable."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(L10n.tr("Vision remains active; no MediaPipe benchmark will run."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    DisclosureGroup(L10n.tr("Advanced Tuning")) {
                        advancedSettings
                            .padding(.top, 8)
                    }
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            metricsPanel
            Button(L10n.tr("Open Pointer Test Surface")) {
                PointerValidationWindow.show()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onDisappear { cancelSample() }
    }

    private var presetBinding: Binding<CursorExperimentPreset> {
        Binding(
            get: { settings.preset },
            set: { preset in
                var updated = settings
                updated.applyPreset(preset)
                settings = updated
            }
        )
    }

    private var advancedSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            strategySettings
            Divider()
            filterSettings
            Divider()
            deadzoneSettings
            Divider()
            gainSettings
            Divider()
            roiSettings
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var strategySettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(L10n.tr("Pointer Anchor:"), selection: experimentBinding(\.anchorStrategy)) {
                Text(L10n.tr("Legacy Tip Fusion")).tag(PointerAnchorStrategy.legacyTipFusion)
                Text(L10n.tr("Index MCP")).tag(PointerAnchorStrategy.indexMCP)
                Text(L10n.tr("Palm Centroid")).tag(PointerAnchorStrategy.palmCentroid)
                Text(L10n.tr("Palm MCP Fusion")).tag(PointerAnchorStrategy.palmMCPFusion)
            }

            Picker(L10n.tr("Mapping Mode:"), selection: experimentBinding(\.mappingMode)) {
                Text(L10n.tr("Absolute Legacy")).tag(CursorMappingMode.absoluteLegacy)
                Text(L10n.tr("Relative Rebased")).tag(CursorMappingMode.relativeRebased)
            }

            Picker(L10n.tr("Filter Preset:"), selection: experimentBinding(\.filterPreset)) {
                Text(L10n.tr("Legacy")).tag(CursorFilterPreset.legacy)
                Text(L10n.tr("Precision")).tag(CursorFilterPreset.precision)
                Text(L10n.tr("Custom")).tag(CursorFilterPreset.custom)
            }
        }
    }

    private var filterSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            sliderRow("Pointer Min Cutoff", value: filterBinding(\.pointerMinCutoff), range: 0.1...10, step: 0.05, format: "%.2f")
            sliderRow("Pointer Beta", value: filterBinding(\.pointerBeta), range: 0...0.1, step: 0.001, format: "%.3f")
            sliderRow("Drag Min Cutoff", value: filterBinding(\.dragMinCutoff), range: 0.1...10, step: 0.05, format: "%.2f")
            sliderRow("Drag Beta", value: filterBinding(\.dragBeta), range: 0...0.1, step: 0.001, format: "%.3f")
            sliderRow("Derivative Cutoff", value: filterBinding(\.derivativeCutoff), range: 0.1...10, step: 0.05, format: "%.2f")
        }
    }

    private var deadzoneSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            sliderRow("Rest Deadzone (px)", value: restDeadzoneBinding, range: 0...12, step: 0.1, format: "%.1f")
            sliderRow("Moving Deadzone (px)", value: movingDeadzoneBinding, range: 0...max(settings.restDeadzone, 0.1), step: 0.05, format: "%.2f")
            sliderRow("Deadzone Velocity (px/s)", value: experimentBinding(\.deadzoneVelocity), range: 1...3000, step: 10, format: "%.0f")
            sliderRow("Quantization Speed Threshold (px/s)", value: experimentBinding(\.quantizationSpeedThreshold), range: 0...1000, step: 5, format: "%.0f")
        }
    }

    private var gainSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            sliderRow("Precision Gain", value: precisionGainBinding, range: 0.05...3, step: 0.05, format: "%.2f")
            sliderRow("Normal Gain", value: normalGainBinding, range: settings.precisionGain...4, step: 0.05, format: "%.2f")
            sliderRow("Fast Gain", value: fastGainBinding, range: settings.normalGain...6, step: 0.05, format: "%.2f")
            sliderRow("Precision Speed (px/s)", value: experimentBinding(\.gainPrecisionSpeed), range: 1...1000, step: 5, format: "%.0f")
            sliderRow("Normal Speed (px/s)", value: experimentBinding(\.gainNormalSpeed), range: settings.gainPrecisionSpeed + 1...5000, step: 10, format: "%.0f")
            sliderRow("Fast Speed (px/s)", value: experimentBinding(\.gainFastSpeed), range: settings.gainNormalSpeed + 1...10000, step: 10, format: "%.0f")
        }
    }

    private var roiSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            sliderRow("ROI Scale", value: experimentBinding(\.roiScale), range: 1.1...4, step: 0.05, format: "%.2f")
            sliderRow("ROI Minimum Size", value: experimentBinding(\.roiMinimumSize), range: 0.1...1, step: 0.01, format: "%.2f")
        }
    }

    private var restDeadzoneBinding: Binding<Double> {
        Binding(
            get: { settings.restDeadzone },
            set: { value in
                var updated = settings
                updated.restDeadzone = value
                updated.movingDeadzone = min(updated.movingDeadzone, value)
                updated.preset = .custom
                settings = updated
            }
        )
    }

    private var movingDeadzoneBinding: Binding<Double> {
        Binding(
            get: { settings.movingDeadzone },
            set: { value in
                var updated = settings
                updated.movingDeadzone = min(value, updated.restDeadzone)
                updated.preset = .custom
                settings = updated
            }
        )
    }

    private var normalGainBinding: Binding<Double> {
        Binding(
            get: { settings.normalGain },
            set: { value in
                var updated = settings
                updated.normalGain = max(value, updated.precisionGain)
                updated.fastGain = max(updated.fastGain, updated.normalGain)
                updated.preset = .custom
                settings = updated
            }
        )
    }

    private var precisionGainBinding: Binding<Double> {
        Binding(
            get: { settings.precisionGain },
            set: { value in
                var updated = settings
                updated.precisionGain = value
                updated.normalGain = max(updated.normalGain, value)
                updated.fastGain = max(updated.fastGain, updated.normalGain)
                updated.preset = .custom
                settings = updated
            }
        )
    }

    private var fastGainBinding: Binding<Double> {
        Binding(
            get: { settings.fastGain },
            set: { value in
                var updated = settings
                updated.fastGain = max(value, updated.normalGain)
                updated.preset = .custom
                settings = updated
            }
        )
    }

    private func experimentToggle(_ title: String, keyPath: WritableKeyPath<CursorExperimentSettings, Bool>) -> some View {
        Toggle(L10n.tr(title), isOn: experimentBinding(keyPath))
    }

    private func experimentBinding<Value>(_ keyPath: WritableKeyPath<CursorExperimentSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { value in
                var updated = settings
                updated[keyPath: keyPath] = value
                updated.preset = .custom
                settings = updated
            }
        )
    }

    private func filterBinding<Value>(_ keyPath: WritableKeyPath<CursorExperimentSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { value in
                var updated = settings
                updated[keyPath: keyPath] = value
                updated.filterPreset = .custom
                updated.preset = .custom
                settings = updated
            }
        )
    }

    private func sliderRow(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        format: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(L10n.tr(title))
                Spacer(minLength: 8)
                Text(String(format: format, value.wrappedValue))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
        }
    }

    private var metricsPanel: some View {
        GroupBox(label: Text(L10n.tr("A/B Metrics"))) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.tr("An opt-in camera sample runs for 15 seconds. No camera video is saved."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L10n.tr("Run one sample per preset to compare baseline and optimized results."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Picker(L10n.tr("Sample purpose:"), selection: $samplePurpose) {
                    Text(L10n.tr("Stationary hold")).tag(CursorExperimentTaskPhase.stationary)
                    Text(L10n.tr("Slow movement")).tag(CursorExperimentTaskPhase.slowMove)
                    Text(L10n.tr("Fast movement")).tag(CursorExperimentTaskPhase.fastMove)
                    Text(L10n.tr("Unlabelled")).tag(CursorExperimentTaskPhase.other)
                }
                .disabled(isSampleActive)
                Text(L10n.tr("Purpose labels the full sample; target metrics still need target coordinates."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Button(L10n.tr("Reset Experiment Metrics")) {
                        AppEnvironment.shared.resetExperimentMetrics()
                        metricsStatusKey = "Metrics reset."
                    }
                    .disabled(isSampleActive)

                    Button(L10n.tr("Export A/B Metrics")) {
                        exportMetrics()
                    }
                    .disabled(isExportingMetrics || isSampleActive)
                }

                Text(L10n.tr("Raise your hand, extend only your index finger, and keep your thumb away from your middle and ring fingers. Recording starts when the HUD says TRACKING."))
                    .font(.callout.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                if isPreparingSample {
                    HStack(alignment: .top) {
                        ProgressView()
                            .controlSize(.small)
                        VStack(alignment: .leading, spacing: 4) {
                            if isWaitingForTracking {
                                Text(L10n.tr(
                                    "Waiting for a tracked pointer… {seconds}",
                                    replacing: ["{seconds}": "\(sampleSecondsRemaining)"]
                                ))
                                    .font(.headline)
                            } else {
                                Text(L10n.tr(
                                    "Preparing camera sample… {seconds}",
                                    replacing: ["{seconds}": "\(sampleSecondsRemaining)"]
                                ))
                                .font(.headline)
                            }
                            Text(L10n.tr("Raise your hand, extend only your index finger, and keep your thumb away from your middle and ring fingers. Recording starts when the HUD says TRACKING."))
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        Button(L10n.tr("Cancel Sample")) { cancelSample() }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                } else if isRecordingSample {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text(L10n.tr(
                            "Recording camera sample… {seconds}",
                            replacing: ["{seconds}": "\(sampleSecondsRemaining)"]
                        ))
                        .font(.headline)
                        Spacer()
                        Button(L10n.tr("Stop Sample")) {
                            stopSample()
                        }
                    }
                } else {
                    Button(L10n.tr("Start 15s Camera A/B Sample")) {
                        startSample()
                    }
                    .disabled(isExportingMetrics || !isCameraAuthorized || isSampleActive)
                }

                if !isCameraAuthorized {
                    Text(L10n.tr("Camera access is required"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if isExportingMetrics {
                    ProgressView()
                        .controlSize(.small)
                }

                if let metricsStatusKey {
                    Text(L10n.tr(metricsStatusKey))
                        .font(.caption)
                        .foregroundStyle(metricsStatusKey == "Metrics export failed." ? Color.orange : Color.gray)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let lastExportURL {
                    Text(lastExportURL.path)
                        .font(.caption)
                        .textSelection(.enabled)
                    Button(L10n.tr("Reveal in Finder")) {
                        NSWorkspace.shared.activateFileViewerSelecting([lastExportURL])
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("HUDSnapshotUpdated")).receive(on: DispatchQueue.main)) { note in
            guard isPreparingSample,
                  isWaitingForTracking,
                  let snapshot = note.object as? HUDSnapshot,
                  isFreshPointerSnapshot(snapshot) else { return }
            beginRecording(sampleID: recordingID)
        }
    }

    private func startSample() {
        guard !isSampleActive else { return }
        metricsStatusKey = nil
        let sampleID = UUID()
        recordingID = sampleID
        isPreparingSample = true
        isWaitingForTracking = false
        sampleSecondsRemaining = 5
        schedulePreparationCountdown(sampleID: sampleID, secondsRemaining: 5)
    }

    private func stopSample() {
        guard isRecordingSample else { return }
        recordingID = UUID()
        isRecordingSample = false
        sampleSecondsRemaining = 0
        AppEnvironment.shared.stopExperimentRecording()
    }

    private var isSampleActive: Bool { isPreparingSample || isRecordingSample }

    private func schedulePreparationCountdown(sampleID: UUID, secondsRemaining: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            guard recordingID == sampleID, isPreparingSample else { return }
            let next = secondsRemaining - 1
            if next > 0 {
                sampleSecondsRemaining = next
                schedulePreparationCountdown(sampleID: sampleID, secondsRemaining: next)
            } else {
                isWaitingForTracking = true
                sampleSecondsRemaining = 30
                scheduleTrackingWait(sampleID: sampleID, secondsRemaining: 30)
            }
        }
    }

    private func scheduleTrackingWait(sampleID: UUID, secondsRemaining: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            guard recordingID == sampleID,
                  isPreparingSample,
                  isWaitingForTracking else { return }
            let next = secondsRemaining - 1
            if next > 0 {
                sampleSecondsRemaining = next
                scheduleTrackingWait(sampleID: sampleID, secondsRemaining: next)
            } else {
                recordingID = UUID()
                isPreparingSample = false
                isWaitingForTracking = false
                sampleSecondsRemaining = 0
                metricsStatusKey = "No tracked pointer was detected within 30 seconds."
            }
        }
    }

    private func isFreshPointerSnapshot(_ snapshot: HUDSnapshot) -> Bool {
        guard snapshot.state == .pointer,
              let sample = snapshot.sample,
              snapshot.cursorLocation != nil,
              snapshot.cursorDiagnostics?.phase == .pointer else { return false }
        let age = CACurrentMediaTime() - sample.hostTimestamp
        return age.isFinite && age >= -0.05 && age <= 0.25
    }

    private func beginRecording(sampleID: UUID) {
        guard recordingID == sampleID,
              isPreparingSample,
              isWaitingForTracking else { return }
        isPreparingSample = false
        isWaitingForTracking = false
        isRecordingSample = true
        sampleSecondsRemaining = 15
        metricsStatusKey = nil
        AppEnvironment.shared.startExperimentRecording(duration: 15, phase: samplePurpose)
        scheduleRecordingCountdown(sampleID: sampleID, secondsRemaining: 15)
    }

    private func scheduleRecordingCountdown(sampleID: UUID, secondsRemaining: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            guard recordingID == sampleID, isRecordingSample else { return }
            let next = secondsRemaining - 1
            if next > 0 {
                sampleSecondsRemaining = next
                scheduleRecordingCountdown(sampleID: sampleID, secondsRemaining: next)
            } else {
                recordingID = UUID()
                sampleSecondsRemaining = 0
                isRecordingSample = false
                AppEnvironment.shared.stopExperimentRecording()
                metricsStatusKey = "Metrics sample complete."
            }
        }
    }

    private func cancelSample() {
        guard isSampleActive else { return }
        let wasRecording = isRecordingSample
        recordingID = UUID()
        isPreparingSample = false
        isWaitingForTracking = false
        isRecordingSample = false
        sampleSecondsRemaining = 0
        if wasRecording { AppEnvironment.shared.stopExperimentRecording() }
        metricsStatusKey = "Sample cancelled."
    }

    private func exportMetrics() {
        guard !isExportingMetrics else { return }
        isExportingMetrics = true
        metricsStatusKey = nil
        AppEnvironment.shared.exportExperimentMetrics { result in
            DispatchQueue.main.async {
                isExportingMetrics = false
                switch result {
                case .success(let url):
                    metricsStatusKey = "Metrics exported."
                    lastExportURL = url
                case .failure:
                    metricsStatusKey = "Metrics export failed."
                }
            }
        }
    }
}
