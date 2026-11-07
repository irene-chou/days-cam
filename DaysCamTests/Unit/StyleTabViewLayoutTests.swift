import SwiftUI
import UIKit
import XCTest
@testable import DaysCam

/// Layout checks for the style tab (TASK-39, #678): 30pt swatches on a shared
/// nine-column grid, the row of looks and the page height.
@MainActor
final class StyleTabViewLayoutTests: XCTestCase {
    private func makeModel() throws -> StyleTabModel {
        let suite = try XCTUnwrap(UserDefaults(suiteName: "StyleTabViewLayoutTests.\(UUID().uuidString)"))
        let profile = CameraProfile(name: "測試", startDate: DateComponents(year: 2026, month: 1, day: 1))
        return StyleTabModel(profile: profile, recentColorsStore: RecentColorsStore(defaults: suite),
                             applyFont: { _, _ in }, allProfiles: { [] }) { _ in }
    }

    /// Natural height of the page; `availableHeight` 0 turns off centering's
    /// minimum height, and the default fills a regular 224pt panel.
    private func pageHeight(_ model: StyleTabModel, availableHeight: CGFloat = 0) -> CGFloat {
        let hosting = UIHostingController(rootView: StyleTabView(model: model, availableHeight: availableHeight)
            .frame(width: 375))
        return hosting.sizeThatFits(in: CGSize(width: 375, height: CGFloat.greatestFiniteMagnitude)).height
    }

    /// 49.10: nine equal-gap columns filling the content width; the second
    /// row reuses the same column centers, so its n-th swatch is directly
    /// under the first row's n-th (±0.5).
    func testNineColumnsAreEvenlySpacedAndShareCentersAcrossRows() {
        XCTAssertEqual(StyleTabView.swatchDiameter, 32, "#691")
        XCTAssertEqual(StyleTabView.swatchCellHeight, 40)
        for contentWidth: CGFloat in [355, 375, 420] {
            let centers = StyleTabView.columnCenters(forContentWidth: contentWidth)
            XCTAssertEqual(centers.count, 9)
            let pitches = zip(centers.dropFirst(), centers).map { $0 - $1 }
            for pitch in pitches {
                XCTAssertEqual(pitch, pitches[0], accuracy: 0.001, "等距")
                XCTAssertGreaterThanOrEqual(pitch, 38, "隔壁色票與環之間不重疊")
            }
            let totalWidth = centers[8] + 16 - (centers[0] - 16)
            XCTAssertLessThanOrEqual(totalWidth, contentWidth + 0.001)
            XCTAssertEqual(totalWidth, contentWidth, accuracy: 0.001, "撐滿內容寬")
            let secondRow = StyleTabView.columnCenters(forContentWidth: contentWidth)
            for (first, second) in zip(centers, secondRow) { XCTAssertEqual(first, second, accuracy: 0.5) }
        }
        XCTAssertEqual(StyleTabView.columnSpacing(forContentWidth: 355), 8.375, accuracy: 0.01)
    }

    /// 117.1 / 117.3: the page insets its content 18pt a side (20pt from the
    /// panel edge).
    func testContentHorizontalInsetIsEighteen() {
        XCTAssertEqual(StyleTabView.contentHorizontalInset, 18)
    }

    /// 117.4: each slider row carries 4pt above and below.
    func testSliderVerticalPaddingIsFour() {
        XCTAssertEqual(StyleTabView.sliderVerticalPadding, 4)
    }

    /// 117.5 / #691: on a 375pt screen the content is 375 - 2 x 18 = 339pt
    /// (the panel adds no side inset of its own); the nine 32pt swatches
    /// keep at least 6pt between neighbors, so the 4pt selection rings
    /// never touch.
    func testSwatchSpacingOn375WidthIsAtLeastSix() {
        let spacing = StyleTabView.columnSpacing(forContentWidth: 375 - 2 * StyleTabView.contentHorizontalInset)
        XCTAssertGreaterThanOrEqual(spacing, 6)
        XCTAssertEqual(spacing, 6.375, accuracy: 0.01)
    }

