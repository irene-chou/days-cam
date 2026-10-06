import XCTest
@testable import DaysCam

/// Covers `FormatTabModel`'s state (PRD 0.2 FR-11), TASK-24 acceptance
/// 24.1–24.5. Reuses `DisplaySettingsModel` directly (the format tab is a
/// thin wrapper around it), so the interlock behavior itself — 0.1 11.8–11.14
/// and `toggleUnit` — is already covered by `DisplaySettingsModelTests`; this
/// file only covers what `FormatTabModel` adds: the format-specific
/// hidden-section hint (the second layer was removed in TASK-38).
@MainActor
final class FormatTabModelTests: XCTestCase {
    private func fixedNow() throws -> Date {
        try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 8))
    }

    private func baselineProfile(showDayCount: Bool = true,
                                 showDate: Bool = false,
                                 displayUnits: Set<DisplayUnit> = [.day],
                                 useAgeWording: Bool = false) -> CameraProfile {
        CameraProfile(name: "小寶",
                     startDate: DateFixture.components(2026, 1, 1),
                     showDayCount: showDayCount,
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
        XCTAssertTrue(settings.isUnitToggleDisabled(.day), "24.2: 只剩一個，天 disabled")
        for unit: DisplayUnit in [.year, .month, .week] {
            XCTAssertFalse(settings.profile.displayUnits.contains(unit), "24.2")
            XCTAssertFalse(settings.isUnitToggleDisabled(unit), "24.2")
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

    // MARK: - 24.4 取消勾年時「年改成歲」自動關閉且 disabled

    func testUncheckingYearTurnsOffAndDisablesAgeWording() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(displayUnits: [.year, .day], useAgeWording: true),
                              now: try fixedNow(), spy: spy)
        XCTAssertFalse(model.displaySettings.isAgeWordingToggleDisabled)

        model.displaySettings.toggleUnit(.year)

        XCTAssertFalse(model.displaySettings.profile.useAgeWording, "24.4")
        XCTAssertTrue(model.displaySettings.isAgeWordingToggleDisabled, "24.4")
    }

    // MARK: - 24.5 天數關閉時的說明文字

    func testDayCountFormatSectionDisabledMessageWhenDayCountOff() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(showDayCount: false, showDate: true),
                              now: try fixedNow(), spy: spy)
        XCTAssertTrue(model.displaySettings.isDayCountFormatSectionDisabled, "24.5")
        XCTAssertEqual(FormatTabModel.dayCountFormatHiddenHintMessage, "天數未顯示，格式設定暫不作用", "24.5")
    }

    func testDayCountFormatSectionEnabledWhenDayCountOn() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(showDayCount: true), now: try fixedNow(), spy: spy)
        XCTAssertFalse(model.displaySettings.isDayCountFormatSectionDisabled)
    }
}
