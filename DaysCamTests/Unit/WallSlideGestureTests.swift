import UIKit
import XCTest
@testable import DaysCam

/// Slide-selection decisions on the photo wall (#681): direction, hit testing
/// and priority over the wall's scroll pan.
@MainActor
final class WallSlideGestureTests: XCTestCase {
    // MARK: Direction (#681-1)

    func testShouldBeginOnlyWhenSideways() {
        XCTAssertTrue(WallSlideGesture.shouldBegin(translation: CGPoint(x: 12, y: 3)))
        XCTAssertFalse(WallSlideGesture.shouldBegin(translation: CGPoint(x: 3, y: 12)))
        XCTAssertFalse(WallSlideGesture.shouldBegin(translation: CGPoint(x: 10, y: 10)))
        XCTAssertTrue(WallSlideGesture.shouldBegin(translation: CGPoint(x: -12, y: 0)))
    }

    // MARK: Hit testing (#681-2)

    /// Two 100pt cells side by side with the wall's 2pt gap.
    private let frames: [String: CGRect] = [
        "a": CGRect(x: 0, y: 40, width: 100, height: 100),
        "b": CGRect(x: 102, y: 40, width: 100, height: 100),
    ]

    func testNearestCellReturnsCellContainingPoint() {
        XCTAssertEqual(WallSlideTracker.nearestCell(to: CGPoint(x: 150, y: 90), in: frames, maxDistance: 100), "b")
    }

    func testNearestCellInGapReturnsNearestCell() {
        XCTAssertEqual(WallSlideTracker.nearestCell(to: CGPoint(x: 100.5, y: 90), in: frames, maxDistance: 100), "a")
        XCTAssertEqual(WallSlideTracker.nearestCell(to: CGPoint(x: 101.5, y: 90), in: frames, maxDistance: 100), "b")
    }

    func testNearestCellOnMonthTitleReturnsRowBelow() {
        XCTAssertEqual(WallSlideTracker.nearestCell(to: CGPoint(x: 30, y: 15), in: frames, maxDistance: 100), "a")
    }

    func testNearestCellFarFromAllCellsReturnsNil() {
        XCTAssertNil(WallSlideTracker.nearestCell(to: CGPoint(x: 100, y: 400), in: frames, maxDistance: 100))
    }

    func testNearestCellWithNoFramesReturnsNil() {
        XCTAssertNil(WallSlideTracker.nearestCell(to: .zero, in: [:], maxDistance: 100))
    }

    func testIndexIgnoresFramesOfPhotosNotOnWall() {
        let tracker = WallSlideTracker()
        tracker.frames = frames
        XCTAssertEqual(tracker.index(at: CGPoint(x: 150, y: 90), in: ["a"], tolerance: 100), 0)
        XCTAssertEqual(tracker.index(at: CGPoint(x: 150, y: 90), in: ["b", "a"], tolerance: 100), 0)
    }

    // MARK: Frames survive recycling (#681-3)

    func testPruneKeepsFramesOfPhotosStillOnWall() {
        let tracker = WallSlideTracker()
        tracker.frames = frames
        tracker.prune(keeping: ["a", "b", "c"])
        XCTAssertEqual(tracker.frames, frames)
        tracker.prune(keeping: ["b"])
        XCTAssertEqual(Array(tracker.frames.keys), ["b"])
    }

    // MARK: Priority over scrolling (#681-4)

    func testScrollViewPanWaitsForSlide() {
        let coordinator = WallSlideGesture.Coordinator()
        let slide = UIPanGestureRecognizer()
        let scrollView = UIScrollView()
        XCTAssertTrue(coordinator.gestureRecognizer(slide, shouldBeRequiredToFailBy: scrollView.panGestureRecognizer))
        XCTAssertFalse(coordinator.gestureRecognizer(slide, shouldRecognizeSimultaneouslyWith: scrollView.panGestureRecognizer))
    }

    func testOtherRecognizersDoNotWaitForSlide() {
        let coordinator = WallSlideGesture.Coordinator()
        let slide = UIPanGestureRecognizer()
        let plainPan = UIPanGestureRecognizer()
        let plainView = UIView()
        plainView.addGestureRecognizer(plainPan)
        let tap = UITapGestureRecognizer()
        let scrollView = UIScrollView()
        scrollView.addGestureRecognizer(tap)
        XCTAssertFalse(coordinator.gestureRecognizer(slide, shouldBeRequiredToFailBy: plainPan))
        XCTAssertFalse(coordinator.gestureRecognizer(slide, shouldBeRequiredToFailBy: tap))
    }
}
