import XCTest
@testable import AuraMotionCore

final class ExperimentSettingsTests: XCTestCase {
    func testBaselineAndOptimizedPresetsOnlyChangeExperimentConfiguration() {
        var appSettings = AppSettings(
            isCameraMirrored: false,
            isClutchEnabled: false,
            arbitrationCooldownSeconds: 2.25,
            language: .english
        )

        appSettings.cursorExperiment.applyPreset(.optimized)

        XCTAssertEqual(appSettings.cursorExperiment.preset, .optimized)
        XCTAssertTrue(appSettings.cursorExperiment.stableAnchorEnabled)
        XCTAssertTrue(appSettings.cursorExperiment.relativeMappingEnabled)
        XCTAssertTrue(appSettings.cursorExperiment.adaptiveDeadzoneEnabled)
        XCTAssertTrue(appSettings.cursorExperiment.lowSpeedQuantizationEnabled)
        XCTAssertFalse(appSettings.cursorExperiment.velocityGainEnabled)
        XCTAssertTrue(appSettings.cursorExperiment.separateDragTuningEnabled)
        XCTAssertTrue(appSettings.cursorExperiment.optimizedOneEuroEnabled)
        XCTAssertFalse(appSettings.cursorExperiment.visionROIEnabled)
        XCTAssertFalse(appSettings.cursorExperiment.mediaPipeBenchmarkEnabled)
        XCTAssertFalse(appSettings.isCameraMirrored)
        XCTAssertFalse(appSettings.isClutchEnabled)
        XCTAssertEqual(appSettings.arbitrationCooldownSeconds, 2.25)
        XCTAssertEqual(appSettings.language, .english)

        appSettings.cursorExperiment.applyPreset(.baseline)
        XCTAssertFalse(appSettings.cursorExperiment.stableAnchorEnabled)
        XCTAssertFalse(appSettings.cursorExperiment.relativeMappingEnabled)
        XCTAssertFalse(appSettings.cursorExperiment.adaptiveDeadzoneEnabled)
        XCTAssertFalse(appSettings.cursorExperiment.lowSpeedQuantizationEnabled)
        XCTAssertFalse(appSettings.cursorExperiment.velocityGainEnabled)
        XCTAssertFalse(appSettings.cursorExperiment.separateDragTuningEnabled)
        XCTAssertFalse(appSettings.cursorExperiment.optimizedOneEuroEnabled)
        XCTAssertFalse(appSettings.cursorExperiment.visionROIEnabled)
        XCTAssertFalse(appSettings.cursorExperiment.mediaPipeBenchmarkEnabled)
        XCTAssertFalse(appSettings.isCameraMirrored)
        XCTAssertEqual(appSettings.language, .english)
    }

    func testCustomPresetDoesNotChangeExperimentToggles() {
        var experiment = CursorExperimentSettings()
        experiment.stableAnchorEnabled = true
        experiment.roiScale = 2.4

        experiment.applyPreset(.custom)

        XCTAssertEqual(experiment.preset, .custom)
        XCTAssertTrue(experiment.stableAnchorEnabled)
        XCTAssertEqual(experiment.roiScale, 2.4)
    }

    func testExperimentSettingsAndLanguagePersistWithExistingPreferences() throws {
        let (suite, defaults) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = SettingsRepository(userDefaults: defaults)

        var experiment = CursorExperimentSettings()
        experiment.applyPreset(.optimized)
        experiment.roiScale = 2.2
        experiment.preset = .custom
        let settings = AppSettings(
            isCameraMirrored: false,
            showHUD: false,
            arbitrationCooldownSeconds: 2.5,
            cursorExperiment: experiment,
            language: .english
        )

        repository.saveSettings(settings)
        XCTAssertEqual(repository.loadSettings(), settings)
    }

    func testPartialExperimentSettingsDeepMergeWithDefaults() throws {
        let (suite, defaults) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(
            Data(#"{"isCameraMirrored":false,"showHUD":false,"language":"en","cursorExperiment":{"stableAnchorEnabled":true,"pointerBeta":0.025}}"#.utf8),
            forKey: "com.auramotion.settings"
        )

        let settings = SettingsRepository(userDefaults: defaults).loadSettings()

        XCTAssertFalse(settings.isCameraMirrored)
        XCTAssertFalse(settings.showHUD)
        XCTAssertEqual(settings.language, .english)
        XCTAssertTrue(settings.cursorExperiment.stableAnchorEnabled)
        XCTAssertEqual(settings.cursorExperiment.pointerBeta, 0.025, accuracy: 0.0001)
        XCTAssertEqual(settings.cursorExperiment.restDeadzone, CursorExperimentSettings().restDeadzone)
        XCTAssertEqual(settings.cursorExperiment.anchorStrategy, .palmMCPFusion)
        XCTAssertFalse(settings.cursorExperiment.relativeMappingEnabled)
        XCTAssertFalse(settings.cursorExperiment.visionROIEnabled)
        XCTAssertFalse(settings.cursorExperiment.mediaPipeBenchmarkEnabled)
    }

    func testInvalidExperimentSchemaFallsBackSafelyAndPreservesOtherPreferences() throws {
        let (suite, defaults) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(
            Data(#"{"isCameraMirrored":false,"showHUD":false,"cursorExperiment":{"stableAnchorEnabled":"yes"}}"#.utf8),
            forKey: "com.auramotion.settings"
        )

        let settings = SettingsRepository(userDefaults: defaults).loadSettings()

        XCTAssertFalse(settings.isCameraMirrored)
        XCTAssertFalse(settings.showHUD)
        XCTAssertEqual(settings.cursorExperiment, CursorExperimentSettings())
    }

    func testInvalidTopLevelSchemaFallsBackToSafeDefaults() throws {
        let (suite, defaults) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(
            Data(#"{"isCameraMirrored":"no","cursorExperiment":{"stableAnchorEnabled":true}}"#.utf8),
            forKey: "com.auramotion.settings"
        )

        XCTAssertEqual(SettingsRepository(userDefaults: defaults).loadSettings(), AppSettings())
    }

    private func makeDefaults() throws -> (String, UserDefaults) {
        let name = "AuraMotion.ExperimentSettingsTests.\(UUID().uuidString)"
        return (name, try XCTUnwrap(UserDefaults(suiteName: name)))
    }
}
