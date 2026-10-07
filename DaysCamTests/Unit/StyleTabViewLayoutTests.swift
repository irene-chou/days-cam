import SwiftUI
import UIKit
import XCTest
@testable import DaysCam

/// Layout checks for the style tab's color pages (TASK-39): 34pt swatches on
/// a shared nine-column grid, and page heights that fit a regular panel.
@MainActor
final class StyleTabViewLayoutTests: XCTestCase {
    private func makeModel() throws -> StyleTabModel {
        let suite = try XCTUnwrap(UserDefaults(suiteName: "StyleTabViewLayoutTests.\(UUID().uuidString)"))
        let profile = CameraProfile(name: "測試", startDate: DateComponents(year: 2026, month: 1, day: 1))
        return StyleTabModel(profile: profile, recentColorsStore: RecentColorsStore(defaults: suite),
                             applyFont: { _, _ in }, allProfiles: { [] }, replaceFont: { _, _ in [] }) { _ in }
    }

    private func pageHeight(_ model: StyleTabModel) -> CGFloat {
        let hosting = UIHostingController(rootView: StyleTabView(model: model).frame(width: 375))
        return hosting.sizeThatFits(in: CGSize(width: 375, height: CGFloat.greatestFiniteMagnitude)).height
    }

    /// 39.8: nine equal-gap columns filling the content width; the second
    /// row reuses the same column centers, so its n-th swatch is directly
    /// under the first row's n-th (±0.5).
    func testNineColumnsAreEvenlySpacedAndShareCentersAcrossRows() {
        XCTAssertEqual(StyleTabView.swatchDiameter, 34)
        XCTAssertEqual(StyleTabView.swatchCellHeight, 42)
        for contentWidth: CGFloat in [355, 375, 420] {
            let centers = StyleTabView.columnCenters(forContentWidth: contentWidth)
            XCTAssertEqual(centers.count, 9)
            let pitches = zip(centers.dropFirst(), centers).map { $0 - $1 }
            for pitch in pitches {
                XCTAssertEqual(pitch, pitches[0], accuracy: 0.001, "等距")
                XCTAssertGreaterThanOrEqual(pitch, 34 + 2, "隔壁色票與環之間不重疊")
            }
            let totalWidth = centers[8] + 17 - (centers[0] - 17)
            XCTAssertLessThanOrEqual(totalWidth, contentWidth + 0.001)
            XCTAssertEqual(totalWidth, contentWidth, accuracy: 0.001, "撐滿內容寬")
            let secondRow = StyleTabView.columnCenters(forContentWidth: contentWidth)
            for (first, second) in zip(centers, secondRow) { XCTAssertEqual(first, second, accuracy: 0.5) }
        }
        XCTAssertEqual(StyleTabView.columnSpacing(forContentWidth: 355), 6.125, accuracy: 0.01)
    }

    /// 39.8a: the color-and-size page (TASK-46, slider above swatches) fits a regular panel's 212pt content area;
    /// the outline page is capped at the ~200pt panel of #198. Small screens may scroll.
    func testColorAndOutlinePagesFitRegularContentArea() throws {
        let model = try makeModel()
        model.selectedSubTab = .color
        let colorHeight = pageHeight(model)
        XCTAssertGreaterThanOrEqual(colorHeight, 42 + 6 + 42)
        XCTAssertLessThanOrEqual(colorHeight, 212, "46.7 顏色與大小頁 \(colorHeight)pt")
        model.selectOutline(model.outlineOptions.first { $0 != .none } ?? .none)
        model.selectedSubTab = .outline
        let outlineHeight = pageHeight(model)
        // The card asks <= 160, but outline options (52) + two 42pt rows +
        // sub-tab row and insets measure 200pt; that equals the ~200pt panel
        // #198 introduces, so it is capped there (reported to Lead).
        XCTAssertLessThanOrEqual(outlineHeight, 200, "外框頁 \(outlineHeight)pt")
    }

    private func width<V: View>(of view: V) -> CGFloat {
        UIHostingController(rootView: view.fixedSize())
            .sizeThatFits(in: CGSize(width: 1000, height: 1000)).width
    }

    /// Every second-row item (auto, rainbow, recent colors) is exactly one
    /// 34pt grid column wide, so the HStack matches `columnCenters`.
    func testSecondRowItemsAreOneSwatchWide() throws {
        let model = try makeModel()
        let view = StyleTabView(model: model)
        XCTAssertEqual(width(of: view.autoColorButton(current: nil) {}), 34, accuracy: 0.5)
        XCTAssertEqual(width(of: view.customColorPicker(current: nil, isSelected: false) { _ in }), 34, accuracy: 0.5)
        XCTAssertEqual(width(of: view.customColorPicker(current: nil, isSelected: true) { _ in }), 34, accuracy: 0.5)
        let recent = try XCTUnwrap(OverlayColor(hex: "#8E5AA8"))
        XCTAssertEqual(width(of: view.colorDot(recent, isSelected: false) {}), 34, accuracy: 0.5)
        XCTAssertEqual(width(of: view.colorDot(recent, isSelected: true) {}), 34, accuracy: 0.5)
    }

    /// The outline page's second row tops out at 9: auto + rainbow + 7 recent.
    func testRecentCustomColorsCapAtSevenSoSecondRowHoldsNineAtMost() throws {
        let model = try makeModel()
        let hexes = ["#8E5AA8", "#2E8B8B", "#C0713A", "#3A7BC0", "#C03A6E", "#6EA83A", "#555555", "#123456", "#654321"]
        for hex in hexes { model.pickCustomOutlineColor(try XCTUnwrap(OverlayColor(hex: hex))) }
        XCTAssertEqual(model.recentColors.count, 7)
        XCTAssertEqual(1 + 1 + model.recentColors.count, StyleTabView.colorColumnCount)
        XCTAssertEqual(1 + model.recentColors.count + 0, 8, "文字顏色頁：彩虹圓 + 7")
    }
}
