import XCTest
@testable import DaysCam

/// TASK-60 (60.2, 60.3): the numbers behind the gallery's pull-down-to-close.
final class GalleryDismissDragTests: XCTestCase {
    func testOnlyMostlyVerticalDragsCount() {
        XCTAssertTrue(GalleryDismissDrag.isVertical(translation: CGSize(width: 5, height: 40)), "60.2")
        XCTAssertFalse(GalleryDismissDrag.isVertical(translation: CGSize(width: 40, height: 5)), "60.3 左右翻頁")
        XCTAssertFalse(GalleryDismissDrag.isVertical(translation: CGSize(width: 20, height: 20)), "平手不算垂直")
    }

    func testDismissThresholdAndFlick() {
        XCTAssertTrue(GalleryDismissDrag.shouldDismiss(offset: 121, predictedEndOffset: 121), "過門檻")
        XCTAssertFalse(GalleryDismissDrag.shouldDismiss(offset: 120, predictedEndOffset: 150), "剛好 120 且不夠快")
        XCTAssertFalse(GalleryDismissDrag.shouldDismiss(offset: 60, predictedEndOffset: 200), "未過門檻彈回")
        XCTAssertTrue(GalleryDismissDrag.shouldDismiss(offset: 50, predictedEndOffset: 500), "速度夠快")
        XCTAssertFalse(GalleryDismissDrag.shouldDismiss(offset: 10, predictedEndOffset: 900), "幾乎沒動不算")
        XCTAssertFalse(GalleryDismissDrag.shouldDismiss(offset: -200, predictedEndOffset: -400), "往上不關閉")
    }

    func testProgressAndScaleAreClamped() {
        XCTAssertEqual(GalleryDismissDrag.progress(offset: -50), 0)
        XCTAssertEqual(GalleryDismissDrag.progress(offset: 150), 0.5, accuracy: 0.0001)
        XCTAssertEqual(GalleryDismissDrag.progress(offset: 900), 1)
        XCTAssertEqual(GalleryDismissDrag.scale(progress: 0), 1)
        XCTAssertEqual(GalleryDismissDrag.scale(progress: 1), 0.85, accuracy: 0.0001)
    }
}
