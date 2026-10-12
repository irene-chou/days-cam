import SwiftUI
import UIKit
import XCTest
@testable import DaysCam

/// TASK-123 (#462): selecting a font never changes the height of the font
/// list, so no row grows or shrinks and nothing below it moves. The list is
/// hosted and measured with its real SwiftUI layout; every font used here is
/// available, so the rows keep their order and only the selection differs.
@MainActor
final class FontRowHeightTests: XCTestCase {
    private func listHeight(current: OverlayFontID,
                            weight: String? = nil,
                            expanded: OverlayFontID? = nil,
                            size: DynamicTypeSize = .large) -> CGFloat {
        let library = FakeFontLibrary([.notoSerifTC: .available, .songti: .available,
                                       .huninn: .available, .kaiti: .available])
        let model = FontLibraryModel(profileID: UUID(), currentFontID: current, currentWeightID: weight,
                                     library: library, profiles: { [] }, applyFont: { _, _ in })
        model.listDidAppear()
        let host = UIHostingController(rootView: FontListView(model: model)
            .environment(\.dynamicTypeSize, size)
            .frame(width: 375))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 4000))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        // The list resets its expansion when it appears, so expand afterwards.
        if let expanded {
            model.toggleExpansion(of: expanded)
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
        }
        return host.sizeThatFits(in: CGSize(width: 375, height: CGFloat.greatestFiniteMagnitude)).height
    }

    private let selections: [OverlayFontID] = [.pingFang, .notoSerifTC, .songti, .huninn, .kaiti]

    /// 123.1／123.2／123.3: whichever font is selected, the list is equally tall.
    func testSelectingAnyFontKeepsTheListHeight() {
        let reference = listHeight(current: .pingFang)
        XCTAssertGreaterThan(reference, 200, "the list was laid out")
        for font in selections {
            XCTAssertEqual(listHeight(current: font), reference, accuracy: 0.5, "123 選中 \(font)")
        }
    }

    /// 123.6: the same at the largest Dynamic Type size.
    func testSelectingAnyFontKeepsTheListHeightAtTheLargestTextSize() {
        let size = DynamicTypeSize.accessibility5
        let reference = listHeight(current: .pingFang, size: size)
        for font in selections {
            XCTAssertEqual(listHeight(current: font, size: size), reference, accuracy: 0.5, "123.6 選中 \(font)")
        }
    }

    /// 123.4: expanding the selected multi-weight font makes the list taller,
    /// and collapsing returns it to exactly the unselected height.
    func testExpandingGrowsTheListAndCollapsingRestoresIt() {
        let collapsed = listHeight(current: .notoSerifTC)
        let expanded = listHeight(current: .notoSerifTC, expanded: .notoSerifTC)
        XCTAssertGreaterThan(expanded, collapsed + 40, "123.4 展開後變高")
        XCTAssertEqual(listHeight(current: .pingFang), collapsed, accuracy: 0.5, "123.4 收合後與未選中同高")
    }
}
