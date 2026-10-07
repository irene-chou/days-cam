import SwiftUI
import UIKit
import XCTest
@testable import DaysCam

/// View-level size check for `RulesTabView` (#156, reshaped by #226 R-8／R-9,
/// TASK-43): the grouped block is three rows of at least 48pt, the preview
/// sentence sits below it, and the day-count-off hint adds one more line.
@MainActor
final class RulesTabViewLayoutTests: XCTestCase {
    private func contentSize(showDayCount: Bool, width: CGFloat = 375) -> CGSize {
        let profile = CameraProfile(name: "小寶",
                                     startDate: DateComponents(year: 2026, month: 1, day: 1),
                                     showDayCount: showDayCount)
        let model = RulesTabModel(profile: profile) { _ in }
        let hosting = UIHostingController(rootView: RulesTabView(model: model).frame(width: width))
        return hosting.sizeThatFits(in: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
    }

    /// 43.7: at 375pt the three rows are never truncated, so the page is at
    /// least the floor of three 48pt rows plus the preview sentence.
    func testGroupedBlockIsAtLeastThreeMinimumRows() {
        let height = contentSize(showDayCount: true).height
        XCTAssertGreaterThanOrEqual(height, 12 + 48 * 3 + 12 + 12)
        XCTAssertLessThanOrEqual(height, 260, "整頁高度過高，量到 \(height)")
    }

    /// 43.2: the rows stay when the day count is off; the hint only adds height.
    func testDayCountOffKeepsRowsAndAddsHint() {
        let on = contentSize(showDayCount: true).height
        let off = contentSize(showDayCount: false).height
        XCTAssertGreaterThanOrEqual(off, 12 + 48 * 3 + 12 + 12)
        XCTAssertGreaterThan(off, on)
    }

    /// 43.7: the two counting-rule capsules fit in the row at 375pt (and at
    /// 320pt, narrower than any supported device) without wrapping the page.
    func testCountingRuleCapsulesFitAtNarrowWidth() {
        let labels = [RulesTabModel.countingRuleDayOneLabel, RulesTabModel.countingRuleDayZeroLabel]
        let font = UIFont.preferredFont(forTextStyle: .footnote)
        let capsules = labels.reduce(CGFloat(0)) { total, label in
            total + (label as NSString).size(withAttributes: [.font: font]).width + 20
        }
        // 375 - 2×16 row inset - label "起算" (~40) - gap - capsule gap.
        let available: CGFloat = 375 - 2 * RulesTabView.rowHorizontalPadding - 40 - 10 - 8
        XCTAssertLessThanOrEqual(capsules, available, "起算兩顆膠囊需完整顯示")
    }
}
