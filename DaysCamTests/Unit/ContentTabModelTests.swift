import SwiftUI
import UIKit
import XCTest
@testable import DaysCam

/// Covers `ContentTabModel` (TASK-38 acceptance 38.3, 38.5) and the 38.6
/// content-height measurements of `ContentTabView`.
@MainActor
final class ContentTabModelTests: XCTestCase {
    func testSubTabTitlesAreFormatThenRules() {
        XCTAssertEqual(ContentTabModel.SubTab.allCases.map(\.title), ["格式", "天數規則"], "38.3")
    }

    func testDefaultsToFormat() {
        XCTAssertEqual(ContentTabModel().selectedSubTab, .format, "38.5")
    }

    func testSelectionIsRememberedWithinTheSameModel() {
        let model = ContentTabModel()
        model.selectedSubTab = .rules
        XCTAssertEqual(model.selectedSubTab, .rules, "38.5")
    }

    func testNewModelReturnsToFormat() {
        let first = ContentTabModel()
        first.selectedSubTab = .rules
        XCTAssertEqual(ContentTabModel().selectedSubTab, .format, "38.5")
    }

    // MARK: - 38.6 measured content height

    private func height(of subTab: ContentTabModel.SubTab, showDayCount: Bool = true) -> CGFloat {
        let profile = CameraProfile(name: "小寶",
                                     startDate: DateComponents(year: 2026, month: 1, day: 1),
                                     showDayCount: showDayCount,
                                     showDate: true,
                                     displayUnits: [.day])
        let content = ContentTabModel()
        content.selectedSubTab = subTab
        let format = FormatTabModel(displaySettings: DisplaySettingsModel(profile: profile) { _ in })
        let rules = RulesTabModel(profile: profile) { _ in }
        let view = ContentTabView(model: content, formatTabModel: format, rulesTabModel: rules)
            .frame(width: 375)
        let hosting = UIHostingController(rootView: view)
        return hosting.sizeThatFits(in: CGSize(width: 375, height: 2000)).height
    }

    func testMeasuredHeights() {
        let format = height(of: .format)
        let rules = height(of: .rules)
        XCTAssertLessThanOrEqual(max(format, rules), 260, "format=\(format) rules=\(rules)")
        XCTAssertGreaterThan(format, 44 * 4, "格式頁至少四列")
    }
}
