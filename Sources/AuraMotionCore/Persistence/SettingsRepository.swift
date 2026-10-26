import Foundation

public final class SettingsRepository: @unchecked Sendable {
    private let userDefaults: UserDefaults
    private let settingsKey = "com.auramotion.settings"
    private let calibrationPrefix = "com.auramotion.calibration."

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func loadSettings() -> AppSettings {
        guard let data = userDefaults.data(forKey: settingsKey),
              let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let defaultsData = try? JSONEncoder().encode(AppSettings()),
              let defaults = try? JSONSerialization.jsonObject(with: defaultsData) as? [String: Any] else {
            return AppSettings()
        }

        // Fill new fields from current defaults. Nested experiment preferences
        // need a recursive merge because older versions may have persisted only
        // a subset of CursorExperimentSettings.
        var merged = mergeDefaults(defaults, with: saved)
        if var settings = decodeSettings(from: merged) {
            settings.cursorExperiment = settings.cursorExperiment.normalized()
            settings.hudSkeletonScale = settings.hudSkeletonScale.isFinite ? min(3, max(0.5, settings.hudSkeletonScale)) : 1
            return settings
        }

        // An invalid experiment schema should safely disable experiments while
        // retaining otherwise valid, unrelated user preferences.
        if saved["cursorExperiment"] != nil {
            merged["cursorExperiment"] = defaults["cursorExperiment"]
            if var settings = decodeSettings(from: merged) {
                settings.cursorExperiment = settings.cursorExperiment.normalized()
                return settings
            }
        }

        // Unknown or invalid top-level settings fall back to safe defaults.
        return AppSettings()
    }

    private func decodeSettings(from object: [String: Any]) -> AppSettings? {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else {
            return nil
        }
        return try? JSONDecoder().decode(AppSettings.self, from: data)
    }

    private func mergeDefaults(_ defaults: [String: Any], with saved: [String: Any]) -> [String: Any] {
        var merged = defaults
        for (key, savedValue) in saved {
            if let defaultObject = defaults[key] as? [String: Any],
               let savedObject = savedValue as? [String: Any] {
                merged[key] = mergeDefaults(defaultObject, with: savedObject)
            } else {
                merged[key] = savedValue
            }
        }
        return merged
    }

    public func saveSettings(_ settings: AppSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            userDefaults.set(data, forKey: settingsKey)
        }
    }

    public func loadCalibration(cameraID: String, displayID: UInt32, arrangementHash: Int) -> CalibrationProfile {
        let key = calibrationKey(cameraID: cameraID, displayID: displayID, arrangementHash: arrangementHash)
        guard let data = userDefaults.data(forKey: key),
              let profile = try? JSONDecoder().decode(CalibrationProfile.self, from: data) else {
            return CalibrationProfile(cameraUniqueID: cameraID, displayID: displayID, displayArrangementHash: arrangementHash)
        }
        return profile
    }

    public func saveCalibration(_ profile: CalibrationProfile) {
        let key = calibrationKey(cameraID: profile.cameraUniqueID, displayID: profile.displayID, arrangementHash: profile.displayArrangementHash)
        if let data = try? JSONEncoder().encode(profile) {
            userDefaults.set(data, forKey: key)
        }
    }

    private func calibrationKey(cameraID: String, displayID: UInt32, arrangementHash: Int) -> String {
        return "\(calibrationPrefix)\(cameraID)_\(displayID)_\(arrangementHash)_v\(CalibrationProfile.currentMappingVersion)"
    }
}
