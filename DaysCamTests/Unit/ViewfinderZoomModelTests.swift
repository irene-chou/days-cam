import XCTest
@testable import DaysCam

/// Covers the pinch-to-zoom state (TASK-61, 61.5 and the model half of 61.6).
@MainActor
final class ViewfinderZoomModelTests: XCTestCase {
    private var factor: CGFloat = 1
    private var applied: [CGFloat] = []
    private var pendingHides: [() -> Void] = []

    private func makeModel() -> ViewfinderZoomModel {
        ViewfinderZoomModel(currentFactor: { [unowned self] in factor },
                            applyFactor: { [unowned self] in applied.append($0) },
                            scheduleHide: { [unowned self] in pendingHides.append($0) })
    }

    func testStartsHiddenAndNotPinching() {
        let model = makeModel()
        XCTAssertFalse(model.isPinching)
        XCTAssertFalse(model.isIndicatorVisible)
    }

    /// The request is the zoom at the pinch's start times the gesture scale,
    /// even when the real zoom moves while the pinch goes on.
    func testRequestIsStartFactorTimesMagnification() {
        factor = 2
        let model = makeModel()
        model.pinchChanged(magnification: 1.0)
        factor = 2.6
        model.pinchChanged(magnification: 1.5)
        XCTAssertEqual(applied, [2, 3])
    }

    func testEachPinchStartsFromTheCurrentFactor() {
        let model = makeModel()
        model.pinchChanged(magnification: 2)
        model.pinchEnded()
        factor = 2
        model.pinchChanged(magnification: 1.5)
        XCTAssertEqual(applied, [2, 3])
    }

    func testPinchingShowsTheIndicatorAndFlagsThePinch() {
        let model = makeModel()
        model.pinchChanged(magnification: 1.2)
        XCTAssertTrue(model.isPinching)
        XCTAssertTrue(model.isIndicatorVisible)
    }

    /// 61.5: the capsule outlasts the pinch until the scheduled hide runs.
    func testIndicatorHidesOnlyAfterTheScheduledDelay() {
        let model = makeModel()
        model.pinchChanged(magnification: 1.2)
        model.pinchEnded()
        XCTAssertFalse(model.isPinching, "手指放開後疊字可再拖曳")
        XCTAssertTrue(model.isIndicatorVisible)
        XCTAssertEqual(pendingHides.count, 1)
        pendingHides[0]()
        XCTAssertFalse(model.isIndicatorVisible)
    }

    /// A new pinch before the delay is up cancels the older hide.
    func testNewPinchCancelsAPendingHide() {
        let model = makeModel()
        model.pinchChanged(magnification: 1.2)
        model.pinchEnded()
        model.pinchChanged(magnification: 1.1)
        pendingHides[0]()
        XCTAssertTrue(model.isIndicatorVisible)
        XCTAssertTrue(model.isPinching)
    }

    func testIndicatorTextHasOneDecimalAndTimesSign() {
        XCTAssertEqual(ViewfinderZoomModel.indicatorText(for: 1), "1.0×")
        XCTAssertEqual(ViewfinderZoomModel.indicatorText(for: 2.34), "2.3×")
        XCTAssertEqual(ViewfinderZoomModel.indicatorText(for: 10), "10.0×")
    }

    func testLingerIsOneSecond() {
        XCTAssertEqual(ViewfinderZoomModel.indicatorLingerSeconds, 1)
    }
}
