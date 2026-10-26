import QuartzCore
import Foundation
import CoreGraphics
import AVFoundation
import CoreMedia
import AppKit

public struct HUDSnapshot: Sendable {
    public let state: GestureState
    public let sample: HandSample?
    public let performance: PerformanceSnapshot
    public let thermalStage: ThermalQualityStage
    public let permissions: PermissionsState
    public let isArbitrationActive: Bool
    public let cursorLocation: CGPoint?
    public var feedback: String? = nil
    public var commandMenu: CommandMenuSnapshot? = nil
    public var showHUD = true
    public var hudShowsCamera = false
    public var hudPreviewMirrored = true
    public var isCameraMirrored = true
    public var cameraAspectRatio = 16.0 / 9.0
    public var isVideoDataMirrored = false
    public var hudShowsJointNumbers = false
    public var hudHighlightFirstRing = false
    public var hudSkeletonScale = 1.0
    public var clickFeedbackID: UInt64 = 0
    public var clickFeedbackLocation: CGPoint? = nil
    public var rawCursorLocation: CGPoint? = nil
    public var cursorExperimentStatus: String = "Baseline"
    public var cursorDiagnostics: CursorMotionDiagnostics? = nil
    public var cursorExperimentSettings = CursorExperimentSettings()
    public var visionWorkerStatus: VisionWorkerStatusSnapshot? = nil
    public var isVisionReconfigurationPending = false
}

public protocol AppEnvironmentObserver: AnyObject, Sendable {
    func environmentDidUpdateHUDSnapshot(_ snapshot: HUDSnapshot)
}

/// Central coordinator for AuraMotion.
/// Enforces a strict single-queue ownership model for interaction state on interactionQueue.
public final class AppEnvironment: CapturePipelineDelegate, VisionInferenceWorkerDelegate, GestureStateMachineDelegate, InputArbitratorDelegate, @unchecked Sendable {
    public static let shared = AppEnvironment()

    // Dedicated serial queue for all interaction state and FSM transitions
    public let interactionQueue = DispatchQueue(label: "com.auramotion.interaction", qos: .userInteractive)
    private let safetyQueue = DispatchQueue(label: "com.auramotion.safety", qos: .userInteractive)
    private let visionConfigurationLock = NSLock()
    private var visionConfigurationGeneration: UInt64 = 0
    private var visionReconfigurationPending = false
    private let experimentExportQueue = DispatchQueue(label: "com.auramotion.experiment-export", qos: .utility)

    // Core subsystems
    public let permissionsManager = PermissionsManager()
    public let settingsRepository = SettingsRepository()
    public let capturePipeline = CapturePipeline()
    public let visionWorker = VisionInferenceWorker()
    public let continuityTracker = IdentityContinuityTracker()
    public let cursorController: CursorController
    public let stateMachine = GestureStateMachine()
    public let outputCoordinator = EventOutputCoordinator()
    public let inputArbitrator = InputArbitrator()
    public let performanceTracker = PerformanceTracker()
    public let qualityLadder = QualityLadder()
    public let landmarkRecorder = LandmarkRecorder()
    private let experimentMetricsRecorder = CursorExperimentMetricsRecorder()

    public weak var observer: AppEnvironmentObserver?

    public private(set) var currentSettings: AppSettings
    public private(set) var currentCalibration: CalibrationProfile

    // Confined to interactionQueue
    private var latestSnapshotSample: HandSample?
    private var latestCursorLocation: CGPoint?
    private var latestRawCursorLocation: CGPoint?
    private var isArbitrationCooldownActive = false
    private var isReleaseConfirmed = false
    private var isCooldownElapsed = false
    private var lastHUDPublishTime: TimeInterval = 0
    private var recognitionFeedback: String?
    private var recognitionTime: TimeInterval = 0
    private var calibrationPreviousPause: Bool?
    private var clickFeedbackID: UInt64 = 0
    private var clickFeedbackLocation: CGPoint?
    private var hasStarted = false
    private var captureStartRequested = false

    public func setCalibrationActive(_ active: Bool) {
        interactionQueue.async { [weak self] in
            guard let self else { return }
            if active {
                guard self.calibrationPreviousPause == nil else { return }
                self.calibrationPreviousPause = self.stateMachine.isManualPaused
                self.stateMachine.isManualPaused = true
                self.stateMachine.reset()
                self.outputCoordinator.emergencyRelease()
            } else if let previous = self.calibrationPreviousPause {
                self.stateMachine.reset()
                self.stateMachine.isManualPaused = previous
                self.calibrationPreviousPause = nil
            }
        }
    }

    private func recognize(_ message: String) {
        recognitionFeedback = message
        recognitionTime = CACurrentMediaTime()
    }

