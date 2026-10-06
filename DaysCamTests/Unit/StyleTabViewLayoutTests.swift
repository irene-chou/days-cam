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

    /// 39.8: measured on the rendered page, not computed. At 200pt the
    /// outline color page (auto + 9 swatches at 34pt) is drawn into a 375pt
    /// window and a scan line through the first swatch row must find ten
    /// separate swatches (no overlap) lying inside the 10pt side insets (no
    /// clipping / horizontal scrolling); the two-row color page then has to
    /// fit 200pt tall with both rows at the 42pt ring height.
    func testRegularPanelPagesFitMeasuredWidthAndHeight() throws {
        let model = try makeModel()
        model.selectOutline(model.outlineOptions.first { $0 != .none } ?? .none)
        model.selectedSubTab = .outline
        let hosting = UIHostingController(rootView: StyleTabView(model: model, availableHeight: 200)
            .frame(width: 375, height: 400, alignment: .top).background(Color.black))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 400))
        window.rootViewController = hosting
        window.makeKeyAndVisible()
        hosting.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 375, height: 400), format: format).image { _ in
            hosting.view.drawHierarchy(in: hosting.view.bounds, afterScreenUpdates: true)
        }
        let cgImage = try XCTUnwrap(image.cgImage)
        let data = try XCTUnwrap(cgImage.dataProvider?.data)
        let bytes = try XCTUnwrap(CFDataGetBytePtr(data))
        let bytesPerRow = cgImage.bytesPerRow
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        func isInk(x: Int, y: Int) -> Bool {
            let p = bytes + y * bytesPerRow + x * bytesPerPixel
            return Int(p[0]) + Int(p[1]) + Int(p[2]) > 60 * 3 // not the black test backdrop
        }
        var best: (runs: Int, minX: Int, maxX: Int)?
        for y in 0..<400 {
            var runs = 0, previous = false, minX = Int.max, maxX = 0
            for x in 0..<375 {
                let ink = isInk(x: x, y: y)
                if ink && !previous { runs += 1 }
                if ink { minX = min(minX, x); maxX = max(maxX, x) }
                previous = ink
            }
            if runs == 10, best == nil || maxX - minX > best!.maxX - best!.minX { best = (runs, minX, maxX) }
        }
        let found = try XCTUnwrap(best, "找不到由 10 顆分開色票組成的第一排（重疊或被切）")
        // The selected 自動 ring pokes at most 4pt into the 10pt inset (#155).
        XCTAssertGreaterThanOrEqual(found.minX, 6)
        XCTAssertLessThanOrEqual(found.maxX, 369)

        model.selectedSubTab = .color
        let colorHeight = UIHostingController(rootView: StyleTabView(model: model, availableHeight: 200).frame(width: 375))
            .sizeThatFits(in: CGSize(width: 375, height: CGFloat.greatestFiniteMagnitude)).height
        XCTAssertGreaterThanOrEqual(colorHeight, 42 + 6 + 42, "兩排應以 42pt 環高計")
        XCTAssertLessThanOrEqual(colorHeight, 200)
    }
}
