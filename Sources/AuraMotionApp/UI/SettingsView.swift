import SwiftUI
import AppKit
import AuraMotionCore

public struct SettingsView: View {
    @State private var settings = AppEnvironment.shared.currentSettings
    @State private var permissions = AppEnvironment.shared.permissionsManager.checkPermissions()
    @State private var postEventRequestMessage: String?
    @State private var postEventRequestSucceeded = false
    @State private var isRequestingPostEventAccess = false

    public init() {}

    public var body: some View {
        Form {
            Section(header: Text("Permissions Status")) {
                HStack {
                    Text("Camera Access:")
                    Spacer()
                    Text(permissions.isCameraAuthorized ? "Granted" : "Denied")
                        .foregroundColor(permissions.isCameraAuthorized ? .green : .red)
                    if !permissions.isCameraAuthorized {
                        Button("Open Settings") {
                            AppEnvironment.shared.permissionsManager.openSystemSettingsCamera()
                        }
                    }
                }
                HStack {
                    Text("Computer Control:")
                    Spacer()
                    Text(permissions.isAccessibilityTrusted ? "Granted" : "Denied")
                        .foregroundColor(permissions.isAccessibilityTrusted ? .green : .red)
                    if !permissions.isAccessibilityTrusted {
                        Button("Request") {
                            NSApplication.shared.activate(ignoringOtherApps: true)
                            AppEnvironment.shared.permissionsManager.requestAccessibilityIfNeeded()
                            AppEnvironment.shared.permissionsManager.openSystemSettingsAccessibility()
                        }
                    }
                }
                HStack {
                    Text("Input Event Posting:")
                    Spacer()
                    Text(permissions.isPostEventAuthorized ? "Granted" : "Required")
                        .foregroundColor(permissions.isPostEventAuthorized ? .green : .orange)
                    if !permissions.isPostEventAuthorized {
                        Button(isRequestingPostEventAccess ? "Requesting…" : "Request") {
                            requestPostEventAccess()
                        }
                        .disabled(isRequestingPostEventAccess)
                    }
                }
                if let postEventRequestMessage {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(postEventRequestMessage)
                            .font(.caption)
                            .foregroundColor(postEventRequestSucceeded ? .green : .orange)
                            .fixedSize(horizontal: false, vertical: true)
                        if !postEventRequestSucceeded {
                            Button("Open Control Settings") {
                                AppEnvironment.shared.permissionsManager.openSystemSettingsAccessibility()
                            }
                        }
                    }
                }
                HStack {
                    Text("Input Monitoring (optional):")
                    Spacer()
                    Text(permissions.isListenEventAuthorized ? "Granted" : "Not granted")
                        .foregroundColor(permissions.isListenEventAuthorized ? .green : .secondary)
                    if !permissions.isListenEventAuthorized {
                        Button("Request") {
                            AppEnvironment.shared.permissionsManager.requestListenEventAccess()
                            refreshPermissions()
                        }
                    }
                }
            }

            Section(header: Text("Interaction Preferences")) {
                Toggle("Mirror Camera Feed", isOn: $settings.isCameraMirrored)
                Toggle("Enable Engagement Clutch (Ready Pose)", isOn: $settings.isClutchEnabled)
                if settings.isClutchEnabled {
                    HStack {
                        Text("Activation Delay:")
                        Slider(value: $settings.clutchDwellTime, in: 0...0.30, step: 0.01)
                        Text(String(format: "%.0f ms", settings.clutchDwellTime * 1000))
                            .monospacedDigit()
                    }
                }
                Toggle("Enable Scroll Inertia", isOn: $settings.scrollInertiaEnabled)
                Toggle("Enable Palm Swipe Switching", isOn: $settings.isPalmSwipeEnabled)
                if settings.isPalmSwipeEnabled {
                    Picker("Swipe Action:", selection: $settings.swipeAction) {
                        ForEach(SwipeActionType.allCases, id: \.self) { action in
                            Text(action.displayName).tag(action)
                        }
                    }
                }
            }

            Section(header: Text("HUD & Feedback")) {
                Toggle("Show Floating HUD", isOn: $settings.showHUD)
                Toggle("Show Click Feedback Ripples", isOn: $settings.showClickFeedback)
            }

            Section(header: Text("Safety & Arbitration")) {
                HStack {
                    Text("Arbitration Cooldown:")
                    Slider(value: $settings.arbitrationCooldownSeconds, in: 0.5...3.0, step: 0.25)
                    Text(String(format: "%.1fs", settings.arbitrationCooldownSeconds))
                        .monospacedDigit()
                }
            }
        }
        .padding(20)
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
                    postEventRequestMessage = "Input event posting is authorized."
                }
            } else {
                refreshPermissions()
            }
        }
    }

    private func refreshPermissions() {
        permissions = AppEnvironment.shared.permissionsManager.checkPermissions()
    }

    private func requestPostEventAccess() {
        guard !isRequestingPostEventAccess else { return }

        NSApplication.shared.activate(ignoringOtherApps: true)
        isRequestingPostEventAccess = true
        postEventRequestSucceeded = false
        postEventRequestMessage = "Requesting input event access from macOS…"

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            let requestGranted = AppEnvironment.shared.permissionsManager.requestPostEventAccess()
            let updatedPermissions = AppEnvironment.shared.permissionsManager.checkPermissions()
            permissions = updatedPermissions
            isRequestingPostEventAccess = false
            postEventRequestSucceeded = updatedPermissions.isPostEventAuthorized

            if updatedPermissions.isPostEventAuthorized {
                postEventRequestMessage = "Input event posting is authorized."
            } else if requestGranted {
                postEventRequestMessage = "macOS returned from the request, but event posting is not active yet. Approve any system alert, then wait for the status to refresh."
            } else {
                let pane = AppEnvironment.shared.permissionsManager.controlPermissionSettingsName
                postEventRequestMessage = "macOS has not granted computer input control. Enable AuraMotion in Privacy & Security → \(pane). If its switch is already on after an app update, turn it off and on, then quit and reopen AuraMotion."
                AppEnvironment.shared.permissionsManager.openSystemSettingsAccessibility()
            }
        }
    }
}
