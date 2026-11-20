import SwiftUI
import UIKit
import XCTest
@testable import DaysCam

/// View-level size check for `RulesTabView` (#156, reshaped by #226 R-8／R-9,
/// TASK-43, #721): the grouped block is six rows of at least 48pt, the preview
/// sentence sits below it.
@MainActor
final class RulesTabViewLayoutTests: XCTestCase {
    private func contentSize(width: CGFloat = 375) -> CGSize {
        let profile = CameraProfile(name: "小寶",
                                     startDate: DateComponents(year: 2026, month: 1, day: 1),
                                     showDayCount: true)
        let model = RulesTabModel(profile: profile) { _ in }
        let hosting = UIHostingController(rootView: RulesTabView(model: model).frame(width: width))
        return hosting.sizeThatFits(in: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
    }

    /// 43.7／155／721: at 375pt the three label-above-value rows, the 單位 and
    /// 「年」改成「歲」 rows (#721) and the 天數預覽 block are never truncated, so the
    /// page is at least three stacked rows (label 16 + value 22 + 2×10 inset),
    /// the unit row (label 16 + 6 + checkbox 36 + 2×10), the age-wording row
    /// (48 + 2×10) plus the preview title and its single 今天 row, and stays
    /// under a ceiling that catches a runaway layout.
    func testPageHoldsSixRowsAndThePreview() {
        let height = contentSize().height
        // 12 + 58×3 + 78 + 48 + 68 + 16 + 16 + 40 + 12 (#747 adds the 48pt 寫法 row); a literal because Xcode 26.3 times out type-checking the sum.
        let floor: CGFloat = 464
        XCTAssertGreaterThanOrEqual(height, floor, "155／721／747 six rows and the preview")
        // #721 measured 464.0 at 375pt; #747 adds the 寫法 row (48 + divider).
        XCTAssertLessThanOrEqual(height, 540, "整頁高度過高，量到 \(height)")
    }

    /// 25.6／155.5: each of the two equal 起算 cells fits its label at 375pt (and
    /// at 320pt, narrower than any supported device) on one line.
    func testCountingRuleCellsFitAtNarrowWidth() {
        let font = UIFont.preferredFont(forTextStyle: .footnote)
        for width: CGFloat in [375, 320] {
            // width - 2×14 outer inset - 2×16 row inset - 2×2 track padding, halved.
            let cell = (width - 2 * 14 - 2 * RulesTabView.rowHorizontalPadding - 4) / 2
            for label in [RulesTabModel.countingRuleDayOneLabel, RulesTabModel.countingRuleDayZeroLabel] {
                let text = (label as NSString).size(withAttributes: [.font: font]).width
                XCTAssertLessThanOrEqual(text + 8, cell, "\(label) 在 \(width)pt 需完整顯示")
            }
        }
    }
}
