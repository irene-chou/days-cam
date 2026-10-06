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
        let hosting = UIHostingController(rootView: StyleTabView(model: model, availableHeight: 120).frame(width: 375))
        let height = hosting.sizeThatFits(in: CGSize(width: 375, height: CGFloat.greatestFiniteMagnitude)).height
        XCTAssertLessThanOrEqual(height, 120, "顏色子分頁量到 \(height)pt，超過 120 會捲動並讓選定圈被固定的子分頁列切到")
    }

    private func makeModel() throws -> StyleTabModel {
        let suite = try XCTUnwrap(UserDefaults(suiteName: "StyleTabViewLayoutTests.\(UUID().uuidString)"))
        let profile = CameraProfile(name: "測試", startDate: DateComponents(year: 2026, month: 1, day: 1))
        return StyleTabModel(profile: profile, recentColorsStore: RecentColorsStore(defaults: suite),
                             applyFont: { _, _ in }, allProfiles: { [] }, replaceFont: { _, _ in [] }) { _ in }
    }

    /// 39.8: regular panels use 34pt swatches; compact (<= 120pt) keeps 28pt.
    func testSwatchDiameterFollowsAvailableHeight() {
        XCTAssertEqual(StyleTabView.swatchDiameter(forAvailableHeight: 120), 28)
        XCTAssertEqual(StyleTabView.swatchDiameter(forAvailableHeight: 80), 28)
        XCTAssertEqual(StyleTabView.swatchDiameter(forAvailableHeight: 200), 34)
        XCTAssertEqual(StyleTabView.swatchDiameter(forAvailableHeight: 160), 34)
    }

    /// 39.8: outline color page at 200pt: first row (auto + 9 swatches at 34pt)
    /// fits the 355pt content width, so the page needs no horizontal scrolling.
    func testOutlineColorPageAt200ptFitsContentWidth() throws {
        let model = try makeModel()
        model.selectOutline(model.outlineOptions.first { $0 != .none } ?? .none)
        model.selectedSubTab = .outline
        let hosting = UIHostingController(rootView: StyleTabView(model: model, availableHeight: 200).frame(width: 375))
        let size = hosting.sizeThatFits(in: CGSize(width: 375, height: CGFloat.greatestFiniteMagnitude))
        XCTAssertLessThanOrEqual(size.width, 375)
        let firstRowWidth = CGFloat(model.outlineColorSwatches.count + 1) * StyleTabView.swatchDiameter(forAvailableHeight: 200)
        XCTAssertEqual(model.outlineColorSwatches.count, 9)
        XCTAssertLessThanOrEqual(firstRowWidth, 355)
    }
}
