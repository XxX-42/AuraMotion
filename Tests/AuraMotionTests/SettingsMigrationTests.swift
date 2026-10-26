import XCTest
import CoreGraphics
@testable import AuraMotionCore

final class SettingsMigrationTests: XCTestCase {
    func testMigratedSettingsRouteBothSwipeDirectionsToAppSwitching() throws {
        let name = "AuraMotion.MigrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Data(#"{"isCameraMirrored":true}"#.utf8), forKey: "com.auramotion.settings")
        let settings = SettingsRepository(userDefaults: defaults).loadSettings()
        let poster = RecordingEventPoster()
        for direction in [PalmSwipeDirection.left, .right] {
            poster.reset()
            poster.postSwipe(direction: direction, action: settings.swipeAction)
            let flags: CGEventFlags = direction == .left ? [.maskCommand, .maskShift] : .maskCommand
            XCTAssertTrue(poster.allEvents.contains(.keyEvent(virtualKey: 48, keyDown: true, flags: flags.rawValue)))
            XCTAssertEqual(poster.allEvents.last, .keyEvent(virtualKey: 55, keyDown: false, flags: 0))
        }
    }
    func testLegacySettingsPreservePreferencesAndGainSwipeOptions() throws {
        let name = "AuraMotion.MigrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Data(#"{"isCameraMirrored":false,"clutchDwellTime":0.12,"showHUD":false}"#.utf8), forKey: "com.auramotion.settings")
        let settings = SettingsRepository(userDefaults: defaults).loadSettings()
        XCTAssertFalse(settings.isCameraMirrored)
        XCTAssertFalse(settings.showHUD)
        XCTAssertFalse(settings.hudShowsCamera)
        XCTAssertTrue(settings.hudPreviewMirrored)
        XCTAssertFalse(settings.hudShowsJointNumbers)
        XCTAssertFalse(settings.hudHighlightFirstRing)
        XCTAssertFalse(settings.isGestureClickAndMenuEnabled)
        XCTAssertEqual(settings.hudSkeletonScale, 1)
        XCTAssertEqual(settings.clutchDwellTime, 0.12)
        XCTAssertTrue(settings.isPalmSwipeEnabled)
        XCTAssertEqual(settings.swipeAction, .switchApp)
    }

    func testGestureClickAndMenuDefaultsOffAndPersists() throws {
        let name = "AuraMotion.GestureToggleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let repository = SettingsRepository(userDefaults: defaults)
        var settings = repository.loadSettings()
        XCTAssertFalse(settings.isGestureClickAndMenuEnabled)
        settings.isGestureClickAndMenuEnabled = true
        repository.saveSettings(settings)
        XCTAssertTrue(repository.loadSettings().isGestureClickAndMenuEnabled)
    }

    func testHUDCameraModeSurvivesReload() throws {
        let name = "AuraMotion.MigrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let repository = SettingsRepository(userDefaults: defaults)
        var settings = AppSettings()
        settings.hudShowsCamera = true
        repository.saveSettings(settings)
        XCTAssertTrue(repository.loadSettings().hudShowsCamera)
    }

    func testHUDJointDisplayPreferencesSurviveReloadAndClamp() throws {
        let name = "AuraMotion.MigrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let repository = SettingsRepository(userDefaults: defaults)
        var settings = AppSettings()
        settings.hudShowsJointNumbers = true
        settings.hudHighlightFirstRing = true
        settings.hudPreviewMirrored = false
        settings.hudSkeletonScale = 2.4
        repository.saveSettings(settings)
        XCTAssertTrue(repository.loadSettings().hudShowsJointNumbers)
        XCTAssertTrue(repository.loadSettings().hudHighlightFirstRing)
        XCTAssertFalse(repository.loadSettings().hudPreviewMirrored)
        XCTAssertEqual(repository.loadSettings().hudSkeletonScale, 2.4)
        settings.hudSkeletonScale = 100
        repository.saveSettings(settings)
        XCTAssertEqual(repository.loadSettings().hudSkeletonScale, 3)
    }

    func testLandmarkNumbersAreStableAndUnique() {
        XCTAssertEqual(HandJointName.allCases.map(\.landmarkNumber), Array(0...20))
        XCTAssertEqual(HandJointName.indexTip.landmarkNumber, 8)
        XCTAssertEqual(HandJointName.littleTip.landmarkNumber, 20)
        XCTAssertEqual(HandLandmarkRings.second.count, 21)
        XCTAssertEqual(HandLandmarkRings.first.map(\.landmarkNumber), [0, 1, 2, 5, 9, 13, 17])
    }

    func testExplicitSwipeSelectionSurvivesReload() throws {
        let name = "AuraMotion.MigrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let repository = SettingsRepository(userDefaults: defaults)
        for action in SwipeActionType.allCases {
            let settings = AppSettings(swipeAction: action)
            repository.saveSettings(settings)
            XCTAssertEqual(repository.loadSettings(), settings)
        }
    }
}
