import XCTest
@testable import DaysCam

/// TASK-58 (#271) acceptance 58.1 and 58.2: when the scroll hint shows.
final class ScrollEdgeStateTests: XCTestCase {
    private func state(content: CGFloat, container: CGFloat, offset: CGFloat = 0) -> ScrollEdgeState {
        ScrollEdgeState(contentHeight: content, containerHeight: container, offsetY: offset)
    }

    func testContentThatFitsShowsNoFade() {
        let fits = state(content: 200, container: 212)
        XCTAssertFalse(fits.canScroll, "58.2")
        XCTAssertFalse(fits.showsTopFade, "58.2")
        XCTAssertFalse(fits.showsBottomFade, "58.2")
        XCTAssertFalse(state(content: 212, container: 212).canScroll, "58.2: exactly fitting does not scroll")
    }

    func testScrollableContentAtTheTopFadesOnlyAtTheBottom() {
        let top = state(content: 400, container: 120)
        XCTAssertTrue(top.canScroll, "58.1")
        XCTAssertFalse(top.showsTopFade, "58.1")
        XCTAssertTrue(top.showsBottomFade, "58.1")
    }

    func testScrolledToTheMiddleFadesAtBothEdges() {
        let middle = state(content: 400, container: 120, offset: 100)
        XCTAssertTrue(middle.showsTopFade)
        XCTAssertTrue(middle.showsBottomFade)
    }

    func testScrolledToTheBottomFadesOnlyAtTheTop() {
        let bottom = state(content: 400, container: 120, offset: 280)
        XCTAssertTrue(bottom.showsTopFade)
        XCTAssertFalse(bottom.showsBottomFade, "58.1: 捲到底淡出消失")
    }

    func testRoundingSlackDoesNotKeepTheBottomFade() {
        XCTAssertFalse(state(content: 400, container: 120, offset: 279.5).showsBottomFade)
        XCTAssertFalse(state(content: 400.5, container: 400).canScroll)
    }

    func testContentInsetsMoveTheEdges() {
        let inset = ScrollEdgeState(contentHeight: 400, containerHeight: 120, offsetY: -10, insetTop: 10, insetBottom: 20)
        XCTAssertFalse(inset.showsTopFade, "the resting offset is -insetTop")
        let bottom = ScrollEdgeState(contentHeight: 400, containerHeight: 120, offsetY: 300, insetTop: 10, insetBottom: 20)
        XCTAssertFalse(bottom.showsBottomFade)
    }
}
