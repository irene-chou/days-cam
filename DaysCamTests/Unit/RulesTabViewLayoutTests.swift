import SwiftUI
import UIKit
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
        // Floor: 12 + three rows of at least 44pt + 12 = 156pt, a hard
        // lower bound whatever the OS. The ceiling is generous because the
        // native date picker's own height and the dividers vary a little
        // between OS versions (measured 157.0 on iOS 18.3, 156.7 on iOS 27).
        XCTAssertGreaterThanOrEqual(height, 12 + 44 * 3 + 12)
        XCTAssertLessThanOrEqual(height, 175, "整頁高度應約 157pt，量到 \(height)")
    }

    func testHiddenDayCountPageIsShorterThanTheFullPage() {
        let full = contentSize(showDayCount: true).height
        let hidden = contentSize(showDayCount: false).height
        // Name row (44) plus the hint, inside the same 12pt insets.
        XCTAssertGreaterThanOrEqual(hidden, 12 + 44 + 12)
        XCTAssertLessThan(hidden, full)
    }
}
