import AppKit
import SwiftUI
import AuraMotionCore

@MainActor
public final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var hudWindow: FloatingHUDWindow?
    private var diagnosticsWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var calibrationWindow: NSWindow?
    private var movementCalibrationWindow: NSWindow?

    public init(hudWindow: FloatingHUDWindow) {
        self.hudWindow = hudWindow
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChange),
            name: AppLocalization.languageDidChangeNotification,
            object: nil
        )
        setupMenu()
    }

    public func showSettingsWindow() {
        openSettings()
    }

    private func setupMenu() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "hand.point.up.fill", accessibilityDescription: "AuraMotion Pro")
        }

        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: "AuraMotion Pro", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        let pauseItem = NSMenuItem(title: L10n.tr("Pause Gesture Control"), action: #selector(togglePause), keyEquivalent: "p")
        pauseItem.target = self
        menu.addItem(pauseItem)

        let hudItem = NSMenuItem(title: L10n.tr("Toggle Floating HUD"), action: #selector(toggleHUD), keyEquivalent: "h")
        hudItem.target = self
        menu.addItem(hudItem)

        menu.addItem(NSMenuItem.separator())

        let diagItem = NSMenuItem(title: L10n.tr("Diagnostics & Telemetry..."), action: #selector(openDiagnostics), keyEquivalent: "d")
        diagItem.target = self
        menu.addItem(diagItem)

        let calItem = NSMenuItem(title: L10n.tr("Calibration..."), action: #selector(openCalibration), keyEquivalent: "c")
        calItem.target = self
        menu.addItem(calItem)
        let movementItem = NSMenuItem(title: L10n.tr("Movement Calibration..."), action: #selector(openMovementCalibration), keyEquivalent: "")
        movementItem.target = self
        menu.addItem(movementItem)

        let settingsItem = NSMenuItem(title: L10n.tr("Settings..."), action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: L10n.tr("Quit AuraMotion"), action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        for (window, title) in [(settingsWindow, "AuraMotion Settings"),
                                (diagnosticsWindow, "AuraMotion Diagnostics"),
                                (calibrationWindow, "AuraMotion Calibration"),
                                (movementCalibrationWindow, "AuraMotion Movement Calibration")] {
            window?.title = L10n.tr(title)
        }
    }

    @objc private func togglePause() {
        AppEnvironment.shared.togglePause()
    }

    @objc private func toggleHUD() {
        var settings = AppEnvironment.shared.currentSettings
        settings.showHUD.toggle()
        AppEnvironment.shared.updateSettings(settings)
    }

    @objc private func openDiagnostics() {
        if diagnosticsWindow == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 100, y: 100, width: 420, height: 640),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            win.identifier = NSUserInterfaceItemIdentifier("AuraMotion Diagnostics")
            win.title = L10n.tr("AuraMotion Diagnostics")
            win.isReleasedWhenClosed = false
            win.contentView = NSHostingView(rootView: DiagnosticsView())
            diagnosticsWindow = win
        }
        diagnosticsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 150, y: 150, width: 500, height: 560),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            win.identifier = NSUserInterfaceItemIdentifier("AuraMotion Settings")
            win.title = L10n.tr("AuraMotion Settings")
            win.isReleasedWhenClosed = false
            win.contentView = NSHostingView(rootView: SettingsView())
            settingsWindow = win
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func openCalibration() {
        movementCalibrationWindow?.close()
        if calibrationWindow == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 200, y: 200, width: 420, height: 560),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            win.identifier = NSUserInterfaceItemIdentifier("AuraMotion Calibration")
            win.title = L10n.tr("AuraMotion Calibration")
            win.isReleasedWhenClosed = false
            win.contentView = NSHostingView(rootView: CalibrationView())
            calibrationWindow = win
        }
        calibrationWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func languageDidChange() {
        setupMenu()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func openMovementCalibration() {
        calibrationWindow?.close()
        if movementCalibrationWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 440, height: 390),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.identifier = NSUserInterfaceItemIdentifier("AuraMotion Movement Calibration")
            window.title = L10n.tr("AuraMotion Movement Calibration")
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: MovementCalibrationView())
            movementCalibrationWindow = window
        }
        movementCalibrationWindow?.makeKeyAndOrderFront(nil)
    }
}
