import SwiftUI
import UIKit
import XCTest
@testable import DaysCam

/// Height check for the style tab's color page (#155 Y.1/Y.2): with the
/// sub-tab row pinned, anything taller than the panel's content area slides
/// its first row under that row when scrolled to the bottom, clipping the
/// selection ring. The color page must therefore fit the 120pt content area.
@MainActor
final class StyleTabViewLayoutTests: XCTestCase {
    func testColorPageFitsA120ptContentAreaSoNothingScrollsUnderThePinnedRow() throws {
        let suite = try XCTUnwrap(UserDefaults(suiteName: "StyleTabViewLayoutTests.\(UUID().uuidString)"))
        let profile = CameraProfile(name: "測試", startDate: DateComponents(year: 2026, month: 1, day: 1))
        let model = StyleTabModel(profile: profile, recentColorsStore: RecentColorsStore(defaults: suite),
                                  applyFont: { _, _ in }, allProfiles: { [] }, replaceFont: { _, _ in [] }) { _ in }
        model.selectedSubTab = .color
        let hosting = UIHostingController(rootView: StyleTabView(model: model).frame(width: 375))
        let height = hosting.sizeThatFits(in: CGSize(width: 375, height: CGFloat.greatestFiniteMagnitude)).height
        XCTAssertLessThanOrEqual(height, 120, "顏色子分頁量到 \(height)pt，超過 120 會捲動並讓選定圈被固定的子分頁列切到")
    }
}
