import AppKit
import SwiftUI
import AuraMotionCore

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, AppEnvironmentObserver {
    private var statusItemController: StatusItemController?
    private var hudWindow: FloatingHUDWindow?
    private let commandMenuWindow = CommandMenuWindowController()
    private let clickFeedback = ClickFeedbackWindowController()
    private var lastFeedbackID: UInt64 = 0
    #if DEBUG
    private let semanticHighlight = AccessibilityTargetHighlightWindow()
    private let gazeProjection = GazeProjectionWindow()
    private var rawProjectionPoint: CGPoint?
    private var projectionCandidate: AccessibilityTargetSnapshot?
    private var projectionCandidateState = false
    private var projectionAllowed = true
    private var gazeProjectionObserver: NSObjectProtocol?
    private var semanticObserver: NSObjectProtocol?
    #endif

    public func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        gazeProjectionObserver = NotificationCenter.default.addObserver(forName: GazeDebugController.gazeProjectionNotification, object: nil, queue: .main) { [weak self] note in
            let point = note.userInfo?["point"] as? CGPoint
            let suppressed = note.userInfo?["suppressed"] as? Bool ?? false
            MainActor.assumeIsolated {
                guard let self else { return }
                self.rawProjectionPoint = point; self.projectionAllowed = !suppressed
                self.refreshGazeProjection()
            }
        }
        semanticObserver = NotificationCenter.default.addObserver(forName: AccessibilityTargetResolver.notification, object: nil, queue: .main) { [weak self] note in
            let target = note.userInfo?["target"] as? AccessibilityTargetSnapshot
            let state = note.userInfo?["state"] as? String ?? ""
            MainActor.assumeIsolated {
                guard let self else { return }
                self.semanticHighlight.update(target, state: state)
                self.projectionCandidate = target; self.projectionCandidateState = state.hasPrefix("candidate")
                self.refreshGazeProjection()
            }
        }
        #endif
        // 1. Create Floating HUD Panel
        let screenRect = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let savedWidth = UserDefaults.standard.double(forKey: "hudWindowWidth")
        let savedHeight = UserDefaults.standard.double(forKey: "hudWindowHeight")
        let width = savedWidth.isFinite && savedWidth >= 220 ? min(savedWidth, screenRect.width) : min(480, screenRect.width)
        let height = savedHeight.isFinite && savedHeight >= 200 ? min(savedHeight, screenRect.height) : min(360, screenRect.height)
        let hudRect = NSRect(x: screenRect.maxX - width - 20, y: screenRect.maxY - height - 20, width: width, height: height)
        let hud = FloatingHUDWindow(contentRect: hudRect)
        hud.contentView = NSHostingView(rootView: HUDView(
            onResize: { [weak hud] translation, finished in
                hud?.resizeFromHandle(translation: translation, finished: finished)
            },
            onMove: { [weak hud] translation, finished in
                hud?.moveFromHeader(translation: translation, finished: finished)
            },
            onRestoreSize: { [weak hud] in hud?.restoreDefaultSize() }
        ))
        if AppEnvironment.shared.currentSettings.showHUD { hud.orderFrontRegardless() }
        self.hudWindow = hud

        // 2. Create Status Item
        self.statusItemController = StatusItemController(hudWindow: hud)

        // Post-event access is required for cursor and keyboard output. Keep
        // the request controls visible when macOS has not granted that access.
        if CommandLine.arguments.contains("--cursor-experiments") ||
            !AppEnvironment.shared.permissionsManager.checkPermissions().isPostEventAuthorized {
            self.statusItemController?.showSettingsWindow()
        }

        // 3. Register environment observer
        let env = AppEnvironment.shared
        env.observer = self

        // 4. Register Sleep/Wake notifications for honest safety guarantees
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        // 5. Start environment
        env.start()
        #if DEBUG
        ExperimentalGazeEstimationWorker.shared.setEnabled(true)
        #endif
    }

    #if DEBUG
    private func refreshGazeProjection() {
        let point = GazeProjectionLink.position(gaze: rawProjectionPoint, candidate: projectionCandidate,
                                                isCandidate: projectionCandidateState, enabled: projectionAllowed)
        gazeProjection.update(point)
    }
    #endif

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusItemController?.showSettingsWindow()
        sender.activate(ignoringOtherApps: true)
        return true
    }

    public func applicationWillTerminate(_ notification: Notification) {
        hudWindow?.saveHUDSize()
        AppEnvironment.shared.stop()
    }

    @objc private func handleWillSleep() {
        AppEnvironment.shared.outputCoordinator.emergencyRelease()
        let env = AppEnvironment.shared
        env.interactionQueue.async { env.stateMachine.transition(to: .trackingLost) }
    }

    @objc private func handleDidWake() {
        let env = AppEnvironment.shared
        env.interactionQueue.async { env.stateMachine.transition(to: .idle) }
    }

    // MARK: - AppEnvironmentObserver

    nonisolated public func environmentDidUpdateHUDSnapshot(_ snapshot: HUDSnapshot) {
        NotificationCenter.default.post(name: NSNotification.Name("HUDSnapshotUpdated"), object: snapshot)
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.commandMenuWindow.update(snapshot.commandMenu)
            if snapshot.showHUD {
                if self.hudWindow?.isVisible == false { self.hudWindow?.orderFrontRegardless() }
            } else { self.hudWindow?.orderOut(nil) }
            if snapshot.clickFeedbackID != self.lastFeedbackID {
                self.lastFeedbackID = snapshot.clickFeedbackID
                if let point = snapshot.clickFeedbackLocation { self.clickFeedback.show(at: point) }
            }
            if snapshot.clickFeedbackLocation == nil { self.clickFeedback.hide() }
        }
    }
}
