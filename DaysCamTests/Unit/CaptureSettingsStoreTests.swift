import Combine
import XCTest
@testable import DaysCam

/// Covers TASK-19 acceptance 19.3: `captureAspectRatio` and `showsGrid`
/// survive a relaunch, `flashMode` and `timerSeconds` do not (PRD 0.2 §4.4).
final class CaptureSettingsStoreTests: XCTestCase {

    /// A fresh, isolated `UserDefaults` suite per test so runs never see
    /// each other's persisted values.
    private func makeIsolatedDefaults() -> UserDefaults {
        let suiteName = "CaptureSettingsStoreTests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }

    func test_defaultsAreThreeByFourAndGridOff() {
        let store = CaptureSettingsStore(defaults: makeIsolatedDefaults())

        XCTAssertEqual(store.captureAspectRatio, .threeByFour)
        XCTAssertFalse(store.showsGrid)
        XCTAssertEqual(store.flashMode, .off)
        XCTAssertEqual(store.timerSeconds, .off)
    }

    func test_aspectRatioAndGridSurviveARelaunch_flashAndTimerDoNot() {
        let defaults = makeIsolatedDefaults()
        let firstLaunch = CaptureSettingsStore(defaults: defaults)

        firstLaunch.setAspectRatio(.oneByOne)
        firstLaunch.toggleGrid()
        firstLaunch.cycleFlash() // .off -> .auto -> .on
        firstLaunch.cycleFlash()
        firstLaunch.cycleTimer() // .off -> .threeSeconds

        XCTAssertEqual(firstLaunch.captureAspectRatio, .oneByOne)
        XCTAssertTrue(firstLaunch.showsGrid)
        XCTAssertEqual(firstLaunch.flashMode, .on)
        XCTAssertEqual(firstLaunch.timerSeconds, .threeSeconds)

        // A second store against the same `UserDefaults` instance simulates
        // the app relaunching (19.3).
        let secondLaunch = CaptureSettingsStore(defaults: defaults)

        XCTAssertEqual(secondLaunch.captureAspectRatio, .oneByOne, "aspect ratio must persist")
        XCTAssertTrue(secondLaunch.showsGrid, "grid setting must persist")
        XCTAssertEqual(secondLaunch.flashMode, .off, "flash must reset on relaunch")
        XCTAssertEqual(secondLaunch.timerSeconds, .off, "timer must reset on relaunch")
    }

    // MARK: - ColorTone (#588)

    func test_colorToneDefaultsToStandard() {
        let store = CaptureSettingsStore(defaults: makeIsolatedDefaults())

        XCTAssertEqual(store.colorTone, .standard)
    }

    func test_colorToneSurvivesARelaunch() {
        let defaults = makeIsolatedDefaults()
        CaptureSettingsStore(defaults: defaults).setColorTone(.warm2)

        XCTAssertEqual(CaptureSettingsStore(defaults: defaults).colorTone, .warm2)
    }

    func test_unknownStoredColorToneFallsBackToStandard() {
        let defaults = makeIsolatedDefaults()
        defaults.set("banana", forKey: "colorTone")

        XCTAssertEqual(CaptureSettingsStore(defaults: defaults).colorTone, .standard)
    }

    func test_settingTheSameColorToneDoesNotPublish() {
        let store = CaptureSettingsStore(defaults: makeIsolatedDefaults())
        var publishCount = 0
        let cancellable = store.objectWillChange.sink { publishCount += 1 }

        store.setColorTone(.standard)
        XCTAssertEqual(publishCount, 0)

        store.setColorTone(.cool1)
        XCTAssertEqual(publishCount, 1)
        store.setColorTone(.cool1)
        XCTAssertEqual(publishCount, 1)
        cancellable.cancel()
    }
}
