import AppKit
import SwiftUI
import AuraMotionCore

public struct SettingsView: View {
    @ObservedObject private var localization = AppLocalization.shared
    @State private var settings = AppEnvironment.shared.currentSettings
    @State private var permissions = AppEnvironment.shared.permissionsManager.checkPermissions()
    @State private var postEventRequestMessageKey: String?
    @State private var postEventRequestPane: String?
    @State private var postEventRequestSucceeded = false
    @State private var isRequestingPostEventAccess = false

    public init() {}

    public var body: some View {
        let _ = localization.language
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 12) {
                GroupBox(label: Text(L10n.tr("Language"))) {
                    Picker(L10n.tr("Language"), selection: $settings.language) {
                        ForEach(AppLanguage.allCases, id: \.self) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                permissionsSection
                interactionSection
                feedbackSection
                safetySection

                CursorExperimentPanel(
                    settings: cursorExperimentBinding,
                    isCameraAuthorized: permissions.isCameraAuthorized
                )
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 500, height: 560)
        .onChange(of: settings) { _, newSettings in
            AppEnvironment.shared.updateSettings(newSettings)
        }
        .onAppear {
            settings = AppEnvironment.shared.currentSettings
            refreshPermissions()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissions()
        }
        .onReceive(NotificationCenter.default.publisher(for: .auraMotionPermissionsDidChange)) { note in
            if let state = note.object as? PermissionsState {
                permissions = state
                if state.isPostEventAuthorized {
                    postEventRequestSucceeded = true
                    postEventRequestMessageKey = "Input event posting is authorized."
                    postEventRequestPane = nil
                }
            } else {
                refreshPermissions()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("HUDSnapshotUpdated")).receive(on: DispatchQueue.main)) { note in
            guard let snapshot = note.object as? HUDSnapshot else { return }
            if settings.hudShowsJointNumbers != snapshot.hudShowsJointNumbers {
                settings.hudShowsJointNumbers = snapshot.hudShowsJointNumbers
            }
            if settings.hudSkeletonScale != snapshot.hudSkeletonScale {
                settings.hudSkeletonScale = snapshot.hudSkeletonScale
            }
        }
    }

    private var cursorExperimentBinding: Binding<CursorExperimentSettings> {
        Binding(
            get: { settings.cursorExperiment },
            set: { settings.cursorExperiment = $0 }
        )
    }

    private var permissionsSection: some View {
        GroupBox(label: Text(L10n.tr("Permissions Status"))) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L10n.tr("Camera Access:"))
                    Spacer()
                    Text(L10n.tr(permissions.isCameraAuthorized ? "Granted" : "Denied"))
                        .foregroundStyle(permissions.isCameraAuthorized ? .green : .red)
                    if !permissions.isCameraAuthorized {
                        Button(L10n.tr("Open Settings")) {
                            AppEnvironment.shared.permissionsManager.openSystemSettingsCamera()
                        }
                    }
                }

                HStack {
                    Text(L10n.tr("Computer Control:"))
                    Spacer()
                    Text(L10n.tr(permissions.isAccessibilityTrusted ? "Granted" : "Denied"))
                        .foregroundStyle(permissions.isAccessibilityTrusted ? .green : .red)
                    if !permissions.isAccessibilityTrusted {
                        Button(L10n.tr("Request")) {
                            NSApplication.shared.activate(ignoringOtherApps: true)
                            AppEnvironment.shared.permissionsManager.requestAccessibilityIfNeeded()
                            AppEnvironment.shared.permissionsManager.openSystemSettingsAccessibility()
                        }
                    }
                }

                HStack {
                    Text(L10n.tr("Input Event Posting:"))
                    Spacer()
                    Text(L10n.tr(permissions.isPostEventAuthorized ? "Granted" : "Required"))
                        .foregroundStyle(permissions.isPostEventAuthorized ? .green : .orange)
                    if !permissions.isPostEventAuthorized {
                        Button(L10n.tr(isRequestingPostEventAccess ? "Requesting…" : "Request")) {
                            requestPostEventAccess()
                        }
                        .disabled(isRequestingPostEventAccess)
                    }
                }

