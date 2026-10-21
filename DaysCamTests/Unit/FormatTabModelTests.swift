import Combine
import XCTest
@testable import DaysCam

/// Covers `FormatTabModel`'s state (PRD 0.2 FR-11), TASK-24 acceptance
/// 24.1–24.5. Reuses `DisplaySettingsModel` directly (the format tab is a
/// thin wrapper around it), so the interlock behavior itself — 0.1 11.8–11.14
/// and `toggleUnit` — is already covered by `DisplaySettingsModelTests`; this
/// file only covers the unit controls staying operable now that the day
/// count is always shown (TASK-48, 0.4 R-13; the second layer was removed in
/// TASK-38).
@MainActor
final class FormatTabModelTests: XCTestCase {
    private func fixedNow() throws -> Date {
        try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 8))
    }

    private func baselineProfile(showDate: Bool = false,
                                 displayUnits: Set<DisplayUnit> = [.day],
                                 useAgeWording: Bool = false) -> CameraProfile {
        CameraProfile(name: "小寶",
                     startDate: DateFixture.components(2026, 1, 1),
                     showDate: showDate,
                     displayUnits: displayUnits,
                     useAgeWording: useAgeWording)
    }

    private final class Spy {
        var updated: [CameraProfile] = []

        func update(_ profile: CameraProfile) throws {
            updated.append(profile)
        }
    }

    private func makeModel(profile: CameraProfile, now: Date, spy: Spy) -> FormatTabModel {
        let displaySettings = DisplaySettingsModel(profile: profile,
                                                   calendar: DateFixture.taipei,
                                                   calculator: DayCountCalculator(calendar: DateFixture.taipei, now: { now }),
                                                   renderer: TemplateRenderer(),
                                                   updateProfile: spy.update)
        return FormatTabModel(displaySettings: displaySettings)
    }

    // MARK: - 24.2 天數格式初始（只勾天）

    func testInitiallyOnlyDayIsCheckedAndDisabled() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(displayUnits: [.day]), now: try fixedNow(), spy: spy)
        let settings = model.displaySettings

        XCTAssertTrue(settings.profile.displayUnits.contains(.day), "24.2")
        XCTAssertTrue(settings.isLastCheckedUnit(.day), "108.7: 只剩一個，天不可取消")
        for unit: DisplayUnit in [.year, .month, .week] {
            XCTAssertFalse(settings.profile.displayUnits.contains(unit), "24.2")
            XCTAssertFalse(settings.isLastCheckedUnit(unit), "24.2")
        }
    }

    // MARK: - 24.3 勾年 → 勾週，沒有格子被自動取消

    func testCheckingYearThenWeekAddsBothWithoutAutoUnchecking() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(displayUnits: [.day]), now: try fixedNow(), spy: spy)
        model.displaySettings.toggleUnit(.year)
        model.displaySettings.toggleUnit(.week)
        XCTAssertEqual(model.displaySettings.profile.displayUnits, [.year, .week, .day], "24.3")
    }

    // MARK: - 24.4 → TASK-139 (#486): 取消勾年不再動到「年改成歲」

    func testUncheckingYearLeavesAgeWordingOn() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(displayUnits: [.year, .day], useAgeWording: true),
                              now: try fixedNow(), spy: spy)

        model.displaySettings.toggleUnit(.year)

        XCTAssertTrue(model.displaySettings.profile.useAgeWording, "24.4 → 139.3")
    }

    // MARK: - 48.3 單位區永遠可操作

    /// 48.3: the unit rows have no day-count-off state (0.4 R-13); toggling
    /// units and 年改成歲 behaves as before on a default profile.
    func testUnitControlsAlwaysOperable() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(), now: try fixedNow(), spy: spy)
        model.displaySettings.toggleUnit(.year)
        XCTAssertTrue(model.displaySettings.profile.displayUnits.contains(.year), "48.3")
        model.displaySettings.setUseAgeWording(true)
        XCTAssertTrue(model.displaySettings.profile.useAgeWording, "48.3")
    }

    // MARK: - #583 寫法

    func test_583_changingTheFormatIsForwarded() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(), now: try fixedNow(), spy: spy)
        var changes = 0
        let subscription = model.objectWillChange.sink { changes += 1 }
        defer { subscription.cancel() }

        model.displaySettings.setDayCountFormat(.plain)

        XCTAssertEqual(model.displaySettings.profile.dayCountFormat, .plain)
        XCTAssertGreaterThan(changes, 0, "objectWillChange forwarded")
    }
}
