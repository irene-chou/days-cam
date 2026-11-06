import XCTest
@testable import DaysCam

/// #687-4: the 水平儀 switch is off by default and remembered.
final class LevelSettingTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "LevelSettingTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    func test_687_4_offByDefault() {
        XCTAssertFalse(LevelSetting(defaults: makeDefaults()).isOn)
    }

    func test_687_4_survivesANewInstance() {
        let defaults = makeDefaults()
        LevelSetting(defaults: defaults).set(true)
        XCTAssertTrue(LevelSetting(defaults: defaults).isOn)
        LevelSetting(defaults: defaults).set(false)
        XCTAssertFalse(LevelSetting(defaults: defaults).isOn)
    }
}
