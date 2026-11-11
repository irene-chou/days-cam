import Combine
import XCTest
@testable import DaysCam

/// Covers `FormatTabModel`'s state (PRD 0.2 FR-11), TASK-24 acceptance
/// 24.1–24.5. Reuses `DisplaySettingsModel` directly (the format tab is a
/// thin wrapper around it). The unit checkboxes and 年改成歲 moved to the
/// record edit page (#721; see `RulesTabModelTests`); this file only covers
/// the forwarding of the model's changes.
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