    /// Transitions and settings changes are rare, so query Quartz here rather
    /// than on the per-frame interaction path. Fall back to the last mapped
    /// output when the current pointer location is unavailable.
    private func visibleCursorLocation(fallback: CGPoint? = nil) -> CGPoint? {
        CGEvent(source: nil)?.location ?? cursorController.lastOutputLocation ?? fallback ?? latestCursorLocation
    }

    public init() {
        let repo = SettingsRepository()
        let settings = repo.loadSettings()
        let displayID = CGMainDisplayID()
        let bounds = CGDisplayBounds(displayID)
        let calibration = repo.loadCalibration(cameraID: "builtin", displayID: displayID, arrangementHash: 0)

        var cal = calibration
        cal.displayBounds = bounds

        self.currentSettings = settings
        self.currentCalibration = cal
        self.cursorController = CursorController(profile: cal)
        self.cursorController.reconfigure(settings.cursorExperiment, cursorPosition: CGEvent(source: nil)?.location)
        AppLocalization.shared.setLanguage(settings.language)

        // Wire delegates
        self.capturePipeline.delegate = self
        self.visionWorker.delegate = self
        self.stateMachine.delegate = self
        self.inputArbitrator.delegate = self
        self.inputArbitrator.setMotionPriorityEnabled(settings.cursorExperiment.hasCursorExperiments)

        // Wire epoch and injection validation providers into outputCoordinator
        self.outputCoordinator.epochProvider = { [weak self] in
            self?.inputArbitrator.currentEpoch() ?? 0
        }
        self.outputCoordinator.injectionAllowedProvider = { [weak self] in
            guard let self = self else { return false }
            // Output path uses only atomic/cached state. No interactionQueue-owned fields.
            return self.permissionsManager.gate.canInject && self.inputArbitrator.isInjectionEnabled()
        }

        self.visionWorker.isMirrored = settings.isCameraMirrored
        self.stateMachine.isClutchEnabled = settings.isClutchEnabled
        self.stateMachine.clutchDwellDuration = settings.clutchDwellTime
        self.stateMachine.scrollDetector.scrollController.isInertiaEnabled = settings.scrollInertiaEnabled
        self.stateMachine.isPalmSwipeEnabled = settings.isPalmSwipeEnabled
        self.stateMachine.updateCalibration(cal)

        if settings.cursorExperiment.visionROIEnabled || settings.cursorExperiment.mediaPipeBenchmarkEnabled {
            self.visionWorker.reconfigure(settings.cursorExperiment) {}
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.permissionsManager.checkPermissions()
        }

        NotificationCenter.default.addObserver(
            forName: .auraMotionPermissionsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.interactionQueue.async {
                guard self.hasStarted else { return }
                let permissions = self.permissionsManager.gate.cachedSnapshot
                if permissions.isCameraAuthorized && !self.captureStartRequested && self.capturePipeline.state == .idle {
                    self.startCapture(permissions)
                }
                self.startInputArbitrationIfNeeded(permissions)
                self.publishHUDSnapshot(force: true)
            }
        }
    }

