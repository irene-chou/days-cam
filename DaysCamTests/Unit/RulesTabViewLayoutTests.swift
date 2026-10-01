import SwiftUI
import XCTest
@testable import DaysCam

/// View-level size check for `RulesTabView` (#156): the whole page should be
/// about 157pt tall at iPhone width — 12 + 3 rows of at least 44pt + two
/// dividers + 12 — so the panel (#157) can be sized to show it unscrolled.
@MainActor
final class RulesTabViewLayoutTests: XCTestCase {
    private func contentSize(showDayCount: Bool) -> CGSize {
        let profile = CameraProfile(name: "小寶",
                                     startDate: DateComponents(year: 2026, month: 1, day: 1),
                                     showDayCount: showDayCount)
        let model = RulesTabModel(profile: profile) { _ in }
        let hosting = UIHostingController(rootView: RulesTabView(model: model).frame(width: 375))
        return hosting.sizeThatFits(in: CGSize(width: 375, height: CGFloat.greatestFiniteMagnitude))
    }

    func testWholePageHeightIsAboutThreeMinimumRows() {
        let height = contentSize(showDayCount: true).height
        // 12 + 44 * 3 + dividers + 12 = ~157; allow room for a taller native
        // date picker row on other OS versions.
        XCTAssertGreaterThanOrEqual(height, 156)
        XCTAssertLessThanOrEqual(height, 165, "整頁高度應約 157pt，量到 \(height)")
    }
}
