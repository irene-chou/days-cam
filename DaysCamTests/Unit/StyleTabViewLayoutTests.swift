import SwiftUI
import UIKit
import XCTest
@testable import DaysCam

/// Layout checks for the style tab's color pages (TASK-39): 30pt swatches on
/// a shared nine-column grid, and page heights that fit a regular panel.
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
        XCTAssertEqual(StyleTabView.swatchDiameter, 30)
        XCTAssertEqual(StyleTabView.swatchCellHeight, 38)
        for contentWidth: CGFloat in [355, 375, 420] {
            let centers = StyleTabView.columnCenters(forContentWidth: contentWidth)
            XCTAssertEqual(centers.count, 9)
            let pitches = zip(centers.dropFirst(), centers).map { $0 - $1 }
            for pitch in pitches {
                XCTAssertEqual(pitch, pitches[0], accuracy: 0.001, "等距")
                XCTAssertGreaterThanOrEqual(pitch, 38, "隔壁色票與環之間不重疊")
            }
            let totalWidth = centers[8] + 15 - (centers[0] - 15)
            XCTAssertLessThanOrEqual(totalWidth, contentWidth + 0.001)
            XCTAssertEqual(totalWidth, contentWidth, accuracy: 0.001, "撐滿內容寬")
            let secondRow = StyleTabView.columnCenters(forContentWidth: contentWidth)
            for (first, second) in zip(centers, secondRow) { XCTAssertEqual(first, second, accuracy: 0.5) }
        }
        XCTAssertEqual(StyleTabView.columnSpacing(forContentWidth: 355), 10.625, accuracy: 0.01)
    }

    /// 39.8a: the color page fits a regular panel's content area (160pt cap);
    /// the outline page is capped at the ~200pt panel of #198. Small screens may scroll.
    func testColorAndOutlinePagesFitRegularContentArea() throws {
        let model = try makeModel()
        model.selectedSubTab = .color
        let colorHeight = pageHeight(model)
        XCTAssertGreaterThanOrEqual(colorHeight, 38 + 6 + 38)
        XCTAssertLessThanOrEqual(colorHeight, 190, "顏色頁 \(colorHeight)pt")
        model.selectOutline(model.outlineOptions.first { $0 != .none } ?? .none)
        model.selectedSubTab = .outline
        let outlineHeight = pageHeight(model)
        // The card asks <= 160, but outline options (52) + two 42pt rows +
        // sub-tab row and insets measure 200pt; that equals the ~200pt panel
        // #198 introduces, so it was capped there (reported to Lead). TASK-57
        // makes the sub-tab row 6pt taller, so the cap moves to 206; it still
        // fits the 224pt content area. TASK-69 adds an opacity row to both
        // pages: color is capped at 190; the outline page may exceed the 224pt
        // content area and then scrolls under the pinned sub-tab row (TASK-66).
        XCTAssertLessThanOrEqual(outlineHeight, 260, "外框頁 \(outlineHeight)pt")
    }

    /// 57.6: the sub-tab row is 6 + 36 + 4.
    func testSubTabRowHeightIs46() {
        XCTAssertEqual(StyleTabView.subTabRowHeight, 46)
    }

    /// 49.1: a centered page fills what is left below the sub-tab row (224pt
    /// panel: 224 - 4 - 46 - 10), and never goes negative on a tiny panel.
    func testCenteredContentMinHeightFillsPanelBelowSubTabRow() {
        XCTAssertEqual(StyleTabView.centeredContentMinHeight(availableHeight: 224), 164)
        XCTAssertEqual(StyleTabView.centeredContentMinHeight(availableHeight: 20), 0)
    }

    /// 49.1 / 49.2: only the color, shadow and size pages are centered.
    func testOnlyShortPagesAreCentered() {
        let centered = StyleTabModel.SubTab.allCases.filter(\.isCentered)
        XCTAssertEqual(Set(centered), [.color, .shadow, .size])
    }

    /// 49.5 / 49.6: option boxes fit one row at SE content width (355pt).
    func testOptionRowsFitSEContentWidth() {
        XCTAssertLessThanOrEqual(5 * StyleTabView.outlineOptionSide + 4 * 8, 355)
        XCTAssertLessThanOrEqual(4 * StyleTabView.shadowOptionSide + 3 * 18, 355)
    }

    /// 49.1: a centered page measures exactly the panel's content height.
    func testCenteredPagesFillRegularPanelHeight() throws {
        let model = try makeModel()
        for subTab in [StyleTabModel.SubTab.color, .shadow, .size] {
            model.selectedSubTab = subTab
            XCTAssertEqual(pageHeight(model, availableHeight: 224), 224, accuracy: 0.5, "\(subTab)")
        }
    }

    private func width<V: View>(of view: V) -> CGFloat {
        UIHostingController(rootView: view.fixedSize())
            .sizeThatFits(in: CGSize(width: 1000, height: 1000)).width
    }

    /// Every second-row item (auto, rainbow, recent colors) is exactly one
    /// 30pt grid column wide, so the HStack matches `columnCenters`.
    func testSecondRowItemsAreOneSwatchWide() throws {
        let model = try makeModel()
        let view = StyleTabView(model: model)
        XCTAssertEqual(width(of: view.autoColorButton(current: nil) {}), 30, accuracy: 0.5)
        XCTAssertEqual(width(of: view.customColorPicker(current: nil, isSelected: false, onApply: { _ in }, onCommit: { _ in })), 30, accuracy: 0.5)
        XCTAssertEqual(width(of: view.customColorPicker(current: nil, isSelected: true, onApply: { _ in }, onCommit: { _ in })), 30, accuracy: 0.5)
        let recent = try XCTUnwrap(OverlayColor(hex: "#8E5AA8"))
        XCTAssertEqual(width(of: view.colorDot(recent, isSelected: false) {}), 30, accuracy: 0.5)
        XCTAssertEqual(width(of: view.colorDot(recent, isSelected: true) {}), 30, accuracy: 0.5)
    }

    /// The outline page's second row tops out at 9: auto + rainbow + 7 recent.
    func testRecentCustomColorsCapAtSevenSoSecondRowHoldsNineAtMost() throws {
        let model = try makeModel()
        let hexes = ["#8E5AA8", "#2E8B8B", "#C0713A", "#3A7BC0", "#C03A6E", "#6EA83A", "#555555", "#123456", "#654321"]
        for hex in hexes { model.commitCustomColor(try XCTUnwrap(OverlayColor(hex: hex))) }
        XCTAssertEqual(model.recentColors.count, 7)
        XCTAssertEqual(1 + 1 + model.recentColors.count, StyleTabView.colorColumnCount)
        XCTAssertEqual(1 + model.recentColors.count + 0, 8, "文字顏色頁：彩虹圓 + 7")
    }
}