    public func start() {
        // Keep lifecycle flags and capture startup serialized with frame-driven
        // interaction state.  This also makes repeated start/stop calls safe
        // when AppKit and a camera permission callback race each other.
        interactionQueue.async { [weak self] in
            guard let self, !self.hasStarted else { return }
            self.hasStarted = true
            let perms = self.permissionsManager.checkPermissions()
            self.permissionsManager.startPeriodicRefresh()

            // Diagnostic logging — write to file for reliable capture
            let diagLines = """
            [AuraMotion] Permission check at startup (\(Date())):
              Executable: \(CommandLine.arguments.first ?? "unknown")
              Bundle: \(Bundle.main.bundlePath)
              Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")
              Camera: \(perms.isCameraAuthorized)
              Accessibility (AXIsProcessTrusted): \(perms.isAccessibilityTrusted)
              PostEvent: \(perms.isPostEventAuthorized)
              ListenEvent: \(perms.isListenEventAuthorized)
              canInjectInput: \(perms.canInjectInput)
              canArbitrate: \(perms.canArbitrate)
            """
            try? diagLines.write(toFile: "/tmp/auramotion_perms.log", atomically: true, encoding: .utf8)

            // Permission request APIs can present system UI. Keep those calls
            // on the main thread while all gesture/capture state remains on
            // interactionQueue.
            if !perms.isAccessibilityTrusted || !perms.isPostEventAuthorized || !perms.isListenEventAuthorized {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if !perms.isAccessibilityTrusted {
                        self.permissionsManager.requestAccessibilityIfNeeded()
                    }
                    if !perms.isPostEventAuthorized {
                        self.permissionsManager.requestPostEventAccess()
                    }
                    if !perms.isListenEventAuthorized {
                        self.permissionsManager.requestListenEventAccess()
                    }
                }
            }

            if perms.isCameraAuthorized {
                self.startCapture(perms)
            } else if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
                // First launch: trigger the TCC camera prompt
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.permissionsManager.requestCameraAccess { [weak self] granted in
                        guard let self, granted else { return }
                        self.interactionQueue.async {
                            let refreshed = self.permissionsManager.checkPermissions()
                            self.startCapture(refreshed)
                            self.startInputArbitrationIfNeeded(refreshed)
                            self.publishHUDSnapshot(force: true)
                        }
                    }
                }
            }
            self.startInputArbitrationIfNeeded(perms)
            self.publishHUDSnapshot(force: true)
            // If camera denied/restricted, do nothing — user must grant via System Settings
        }
    }

    private func startCapture(_ perms: PermissionsState) {
        guard perms.isCameraAuthorized else { return }
        guard !captureStartRequested else { return }
        guard capturePipeline.state == .idle || capturePipeline.state == .configured else { return }
        captureStartRequested = true

        capturePipeline.configure { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success:
                self.capturePipeline.start { startResult in
                    if case .failure(let error) = startResult {
                        self.interactionQueue.async { [weak self] in
                            self?.captureStartRequested = false
                            self?.publishHUDSnapshot(force: true)
                        }
                        StructuredLogger.capture.error("Failed to start capture: \(error.localizedDescription)")
                    }
                }
            case .failure(let error):
                self.interactionQueue.async { [weak self] in
                    self?.captureStartRequested = false
                    self?.publishHUDSnapshot(force: true)
                }
                StructuredLogger.capture.error("Failed to configure capture: \(error.localizedDescription)")
            }
        }
    }

    private func startInputArbitrationIfNeeded(_ perms: PermissionsState) {
        if perms.canArbitrate && !inputArbitrator.isTapActive {
            _ = inputArbitrator.start()
        }
    }

    public func stop() {
        permissionsManager.stopPeriodicRefresh()
        interactionQueue.async { [weak self] in
            guard let self = self else { return }
            self.hasStarted = false
            self.captureStartRequested = false
            self.stateMachine.transition(to: .paused)
            self.outputCoordinator.emergencyRelease()
            self.capturePipeline.stop()
            self.inputArbitrator.stop()
            _ = self.experimentMetricsRecorder.stop()
        }
    }

    public func resetExperimentMetrics() {
        interactionQueue.async { [weak self] in
            self?.experimentMetricsRecorder.reset()
        }
    }

    public func startExperimentRecording(
        duration: Double,
        phase: CursorExperimentTaskPhase = .other
    ) {
        interactionQueue.async { [weak self] in
            guard let self,
                  self.hasStarted,
                  self.permissionsManager.gate.cachedSnapshot.isCameraAuthorized else { return }
            let workerStatus = self.visionWorker.statusSnapshot
            let metadata = CursorExperimentRecordingMetadata(
                settings: self.currentSettings.cursorExperiment,
                calibrationProfile: self.currentCalibration,
                initialCursorPosition: self.visibleCursorLocation(fallback: self.latestCursorLocation),
                declaredTaskPhase: phase == .other ? nil : phase,
                provider: workerStatus.activeProviderIdentifier,
                providerAvailabilityReason: workerStatus.mediaPipeUnavailabilityReason,
                camera: self.experimentCameraMetadata()
            )
            self.experimentMetricsRecorder.start(
                duration: duration,
                source: .camera,
                metadata: metadata
            )
        }
    }

    public func stopExperimentRecording() {
        interactionQueue.async { [weak self] in
            _ = self?.experimentMetricsRecorder.stop()
        }
    }

    public func exportExperimentMetrics(
        completion: @escaping @Sendable (Result<URL, Error>) -> Void
    ) {
        interactionQueue.async { [weak self] in
            guard let self,
                  let recording = self.experimentMetricsRecorder.snapshot() else {
                completion(.failure(CocoaError(.fileNoSuchFile)))
                return
            }
            self.experimentExportQueue.async {
                do {
                    let directory = FileManager.default.urls(
                        for: .applicationSupportDirectory,
                        in: .userDomainMask
                    )[0].appendingPathComponent("AuraMotion/Experiments/CursorRuns", isDirectory: true)
                    try FileManager.default.createDirectory(
                        at: directory,
                        withIntermediateDirectories: true
                    )
                    let destination = directory.appendingPathComponent(
                        "cursor_\(recording.sessionID).json"
                    )
                    let url = try CursorExperimentMetricsExporter.writeBundle(recording, to: destination)
                    completion(.success(url))
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }

    private func experimentCameraMetadata() -> CursorExperimentCameraMetadata? {
        guard let device = AVCaptureDevice.default(for: .video) else { return nil }
        let dimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        let frameDuration = device.activeVideoMinFrameDuration
        let nominalFPS = frameDuration.isValid && frameDuration.seconds.isFinite && frameDuration.seconds > 0
            ? 1 / frameDuration.seconds
            : nil
        return CursorExperimentCameraMetadata(
            name: device.localizedName,
            width: Int(dimensions.width),
            height: Int(dimensions.height),
            nominalFPS: nominalFPS
        )
    }

    private func recordExperimentFrame(
        timestamp: Double,
        sample: HandSample?,
        inferenceDuration: TimeInterval,
        mailboxWaitDuration: TimeInterval,
        droppedFrames: Int
    ) {
        guard hasStarted, experimentMetricsRecorder.isRecording else { return }
        let workerStatus = visionWorker.statusSnapshot
        let visionDiagnostics = workerStatus.lastDiagnostics
        let motionDiagnostics = cursorController.lastDiagnostics
        let motion = cursorController.hasValidAnchorForLastSample &&
                abs(motionDiagnostics.timestamp - timestamp) < 0.000_001
            ? CursorExperimentMotionSample(diagnostics: motionDiagnostics)
            : nil
        let region = visionDiagnostics?.regionOfInterest ?? workerStatus.currentROI
        let roi = CursorExperimentROI(
            rect: region,
            usedFullFrame: visionDiagnostics?.usedFullFrame ?? !workerStatus.roiEnabled,
            fallbackReason: visionDiagnostics?.usedFullFrame == true && workerStatus.roiEnabled
                ? visionDiagnostics?.detail
                : nil
        )
        experimentMetricsRecorder.record(frame: CursorExperimentFrame(
            timestamp: timestamp,
            source: .camera,
            sample: sample,
            state: stateMachine.currentState,
            inferenceDurationMilliseconds: inferenceDuration * 1000,
            mailboxWaitMilliseconds: mailboxWaitDuration * 1000,
            droppedFrames: droppedFrames,
            roi: roi,
            motion: motion
        ))
    }

    public func togglePause() {
        interactionQueue.async { [weak self] in
            guard let self = self else { return }
            self.stateMachine.isManualPaused.toggle()
            if self.stateMachine.isManualPaused {
                self.stateMachine.transition(to: .paused)
                self.outputCoordinator.emergencyRelease()
            } else {
                self.stateMachine.transition(to: .idle)
            }
        }
    }

    public func updateSettings(_ newSettings: AppSettings) {
        interactionQueue.async { [weak self] in
            guard let self = self else { return }
            var updatedSettings = newSettings
            updatedSettings.cursorExperiment = newSettings.cursorExperiment.normalized()
            let oldCursorSettings = self.currentSettings.cursorExperiment.normalized()
            let cursorSettingsChanged = oldCursorSettings != updatedSettings.cursorExperiment
            let cursorRebaseRequired = self.cursorController.requiresRebase(for: updatedSettings.cursorExperiment)
            let visionSettingsChanged = self.visionSettingsDiffer(
                oldCursorSettings,
                updatedSettings.cursorExperiment
            ) || self.currentSettings.isCameraMirrored != updatedSettings.isCameraMirrored
            let visionGeneration = visionSettingsChanged ? self.beginVisionReconfiguration() : nil
            var visibleCursor: CGPoint?
            if cursorRebaseRequired || visionSettingsChanged {
                visibleCursor = self.visibleCursorLocation(fallback: self.latestCursorLocation)
                // Drop queued pointer/drag work and release any held button
                // before replacing the mapping configuration.
                if !visionSettingsChanged {
                    self.outputCoordinator.emergencyRelease()
                }
                if visionSettingsChanged {
                    self.cursorController.freezeForVisionReconfiguration(at: visibleCursor)
                } else if cursorRebaseRequired {
                    self.cursorController.freeze(at: visibleCursor)
                }
                if self.stateMachine.currentState == .dragging || self.stateMachine.currentState == .pinchArmed {
                    self.stateMachine.reset()
                }
            }
            if cursorSettingsChanged {
                self.cursorController.reconfigure(
                    updatedSettings.cursorExperiment,
                    cursorPosition: visibleCursor ?? self.visibleCursorLocation(fallback: self.latestCursorLocation)
                )
            }
            if cursorRebaseRequired && !visionSettingsChanged {
                self.cursorController.setInteractionState(self.stateMachine.currentState, currentCursor: visibleCursor)
            }
            if cursorSettingsChanged {
                self.inputArbitrator.setMotionPriorityEnabled(updatedSettings.cursorExperiment.hasCursorExperiments)
            }
            self.currentSettings = updatedSettings
            self.visionWorker.isMirrored = updatedSettings.isCameraMirrored
            self.stateMachine.isClutchEnabled = updatedSettings.isClutchEnabled
            self.stateMachine.clutchDwellDuration = updatedSettings.clutchDwellTime
            self.stateMachine.scrollDetector.scrollController.isInertiaEnabled = updatedSettings.scrollInertiaEnabled
            self.stateMachine.isPalmSwipeEnabled = updatedSettings.isPalmSwipeEnabled
            AppLocalization.shared.setLanguage(updatedSettings.language)
            self.settingsRepository.saveSettings(updatedSettings)
            if let visionGeneration {
                self.reconfigureVisionWorker(
                    settings: updatedSettings.cursorExperiment,
                    generation: visionGeneration,
                    cursorPosition: visibleCursor
                )
            }
            self.publishHUDSnapshot()
        }
    }

    /// Changes only the HUD drawing preferences on the interaction queue.
    public func updateHUDJointDisplay(showNumbers: Bool? = nil, scale: Double? = nil, previewMirrored: Bool? = nil, highlightFirstRing: Bool? = nil) {
        interactionQueue.async { [weak self] in
            guard let self else { return }
            var updated = self.currentSettings
            if let showNumbers { updated.hudShowsJointNumbers = showNumbers }
            if let previewMirrored { updated.hudPreviewMirrored = previewMirrored }
            if let highlightFirstRing { updated.hudHighlightFirstRing = highlightFirstRing }
            if let scale, scale.isFinite { updated.hudSkeletonScale = min(3, max(0.5, scale)) }
            guard updated != self.currentSettings else { return }
            self.currentSettings = updated
            self.settingsRepository.saveSettings(updated)
            self.publishHUDSnapshot(force: true)
        }
    }

    private func visionSettingsDiffer(
        _ old: CursorExperimentSettings,
        _ new: CursorExperimentSettings
    ) -> Bool {
        old.visionROIEnabled != new.visionROIEnabled ||
            old.mediaPipeBenchmarkEnabled != new.mediaPipeBenchmarkEnabled ||
            ((old.visionROIEnabled || new.visionROIEnabled) &&
                (old.roiScale != new.roiScale || old.roiMinimumSize != new.roiMinimumSize))
    }

    private func beginVisionReconfiguration() -> UInt64 {
        visionConfigurationLock.lock()
        defer { visionConfigurationLock.unlock() }
        visionConfigurationGeneration &+= 1
        visionReconfigurationPending = true
        return visionConfigurationGeneration
    }

    private func isCurrentVisionReconfiguration(_ generation: UInt64) -> Bool {
        visionConfigurationLock.lock()
        defer { visionConfigurationLock.unlock() }
        return visionConfigurationGeneration == generation && visionReconfigurationPending
    }

    private func visionGenerationForNewCallback() -> UInt64? {
        visionConfigurationLock.lock()
        defer { visionConfigurationLock.unlock() }
        return visionReconfigurationPending ? nil : visionConfigurationGeneration
    }

    private func isCurrentVisionCallback(_ generation: UInt64) -> Bool {
        visionConfigurationLock.lock()
        defer { visionConfigurationLock.unlock() }
        return !visionReconfigurationPending && visionConfigurationGeneration == generation
    }

    private func finishVisionReconfiguration(_ generation: UInt64) -> Bool {
        visionConfigurationLock.lock()
        defer { visionConfigurationLock.unlock() }
        guard visionConfigurationGeneration == generation else { return false }
        visionReconfigurationPending = false
        return true
    }

    private var isVisionReconfigurationPending: Bool {
        visionConfigurationLock.lock()
        defer { visionConfigurationLock.unlock() }
        return visionReconfigurationPending
    }

    private func reconfigureVisionWorker(
        settings: CursorExperimentSettings,
        generation: UInt64,
        cursorPosition: CGPoint?
    ) {
        outputCoordinator.emergencyRelease { [weak self] in
            guard let self, self.isCurrentVisionReconfiguration(generation) else { return }
            self.visionWorker.reconfigure(settings) { [weak self] in
                guard let self else { return }
                self.interactionQueue.async {
                    guard self.finishVisionReconfiguration(generation) else { return }
                    self.continuityTracker.reset()
                    self.latestSnapshotSample = nil
                    self.latestRawCursorLocation = nil
                    let visibleCursor = self.visibleCursorLocation(
                        fallback: cursorPosition ?? self.latestCursorLocation
                    )
                    self.cursorController.rebaseAfterVisionReconfiguration(to: visibleCursor)
                    self.cursorController.setInteractionState(
                        self.stateMachine.currentState,
                        currentCursor: visibleCursor
                    )
                    self.latestCursorLocation = visibleCursor ?? self.latestCursorLocation
                    self.publishHUDSnapshot(force: true)
                }
            }
        }
    }

    public func updateCalibration(_ newCalibration: CalibrationProfile) {
        interactionQueue.async { [weak self] in
            guard let self = self else { return }
            self.currentCalibration = newCalibration
            self.cursorController.updateProfile(newCalibration)
            self.stateMachine.updateCalibration(newCalibration)
            self.settingsRepository.saveCalibration(newCalibration)
        }
    }

    // MARK: - CapturePipelineDelegate

    public func capturePipeline(_ pipeline: CapturePipeline, didOutput carrier: SampleCarrier) {
        #if DEBUG
        DebugFaceWorker.shared.submit(carrier)
        #endif
        performanceTracker.recordCaptureFrame(
            timestamp: carrier.hostPresentationTime,
            droppedFrames: pipeline.mailbox.droppedFrames
        )

        // Quality Ladder Stage 1: check if frame should be processed
        if qualityLadder.shouldProcessVisionFrame() {
            visionWorker.processMailbox(mailbox: pipeline.mailbox)
        }
    }

    public func capturePipelineDidInterrupted(_ pipeline: CapturePipeline) {
        interactionQueue.async { [weak self] in
            guard let self = self else { return }
            self.stateMachine.transition(to: .trackingLost)
            self.outputCoordinator.emergencyRelease()
        }
    }

    public func capturePipelineInterruptionEnded(_ pipeline: CapturePipeline) {
        interactionQueue.async { [weak self] in
            self?.stateMachine.transition(to: .idle)
        }
    }

    // MARK: - VisionInferenceWorkerDelegate

    public func visionWorker(
        _ worker: VisionInferenceWorker,
        didProduce sample: HandSample?,
        carrier: SampleCarrier,
        inferenceDuration: TimeInterval,
        mailboxWaitDuration: TimeInterval
    ) {
        guard let callbackGeneration = visionGenerationForNewCallback() else { return }
        let now = CACurrentMediaTime()

        // Dispatch all state transitions and coordinate mapping strictly to interactionQueue
        interactionQueue.async { [weak self] in
            guard let self = self else { return }
            guard self.isCurrentVisionCallback(callbackGeneration), self.hasStarted else { return }

            self.performanceTracker.recordInference(
                duration: inferenceDuration,
                mailboxWait: mailboxWaitDuration,
                pipelineLatency: now - carrier.hostPresentationTime,
                isEstimated: carrier.isEstimatedTime,
                timestamp: now
            )

            var processedSample: HandSample? = nil
            var mappedCursor: CGPoint? = nil
            self.latestRawCursorLocation = nil

            if let rawSample = sample {
                let tracked = self.continuityTracker.update(sample: rawSample, timestamp: now)
                processedSample = tracked
                self.landmarkRecorder.record(sample: tracked)

                let hasReliableTip = tracked.joint(.indexTip, minConfidence: 0.45) != nil
                if hasReliableTip || self.currentSettings.cursorExperiment.hasCursorExperiments {
                    mappedCursor = self.cursorController.processHand(tracked)
                    self.latestRawCursorLocation = self.cursorController.hasValidAnchorForLastSample
                        ? self.cursorController.lastDiagnostics.rawAnchor
                        : nil
                } else {
                    // Keep palm/shortcut detection alive without switching the cursor's
                    // tracking landmark, which caused large jumps on fingertip occlusion.
                    mappedCursor = self.latestCursorLocation
                }
            }

            self.latestSnapshotSample = processedSample
            self.latestCursorLocation = mappedCursor

            let epoch = self.inputArbitrator.currentEpoch()
            let canInject = self.permissionsManager.gate.canInject && self.inputArbitrator.isInjectionEnabled() && !self.isArbitrationCooldownActive

            self.stateMachine.processFrame(
                sample: processedSample,
                mappedCursorLocation: mappedCursor,
                currentEpoch: epoch,
                isInjectionAllowed: canInject
            )

            self.recordExperimentFrame(
                timestamp: carrier.hostPresentationTime,
                sample: processedSample,
                inferenceDuration: inferenceDuration,
                mailboxWaitDuration: mailboxWaitDuration,
                droppedFrames: self.capturePipeline.mailbox.droppedFrames
            )

            self.publishHUDSnapshot()
        }
    }

    // MARK: - GestureStateMachineDelegate

    public func stateMachine(_ fsm: GestureStateMachine, didTransitionTo state: GestureState) {
        let visibleCursor = visibleCursorLocation(fallback: latestCursorLocation)
        cursorController.setInteractionState(state, currentCursor: visibleCursor)
        if currentSettings.cursorExperiment.hasCursorExperiments && state != .pointer && state != .dragging {
            latestCursorLocation = visibleCursor ?? latestCursorLocation
        }
        publishHUDSnapshot()
    }

    public func stateMachine(_ fsm: GestureStateMachine, emitMoveTo location: CGPoint, epoch: UInt64) {
        let outputLocation = cursorController.consumeResumeMoveOverride() ?? location
        latestCursorLocation = outputLocation
        outputCoordinator.enqueueMove(to: outputLocation, epoch: epoch)
    }

    public func stateMachine(_ fsm: GestureStateMachine, emitClickAt anchor: CGPoint, epoch: UInt64) {
        clickFeedbackID &+= 1
        clickFeedbackLocation = currentSettings.showClickFeedback ? anchor : nil
        recognize("Click recognized")
        outputCoordinator.enqueueClick(at: anchor, epoch: epoch)
    }

    public func stateMachine(_ fsm: GestureStateMachine, emitDragStartAt anchor: CGPoint, epoch: UInt64) {
        outputCoordinator.enqueueDragStart(at: anchor, epoch: epoch)
    }

    public func stateMachine(_ fsm: GestureStateMachine, emitDragMoveTo location: CGPoint, epoch: UInt64) {
        latestCursorLocation = location
        outputCoordinator.enqueueDragMove(to: location, epoch: epoch)
    }

    public func stateMachine(_ fsm: GestureStateMachine, emitDragEndAt location: CGPoint, epoch: UInt64) {
        outputCoordinator.enqueueDragEnd(at: location, epoch: epoch)
    }

    public func stateMachine(_ fsm: GestureStateMachine, emitScroll delta: ScrollDelta, epoch: UInt64) {
        outputCoordinator.enqueueScroll(delta: delta, epoch: epoch)
    }

    public func stateMachine(_ fsm: GestureStateMachine, emitSwipe direction: PalmSwipeDirection, epoch: UInt64) {
        recognize(direction == .left ? "Left swipe recognized" : "Right swipe recognized")
        outputCoordinator.enqueueSwipe(direction: direction, action: currentSettings.swipeAction, epoch: epoch)
    }

    public func stateMachine(_ fsm: GestureStateMachine, emitShortcut shortcut: FingerShortcut, epoch: UInt64) {
        recognize(shortcut == .copy ? "Copy recognized" : "Paste recognized")
        outputCoordinator.enqueueShortcut(shortcut, epoch: epoch)
    }

    public func stateMachine(_ fsm: GestureStateMachine, emitCommand command: GestureCommand, at target: CGPoint, epoch: UInt64) {
        recognize("\(command.title) recognized")
        guard command == .snapLeft || command == .snapRight else {
            outputCoordinator.enqueueCommand(command, at: target, epoch: epoch)
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, let app = NSWorkspace.shared.frontmostApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            let pid = app.processIdentifier
            let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
            let cocoaPoint = CGPoint(x: target.x, y: primaryHeight - target.y)
            guard let screen = NSScreen.screens.first(where: { $0.frame.contains(cocoaPoint) }) ?? NSScreen.main else { return }
            let visible = screen.visibleFrame
            let bounds = CGRect(x: visible.minX, y: primaryHeight - visible.maxY, width: visible.width, height: visible.height)
            self.outputCoordinator.enqueueValidatedAction(epoch: epoch) { [weak self] in
                let result = WindowSnapper.apply(pid: pid, bounds: bounds, right: command == .snapRight)
                self?.interactionQueue.async { [weak self] in self?.recognize(result) }
            }
        }
    }

    public func stateMachineTriggerEmergencyRelease(_ fsm: GestureStateMachine) {
        outputCoordinator.emergencyRelease()
    }

    // MARK: - InputArbitratorDelegate & Strict 4-Step Re-Enable Sequence

    public func arbitratorDidDetectExternalInput(epoch: UInt64) {
        interactionQueue.async { [weak self] in
            guard let self = self else { return }

            // Step 1: Immediately drop pending work and release all buttons with confirmation
            self.isArbitrationCooldownActive = true
            self.isReleaseConfirmed = false
            self.isCooldownElapsed = false
            self.stateMachine.transition(to: .trackingLost)

            StructuredLogger.arbitration.notice("External physical input detected. Control yielded.")

            // Execute emergency release with completion barrier
            self.outputCoordinator.emergencyRelease { [weak self] in
                guard let self = self else { return }
                self.interactionQueue.async {
                    self.isReleaseConfirmed = true
                    self.checkAndReenableAfterArbitration()
                }
            }

            // Start arbitration cooldown timer
            let cooldown = self.currentSettings.arbitrationCooldownSeconds
            self.safetyQueue.asyncAfter(deadline: .now() + cooldown) { [weak self] in
                guard let self = self else { return }
                self.interactionQueue.async {
                    self.isCooldownElapsed = true
                    self.checkAndReenableAfterArbitration()
                }
            }
        }
    }

    public func arbitratorDidTimeoutExcessively() {
        StructuredLogger.arbitration.warning("CGEventTap disabled due to excessive timeouts. Running in degraded safe mode.")
    }

    /// Strict 4-Step Re-Enable Sequence:
    /// 1. Cooldown elapsed
    /// 2. releaseAllButtons() confirmed completed on output coordinator
    /// 3. Output queue drained
    /// 4. Ready for engagement clutch reacquisition
    private func checkAndReenableAfterArbitration() {
        guard isCooldownElapsed && isReleaseConfirmed else {
            return
        }

        isArbitrationCooldownActive = false
        isReleaseConfirmed = false
        isCooldownElapsed = false
        stateMachine.reset()

        // Re-enable atomic state and bump epoch
        let _ = inputArbitrator.reenableInjection()
        StructuredLogger.arbitration.notice("Arbitration cooldown ended and release confirmed. Ready for clutch reacquisition.")
    }

    private func publishHUDSnapshot(force: Bool = false) {
        let now = CACurrentMediaTime()
        guard force || now - lastHUDPublishTime >= 1.0 / 30.0 else { return }
        lastHUDPublishTime = now
        // Use cached permission snapshot — zero IPC on the steady-state path.
        let cachedPerms = permissionsManager.gate.cachedSnapshot
        var snapshot = HUDSnapshot(
            state: stateMachine.currentState,
            sample: latestSnapshotSample,
            performance: performanceTracker.snapshot(),
            thermalStage: qualityLadder.activeStage,
            permissions: cachedPerms,
            isArbitrationActive: inputArbitrator.isTapActive && !isArbitrationCooldownActive,
            cursorLocation: latestCursorLocation
        )
        if calibrationPreviousPause != nil {
            snapshot.feedback = "Calibration — control paused"
        } else if !cachedPerms.isCameraAuthorized {
            snapshot.feedback = cachedPerms.statusLabel
        } else if !cachedPerms.canInjectInput {
            snapshot.feedback = cachedPerms.statusLabel ?? "Input control is blocked"
        } else if isArbitrationCooldownActive {
            snapshot.feedback = "Mouse in use — gesture control waiting"
        } else if now - recognitionTime < 1.2 {
            snapshot.feedback = recognitionFeedback
        } else if stateMachine.shortcutDetector.isHoldingContact {
            snapshot.feedback = "Hold steady, then separate fingertips"
        } else if stateMachine.commandMenu.isOpen {
            snapshot.feedback = "Point to a command, then pinch"
        } else if stateMachine.currentState == .palmRest {
            snapshot.feedback = "Hold palm still to open commands"
        }
        snapshot.commandMenu = stateMachine.commandMenu.snapshot
        snapshot.showHUD = currentSettings.showHUD
        snapshot.hudShowsCamera = currentSettings.hudShowsCamera
        snapshot.hudPreviewMirrored = currentSettings.hudPreviewMirrored
        snapshot.isCameraMirrored = currentSettings.isCameraMirrored
        snapshot.cameraAspectRatio = capturePipeline.previewAspectRatio
        snapshot.isVideoDataMirrored = capturePipeline.isVideoDataMirrored
        snapshot.hudShowsJointNumbers = currentSettings.hudShowsJointNumbers
        snapshot.hudHighlightFirstRing = currentSettings.hudHighlightFirstRing
        snapshot.hudSkeletonScale = currentSettings.hudSkeletonScale
        snapshot.rawCursorLocation = latestRawCursorLocation
        snapshot.cursorExperimentStatus = cursorController.cursorExperimentStatus
        snapshot.cursorDiagnostics = cursorController.lastDiagnostics
        snapshot.cursorExperimentSettings = currentSettings.cursorExperiment
        snapshot.visionWorkerStatus = visionWorker.statusSnapshot
        snapshot.isVisionReconfigurationPending = isVisionReconfigurationPending
        snapshot.clickFeedbackID = clickFeedbackID
        snapshot.clickFeedbackLocation = currentSettings.showClickFeedback ? clickFeedbackLocation : nil
        let publishedSnapshot = snapshot
        DispatchQueue.main.async { [weak self] in
            self?.observer?.environmentDidUpdateHUDSnapshot(publishedSnapshot)
        }
    }
}