                if let postEventRequestMessageKey {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(localizedPostEventRequestMessage(postEventRequestMessageKey))
                            .font(.caption)
                            .foregroundStyle(postEventRequestSucceeded ? .green : .orange)
                            .fixedSize(horizontal: false, vertical: true)
                        if !postEventRequestSucceeded {
                            Button(L10n.tr("Open Control Settings")) {
                                AppEnvironment.shared.permissionsManager.openSystemSettingsAccessibility()
                            }
                        }
                    }
                }

                HStack {
                    Text(L10n.tr("Input Monitoring (optional):"))
                    Spacer()
                    Text(L10n.tr(permissions.isListenEventAuthorized ? "Granted" : "Not granted"))
                        .foregroundStyle(permissions.isListenEventAuthorized ? Color.green : Color.gray)
                    if !permissions.isListenEventAuthorized {
                        Button(L10n.tr("Request")) {
                            AppEnvironment.shared.permissionsManager.requestListenEventAccess()
                            refreshPermissions()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var interactionSection: some View {
        GroupBox(label: Text(L10n.tr("Interaction Preferences"))) {
            VStack(alignment: .leading, spacing: 6) {
                Toggle(L10n.tr("Mirror Camera Feed"), isOn: $settings.isCameraMirrored)
                Toggle(L10n.tr("Enable Engagement Clutch (Ready Pose)"), isOn: $settings.isClutchEnabled)
                if settings.isClutchEnabled {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(L10n.tr("Activation Delay:"))
                            Spacer()
                            Text(String(format: L10n.tr("%.0f ms"), settings.clutchDwellTime * 1000))
                                .monospacedDigit()
                        }
                        Slider(value: $settings.clutchDwellTime, in: 0...0.30, step: 0.01)
                    }
                }
                Toggle(L10n.tr("Enable Scroll Inertia"), isOn: $settings.scrollInertiaEnabled)
                Toggle(L10n.tr("Enable Palm Swipe Switching"), isOn: $settings.isPalmSwipeEnabled)
                if settings.isPalmSwipeEnabled {
                    Picker(L10n.tr("Swipe Action:"), selection: $settings.swipeAction) {
                        ForEach(SwipeActionType.allCases, id: \.self) { action in
                            Text(action.localizedDisplayName).tag(action)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var feedbackSection: some View {
        GroupBox(label: Text(L10n.tr("HUD & Feedback"))) {
            VStack(alignment: .leading, spacing: 6) {
                Toggle(L10n.tr("Show Floating HUD"), isOn: $settings.showHUD)
                Picker(L10n.tr("HUD Display Mode"), selection: $settings.hudShowsCamera) {
                    Text(L10n.tr("Hand Skeleton Only")).tag(false)
                    Text(L10n.tr("Camera and Hand Skeleton")).tag(true)
                }
                Toggle(L10n.tr("Show Click Feedback Ripples"), isOn: $settings.showClickFeedback)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var safetySection: some View {
        GroupBox(label: Text(L10n.tr("Safety & Arbitration"))) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(L10n.tr("Arbitration Cooldown:"))
                    Spacer()
                    Text(String(format: L10n.tr("%.1f s"), settings.arbitrationCooldownSeconds))
                        .monospacedDigit()
                }
                Slider(value: $settings.arbitrationCooldownSeconds, in: 0.5...3.0, step: 0.25)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func localizedPostEventRequestMessage(_ key: String) -> String {
        if let postEventRequestPane {
            return L10n.tr(key, replacing: ["{pane}": postEventRequestPane])
        }
        return L10n.tr(key)
    }

    private func refreshPermissions() {
        permissions = AppEnvironment.shared.permissionsManager.checkPermissions()
    }

    private func requestPostEventAccess() {
        guard !isRequestingPostEventAccess else { return }

        NSApplication.shared.activate(ignoringOtherApps: true)
        isRequestingPostEventAccess = true
        postEventRequestSucceeded = false
        postEventRequestMessageKey = "Requesting input event access from macOS…"
        postEventRequestPane = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            let requestGranted = AppEnvironment.shared.permissionsManager.requestPostEventAccess()
            let updatedPermissions = AppEnvironment.shared.permissionsManager.checkPermissions()
            permissions = updatedPermissions
            isRequestingPostEventAccess = false
            postEventRequestSucceeded = updatedPermissions.isPostEventAuthorized

            if updatedPermissions.isPostEventAuthorized {
                postEventRequestMessageKey = "Input event posting is authorized."
                postEventRequestPane = nil
            } else if requestGranted {
                postEventRequestMessageKey = "macOS returned from the request, but event posting is not active yet. Approve any system alert, then wait for the status to refresh."
                postEventRequestPane = nil
            } else {
                postEventRequestPane = AppEnvironment.shared.permissionsManager.controlPermissionSettingsName
                postEventRequestMessageKey = "macOS has not granted computer input control. Enable AuraMotion in Privacy & Security → {pane}. If its switch is already on after an app update, turn it off and on, then quit and reopen AuraMotion."
                AppEnvironment.shared.permissionsManager.openSystemSettingsAccessibility()
            }
        }
    }
}
