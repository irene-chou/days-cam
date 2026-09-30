import SwiftUI
import UIKit
import XCTest
@testable import DaysCam

/// Regression coverage for #108's real-device QA finding: the nine-point
/// grid's dots rendered clustered in a small band near the top of the box
/// instead of spread across its full height, even though `gridBoxSide`
/// itself (the pure function deciding the box's side) was — and still is —
/// correct, and an isolated `#Preview` looked fine. `PositionTabModelTests`
/// already covers `gridBoxSide`'s own math; nothing at that level would ever
/// have caught this, since the bug was `LazyVGrid` silently not stretching
/// its *rows* to fill an imposed height (see `PositionTabView.grid`'s doc
/// comment) — a real layout behavior only a hosted, rendered view can show.
///
/// Follows `ColorSchemeEscapeTests`' pattern: a real `UIHostingController`/
/// `UIWindow`, not `#Preview` — `#Preview`'s own render path did not
/// reproduce the bug QA found on an actual device, so this deliberately
/// avoids that path too.
@MainActor
final class PositionTabViewGridFillTests: XCTestCase {
    func testNineDotsSpreadAcrossTheFullBoxHeightNotClusteredNearOneEdge() {
        let profile = CameraProfile(name: "測試",
                                     startDate: DateComponents(year: 2026, month: 1, day: 1),
                                     position: .anchor(.bottomTrailing))
        let model = PositionTabModel(profile: profile) { _ in }
        // 300 clamps to `gridBoxMaxSide` (132) — matches #108's iPhone 16 QA
        // report, where the box itself was already correctly sized (~132pt
        // square) but the dots inside it were not spread across it.
        let view = PositionTabView(model: model, availableHeight: 300)

        let dotFrames = renderedDotFrames(hosting: view, hostWidth: 375, hostHeight: 400)
        XCTAssertEqual(dotFrames.count, 9)

        // Bucket to the nearest 5pt: the selected dot is 14pt across versus
        // 7pt for the other eight, so their centers can differ by a
        // sub-point rounding amount within the *same* row without that
        // meaning a fourth row actually exists.
        let rowCenters = Set(dotFrames.map { ($0.midY / 5).rounded() * 5 }).sorted()
        XCTAssertEqual(rowCenters.count, 3, "九個點應該落在三個不同的列上，量到的列中心：\(rowCenters)")

        // The box's own grid area is `gridBoxSide - 2*4` (the `.padding(4)`
        // on each side, `PositionTabView.body`) — 124pt here. Each row
        // should own roughly a third of that, so the top and bottom row
        // centers should be far apart, not clustered together the way the
        // pre-fix `LazyVGrid` left them (under 25pt apart in the original
        // bug report).
        let rowSpan = rowCenters.last! - rowCenters.first!
        XCTAssertGreaterThan(rowSpan, 60, "三列應該分散在小框的整個高度，不是擠在一小段範圍內")
    }

    func testDotsFillBothAxesEquallyOnAConstrainedHeightLikeIPhoneSE() {
        // A moderate, non-max `availableHeight`, sanity-checking that the
        // box stays square once `gridBoxSide` is no longer pinned at
        // `gridBoxMaxSide` the way `testNineDotsSpreadAcross...` above always
        // clamps to. Not a claim that this covers every real iPhone SE
        // scenario: a *separate*, real-device #122 QA report found the box
        // non-square at SE's actual (much smaller, ~36pt) `gridBoxSide` —
        // the human's 2026-09-29 call was to track that as its own,
        // not-yet-diagnosed issue rather than fold a fix into this PR, so
        // this test intentionally does not attempt to reproduce it.
        let profile = CameraProfile(name: "測試",
                                     startDate: DateComponents(year: 2026, month: 1, day: 1),
                                     position: .anchor(.bottomTrailing))
        let model = PositionTabModel(profile: profile) { _ in }
        let availableHeight: CGFloat = 108 // gridBoxSide = 108 - 24 = 84
        let view = PositionTabView(model: model, availableHeight: availableHeight)

        let dotFrames = renderedDotFrames(hosting: view, hostWidth: 375, hostHeight: 200)
        XCTAssertEqual(dotFrames.count, 9)

        let xSpan = dotFrames.map(\.midX).max()! - dotFrames.map(\.midX).min()!
        let ySpan = dotFrames.map(\.midY).max()! - dotFrames.map(\.midY).min()!
        // Both spans should be close to each other (the box is square) and
        // comfortably above a "clustered in a sliver" span like the ~25pt
        // `ySpan` the pre-fix bug produced.
        XCTAssertEqual(xSpan, ySpan, accuracy: 3, "點的橫向、縱向分佈範圍應該接近相等（正方形），量到 xSpan=\(xSpan) ySpan=\(ySpan)")
        XCTAssertGreaterThan(ySpan, 30, "縱向不該被壓縮成一小段")
    }

    /// Hosts `view` in a real window and returns every rendered dot's frame
    /// (in window coordinates) — a small (`<= 16pt`), roughly-square view is
    /// one of the nine `Circle` dots (14pt selected, 7pt unselected).
    ///
    /// Polls until all nine dots have appeared (or a generous 3s timeout),
    /// rather than a single fixed short wait — a bot review on #111 already
    /// flagged the earlier fixed `0.1s × 5` wait as fragile on a slower CI,
    /// and QA later hit exactly that on #122: 0 dots found on their machine.
    /// A fixed wait can be too short under contention (this project's
    /// simulators are shared across several agents at once); polling costs
    /// nothing extra when the layout settles quickly, the way it does here.
    private func renderedDotFrames(hosting view: PositionTabView, hostWidth: CGFloat, hostHeight: CGFloat) -> [CGRect] {
        let hosting = UIHostingController(rootView: view.frame(width: hostWidth))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: hostWidth, height: hostHeight))
        window.rootViewController = hosting
        window.makeKeyAndVisible()
        hosting.view.frame = CGRect(x: 0, y: 0, width: hostWidth, height: hostHeight)

        var frames: [CGRect] = []
        let deadline = Date().addingTimeInterval(3)
        repeat {
            hosting.view.setNeedsLayout()
            hosting.view.layoutIfNeeded()
            frames = []
            collectDotFrames(in: hosting.view, into: &frames)
            if frames.count == 9 { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline

        return frames
    }

    private func collectDotFrames(in view: UIView, into result: inout [CGRect]) {
        let bounds = view.bounds
        if bounds.width > 0, bounds.width <= 16, abs(bounds.width - bounds.height) < 1 {
            result.append(view.convert(bounds, to: nil))
        }
        for subview in view.subviews {
            collectDotFrames(in: subview, into: &result)
        }
    }
}
