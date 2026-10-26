import SwiftUI
import AuraMotionCore

struct MovementCalibrationView: View {
    @ObservedObject private var localization = AppLocalization.shared
    @State private var session = MovementCalibration()
    @State private var started = false
    @State private var collecting = false
    @State private var notice = ""
    var body: some View {
        VStack(spacing: 16) {
            Text(L10n.tr("Personalize Cursor Movement")).font(.title2)
            Text(L10n.tr("Three short recordings learn your resting tremor and movement speeds. Control pauses during setup; camera video is not saved."))
                .font(.callout).foregroundStyle(.secondary)
            if !started {
                Button(L10n.tr("Start movement setup")) {
                    session = MovementCalibration(); notice = ""; started = true
                    AppEnvironment.shared.setCalibrationActive(true)
                }
            } else if !session.isComplete {
                Text(L10n.tr("Step {current} of 3", replacing: ["{current}": "\(session.step.rawValue + 1)"])).font(.headline)
                Text(session.step.instruction)
                ProgressView(value: Double(session.count), total: 60)
                Text(L10n.tr("{count} / 60 clear observations", replacing: ["{count}": "\(session.count)"])).font(.caption)
                if let message = session.message { Text(L10n.tr(message)).foregroundStyle(.orange) }
                Button(L10n.tr(collecting ? "Recording…" : "Record this movement")) { collecting = true }
                    .disabled(collecting)
            } else {
                Text(L10n.tr("Your movement profile is ready."))
                Button(L10n.tr("Save movement profile")) {
                    let env = AppEnvironment.shared
                    guard let profile = session.applying(to: env.currentCalibration) else { return }
                    env.updateCalibration(profile)
                    finish()
                    notice = "Saved. Your personalized cursor response is active."
                }
            }
            if started { Button(L10n.tr("Cancel")) { finish() } }
            if !notice.isEmpty { Text(L10n.tr(notice)).font(.callout) }
        }
        .padding(24).frame(width: 440, height: 390)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("HUDSnapshotUpdated"))) { note in
            guard collecting, let snapshot = note.object as? HUDSnapshot, let sample = snapshot.sample else { return }
            if session.add(sample) { collecting = false }
        }
        .onDisappear { finish() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
            if (note.object as? NSWindow)?.title == "AuraMotion Movement Calibration" { finish() }
        }
    }
    private func finish() {
        guard started else { return }
        collecting = false; started = false
        AppEnvironment.shared.setCalibrationActive(false)
    }
}