    /// #691 ruling (plan A): one row of the nine main colors, then the
    /// rainbow row — no light row — so the palette is two rows tall.
    func testOnlyOneRowOfMainColors() throws {
        let view = StyleTabView(model: try makeModel())
        let height = UIHostingController(rootView: view.textColorPalette.frame(width: 339))
            .sizeThatFits(in: CGSize(width: 339, height: CGFloat.greatestFiniteMagnitude)).height
        XCTAssertEqual(height, 2 * StyleTabView.swatchCellHeight + 6, accuracy: 0.5, "#691 一排主色＋彩虹列")
    }

    /// 678-1 / 678-2: the capsule metrics of the row of looks and the box
    /// button.
    func testPresetRowAndBoxButtonMetrics() {
        XCTAssertEqual(StyleTabView.presetHeight, 34)
        XCTAssertEqual(StyleTabView.presetSpacing, 8)
        XCTAssertEqual(StyleTabView.presetHorizontalPadding, 14)
        XCTAssertEqual(StyleTabView.presetVerticalPadding, 7)
        XCTAssertEqual(StyleTabView.presetRingWidth, 2)
        XCTAssertEqual(StyleTabView.presetRingOffset, 1)
        XCTAssertEqual(StyleTabView.presetBadgeSize, 14)
        XCTAssertEqual(StyleTabView.presetRowVerticalInset, 4)
        XCTAssertEqual(StyleTabView.boxButtonSide, 28)
        XCTAssertEqual(StyleTabView.sectionSpacing, 16, "#691")
    }

    /// 678-1 / #691 rulings: the one page — row of looks, two color rows,
    /// the one-line size row, 16pt apart — fits the 244pt content area, no scrolling on a
    /// regular phone (FR-8.8).
    func testThePageFitsTheRegularContentArea() throws {
        let height = pageHeight(try makeModel())
        let rowAndColors: CGFloat = 42 + 16 + 86 + 16
        XCTAssertGreaterThanOrEqual(height, rowAndColors)
        XCTAssertLessThanOrEqual(height, 244, "樣式頁 \(height)pt")
    }

    /// 678-5: the box button's VoiceOver values.
    func testBoxStateNames() {
        XCTAssertEqual(StyleTabView.boxStateName(.base), "原本")
        XCTAssertEqual(StyleTabView.boxStateName(.solid), "實心")
        XCTAssertEqual(StyleTabView.boxStateName(.translucent), "半透明")
    }

    private func width<V: View>(of view: V) -> CGFloat {
        UIHostingController(rootView: view.fixedSize())
            .sizeThatFits(in: CGSize(width: 1000, height: 1000)).width
    }

    /// Every last-row item (rainbow, recent colors, box button) is exactly
    /// one 32pt grid column wide, so the HStack matches `columnCenters`.
    func testSecondRowItemsAreOneSwatchWide() throws {
        let model = try makeModel()
        let view = StyleTabView(model: model)
        XCTAssertEqual(width(of: view.boxButton), 32, accuracy: 0.5)
        XCTAssertEqual(width(of: view.customColorPicker(current: nil, isSelected: false, onApply: { _ in }, onCommit: { _ in })), 32, accuracy: 0.5)
        XCTAssertEqual(width(of: view.customColorPicker(current: nil, isSelected: true, onApply: { _ in }, onCommit: { _ in })), 32, accuracy: 0.5)
        let recent = try XCTUnwrap(OverlayColor(hex: "#8E5AA8"))
        XCTAssertEqual(width(of: view.colorDot(recent, isSelected: false) {}), 32, accuracy: 0.5)
        XCTAssertEqual(width(of: view.colorDot(recent, isSelected: true) {}), 32, accuracy: 0.5)
    }

    /// The last row tops out at 9: rainbow + 7 recent + the box button.
    func testRecentCustomColorsCapAtSevenSoSecondRowHoldsNineAtMost() throws {
        let model = try makeModel()
        let hexes = ["#8E5AA8", "#2E8B8B", "#C0713A", "#3A7BC0", "#C03A6E", "#6EA83A", "#555555", "#123456", "#654321"]
        for hex in hexes { model.commitCustomColor(try XCTUnwrap(OverlayColor(hex: hex))) }
        XCTAssertEqual(model.recentColors.count, 7)
        XCTAssertEqual(1 + model.recentColors.count + 1, StyleTabView.colorColumnCount, "彩虹圓 + 7 + 底框鈕")
    }
}
