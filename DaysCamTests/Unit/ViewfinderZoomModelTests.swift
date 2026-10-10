import Combine
import XCTest
@testable import DaysCam

/// Covers the pinch-to-zoom state (TASK-61, 61.5 and the model half of 61.6).
@MainActor
final class ViewfinderZoomModelTests: XCTestCase {
    private var applied: [CGFloat] = []
    private var range = ZoomRange(minimum: 1, maximum: 10)
    private var cancellables: Set<AnyCancellable> = []

    private var appliedPresets: [CGFloat] = []

    private func makeModel(initialFactor: CGFloat = 1) -> ViewfinderZoomModel {
        ViewfinderZoomModel(initialFactor: initialFactor,
                            zoomRange: { [unowned self] in range },
                            applyFactor: { [unowned self] in applied.append($0) },
                            applyPreset: { [unowned self] in appliedPresets.append($0) })
    }

    /// How many times `model.objectWillChange` fires while `body` runs.
    private func changeCount(of model: ViewfinderZoomModel, during body: () -> Void) -> Int {
        var count = 0
        model.objectWillChange.sink { count += 1 }.store(in: &cancellables)
        body()
        return count
    }

    /// 62.3: a tap on a preset asks the camera for it and the next pinch
    /// starts from it.
    func testSelectingAPresetAppliesItAndSetsTheRequestedFactor() {
        let model = makeModel()
        model.selectPreset(ZoomPreset(displayFactor: 2))
        XCTAssertEqual(appliedPresets, [2])
        XCTAssertEqual(model.requestedFactor, 2)
        model.pinchChanged(magnification: 0.85)
        XCTAssertEqual(applied.last ?? 0, 1.7, accuracy: 0.0001)
    }

    func testSelectingAPresetOutsideTheRangeIsClamped() {
        range = ZoomRange(minimum: 1, maximum: 4)
        let model = makeModel()
        model.selectPreset(ZoomPreset(displayFactor: 0.5))
        XCTAssertEqual(appliedPresets, [1])
        XCTAssertEqual(model.requestedFactor, 1)
    }

    func testStartsHiddenAndNotPinching() {
        let model = makeModel()
        XCTAssertFalse(model.isPinching)
    }

    /// The request is the zoom at the pinch's start times the gesture scale.
    func testRequestIsStartFactorTimesMagnification() {
        let model = makeModel(initialFactor: 2)
        model.pinchChanged(magnification: 1.0)
        model.pinchChanged(magnification: 1.5)
        XCTAssertEqual(applied, [2, 3])
        XCTAssertEqual(model.requestedFactor, 3)
    }

    /// 63.3 / 63.4: the next pinch starts from where the last one asked to
    /// end, not from the camera's (late) own factor.
    func testNextPinchStartsFromRequestedFactor() {
        let model = makeModel()
        model.pinchChanged(magnification: 2)
        model.pinchEnded()
        model.pinchChanged(magnification: 1.5)
        XCTAssertEqual(applied, [2, 3])
        XCTAssertEqual(model.requestedFactor, 3)
    }

    /// The shown factor stays inside what the camera accepts, so the capsule
    /// never reads 14× when the cap is 10×.
    func testRequestedFactorIsClampedToTheRange() {
        let model = makeModel()
        model.pinchChanged(magnification: 50)
        XCTAssertEqual(model.requestedFactor, 10)
        model.pinchChanged(magnification: 0.1)
        XCTAssertEqual(model.requestedFactor, 1)
        model.pinchEnded()
        model.pinchChanged(magnification: 4)
        XCTAssertEqual(applied.last, 4, "起點是夾值後的 1，不是未夾值的 0.1")
    }

    func testResetRequestedFactorBringsTheNextPinchBackToOne() {
        let model = makeModel()
        model.pinchChanged(magnification: 3)
        model.pinchEnded()
        model.resetRequestedFactor()
        XCTAssertEqual(model.requestedFactor, 1)
        model.pinchChanged(magnification: 2)
        XCTAssertEqual(applied.last, 2)
    }

    /// 63.4: with nothing new to say, a pinch update does not publish a change.
    func testRepeatedPinchUpdatesWithSameStateDoNotPublish() {
        let model = makeModel()
        model.pinchChanged(magnification: 1) // first update: pinching
        let count = changeCount(of: model) {
            model.pinchChanged(magnification: 1)
            model.pinchChanged(magnification: 1)
        }
        XCTAssertEqual(count, 0)
    }

    /// Only a real change of the factor publishes, once per change.
    func testChangingFactorPublishesOncePerUpdate() {
        let model = makeModel()
        model.pinchChanged(magnification: 1)
        let count = changeCount(of: model) {
            model.pinchChanged(magnification: 1.2)
            model.pinchChanged(magnification: 1.4)
        }
        XCTAssertEqual(count, 2)
    }

    func testEndingTwiceDoesNotRepublish() {
        let model = makeModel()
        model.pinchChanged(magnification: 1.2)
        model.pinchEnded()
        let count = changeCount(of: model) {
            model.pinchEnded()
        }
        XCTAssertEqual(count, 0)
    }

    func testPinchFlagsFollowTheFingers() {
        let model = makeModel()
        model.pinchChanged(magnification: 1.2)
        XCTAssertTrue(model.isPinching)
        model.pinchEnded()
        XCTAssertFalse(model.isPinching, "手指放開後疊字可再拖曳")
    }

    func testIndicatorTextHasOneDecimalAndTimesSign() {
        XCTAssertEqual(ViewfinderZoomModel.indicatorText(for: 1), "1.0×")
        XCTAssertEqual(ViewfinderZoomModel.indicatorText(for: 2.34), "2.3×")
        XCTAssertEqual(ViewfinderZoomModel.indicatorText(for: 10), "10.0×")
    }
}
