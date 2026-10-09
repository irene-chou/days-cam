import XCTest
@testable import DaysCam

/// Covers the viewfinder's focus, exposure and lock gestures (TASK-73, the
/// model half of 73.1-73.3, 73.6 and 73.7, and #315's two QA suggestions).
@MainActor
final class ViewfinderFocusModelTests: XCTestCase {
    private var focused: [CGPoint] = []
    private var locked: [CGPoint] = []
    private var biases: [Float] = []
    private var deviceRange: ClosedRange<Float> = -8...8
    private var accepts = true
    private var pinching = false
    private let size = CGSize(width: 300, height: 400)
    private var requestCounter = 0

    private func nextRequestID() -> Int {
        requestCounter += 1
        return requestCounter
    }

    private func makeModel(hold: Duration = .milliseconds(40),
                           dim: Duration = .milliseconds(60),
                           hide: Duration = .milliseconds(60)) -> ViewfinderFocusModel {
        let model = ViewfinderFocusModel(
            actions: FocusExposureActions(
                focusAndExpose: { [unowned self] in focused.append($0); return nextRequestID() },
                lock: { [unowned self] in locked.append($0); return nextRequestID() },
                setBias: { [unowned self] in biases.append($0) },
                deviceBiasRange: { [unowned self] in deviceRange }),
            convert: { point, size in CGPoint(x: point.x / size.width, y: point.y / size.height) },
            holdDuration: hold, dimDelay: dim, hideDelay: hide)
        model.canAcceptGesture = { [unowned self] in accepts }
        model.isPinching = { [unowned self] in pinching }
        return model
    }

    private func tap(_ model: ViewfinderFocusModel, at point: CGPoint = CGPoint(x: 150, y: 200)) {
        model.touchChanged(startLocation: point, location: point, viewfinderSize: size)
        model.touchEnded()
    }

    private func settle(_ milliseconds: UInt64) async {
        try? await Task.sleep(nanoseconds: milliseconds * 1_000_000)
    }

    // MARK: range and text

    /// #315 QA: the offered range is the device's own, cut to 2 EV.
    func testEffectiveRangeIsTheIntersectionOfDeviceAndTwoEV() {
        XCTAssertEqual(ViewfinderFocusModel.effectiveBiasRange(deviceRange: -8...8), -2...2)
        XCTAssertEqual(ViewfinderFocusModel.effectiveBiasRange(deviceRange: -1.5...1), -1.5...1)
        XCTAssertEqual(ViewfinderFocusModel.effectiveBiasRange(deviceRange: 0...0), 0...0)
    }

    func testEffectiveRangeNeverEmptyWhenDeviceRangeLiesOutsideTwoEV() {
        XCTAssertEqual(ViewfinderFocusModel.effectiveBiasRange(deviceRange: 3...5), 2...2)
        XCTAssertEqual(ViewfinderFocusModel.effectiveBiasRange(deviceRange: -5 ... -3), -2 ... -2)
    }

    func testClampedBiasSnapsAndStaysInRange() {
        XCTAssertEqual(ViewfinderFocusModel.clampedBias(0.73, deviceRange: -8...8), 0.7, accuracy: 0.0001)
        XCTAssertEqual(ViewfinderFocusModel.clampedBias(9, deviceRange: -8...8), 2)
        XCTAssertEqual(ViewfinderFocusModel.clampedBias(-9, deviceRange: -1.5...1), -1.5)
        XCTAssertEqual(ViewfinderFocusModel.clampedBias(1.7, deviceRange: -1.5...1), 1)
    }

    /// 73.2: the value shows only away from zero, with a sign.
    func testBiasText() {
        XCTAssertNil(ViewfinderFocusModel.biasText(for: 0))
        XCTAssertNil(ViewfinderFocusModel.biasText(for: 0.04))
        XCTAssertEqual(ViewfinderFocusModel.biasText(for: 0.7), "+0.7")
        XCTAssertEqual(ViewfinderFocusModel.biasText(for: -1.3), "-1.3")
        XCTAssertEqual(ViewfinderFocusModel.biasText(for: 2), "+2.0")
    }

    // MARK: tap

    /// 73.1: a tap focuses at the converted point and shows the reticle there.
    func testTapFocusesAtTheConvertedPointAndShowsTheReticle() {
        let model = makeModel()
        tap(model, at: CGPoint(x: 75, y: 100))
        XCTAssertEqual(focused, [CGPoint(x: 0.25, y: 0.25)])
        XCTAssertEqual(model.reticle?.layerPoint, CGPoint(x: 75, y: 100))
        XCTAssertTrue(locked.isEmpty)
    }

    func testEveryTapMakesANewReticleIdentity() {
        let model = makeModel()
        tap(model)
        let first = model.reticle?.id
        tap(model)
        XCTAssertNotEqual(model.reticle?.id, first)
    }

    /// 73.7: an unconvertible point does nothing and shows nothing.
    func testUnconvertiblePointIsIgnored() {
        let model = ViewfinderFocusModel(
            actions: FocusExposureActions(focusAndExpose: { [unowned self] in focused.append($0); return 1 },
                                          lock: { _ in 1 }, setBias: { _ in }, deviceBiasRange: { -2...2 }),
            convert: { _, _ in nil })
        model.touchChanged(startLocation: .zero, location: .zero, viewfinderSize: size)
        model.touchEnded()
        XCTAssertTrue(focused.isEmpty)
        XCTAssertNil(model.reticle)
    }

    /// 73.6: with the panel (or a capsule) open, a touch does nothing.
    func testTouchIsIgnoredWhileGesturesAreNotAccepted() {
        accepts = false
        let model = makeModel()
        tap(model)
        XCTAssertTrue(focused.isEmpty)
        XCTAssertNil(model.reticle)
    }

    // MARK: pinch

    /// 73.6: a pinch is never a tap or a hold.
    func testPinchBeforeTheTouchIgnoresIt() {
        pinching = true
        let model = makeModel()
        tap(model)
        XCTAssertTrue(focused.isEmpty)
    }

    func testPinchStartingMidTouchCancelsTheTap() {
        let model = makeModel()
        model.touchChanged(startLocation: CGPoint(x: 150, y: 200), location: CGPoint(x: 150, y: 200), viewfinderSize: size)
        pinching = true
        model.touchChanged(startLocation: CGPoint(x: 150, y: 200), location: CGPoint(x: 151, y: 200), viewfinderSize: size)
        pinching = false
        model.touchEnded()
        XCTAssertTrue(focused.isEmpty)
    }

    func testPinchStartingMidTouchCancelsTheHold() async {
        let model = makeModel()
        model.touchChanged(startLocation: CGPoint(x: 150, y: 200), location: CGPoint(x: 150, y: 200), viewfinderSize: size)
        pinching = true
        model.touchChanged(startLocation: CGPoint(x: 150, y: 200), location: CGPoint(x: 151, y: 200), viewfinderSize: size)
        await settle(120)
        XCTAssertTrue(locked.isEmpty)
    }

    // MARK: lost onEnded

    /// 85.1: onEnded lost after a lock, the same spot tapped again still focuses.
    func testSamePointRetapAfterLostEndOnLockedTouchFocuses() async {
        let model = makeModel()
        let spot = CGPoint(x: 150, y: 200)
        model.touchChanged(startLocation: spot, location: spot, viewfinderSize: size)
        await settle(120)
        focused.removeAll()
        tap(model, at: spot)
        XCTAssertEqual(focused, [CGPoint(x: 0.5, y: 0.5)])
    }

    /// 85.1: same, when the lost touch had become an exposure drag.
    func testSamePointRetapAfterLostEndOnAdjustingTouchFocuses() async {
        let model = makeModel()
        let spot = CGPoint(x: 150, y: 200)
        tap(model, at: spot)
        focused.removeAll()
        model.touchChanged(startLocation: spot, location: spot, viewfinderSize: size)
        model.touchChanged(startLocation: spot, location: CGPoint(x: 150, y: 150), viewfinderSize: size)
        await settle(100)
        tap(model, at: spot)
        XCTAssertEqual(focused.count, 1)
    }

    // MARK: hold

    /// 73.3: holding still locks at the pressed point and no tap follows.
    func testHoldLocksAndTheLiftIsNotATap() async {
        let model = makeModel()
        let point = CGPoint(x: 150, y: 200)
        model.touchChanged(startLocation: point, location: point, viewfinderSize: size)
        await settle(120)
        XCTAssertEqual(locked, [CGPoint(x: 0.5, y: 0.5)])
        model.touchEnded()
        XCTAssertTrue(focused.isEmpty)
        XCTAssertNotNil(model.reticle)
    }

    func testReleaseBeforeTheHoldIsATapNotALock() async {
        let model = makeModel(hold: .milliseconds(200))
        tap(model)
        await settle(300)
        XCTAssertEqual(focused.count, 1)
        XCTAssertTrue(locked.isEmpty)
    }

    func testMovingBeforeTheHoldCancelsIt() async {
        let model = makeModel()
        let start = CGPoint(x: 150, y: 200)
        model.touchChanged(startLocation: start, location: start, viewfinderSize: size)
        model.touchChanged(startLocation: start, location: CGPoint(x: 150, y: 230), viewfinderSize: size)
        await settle(120)
        XCTAssertTrue(locked.isEmpty)
    }

    /// 73.3 / 73.7 and #315 QA: the label follows the device, not the request.
    func testLockedFollowsTheServiceOnly() {
        let model = makeModel()
        XCTAssertFalse(model.isLocked)
        model.receive(FocusExposureState(isLocked: true, exposureBias: 0))
        XCTAssertTrue(model.isLocked)
        model.receive(.initial)
        XCTAssertFalse(model.isLocked)
    }

    func testFailedLockLeavesNoLockAndNoReticle() async {
        let model = makeModel()
        let point = CGPoint(x: 150, y: 200)
        model.touchChanged(startLocation: point, location: point, viewfinderSize: size)
        await settle(120)
        model.touchEnded()
        XCTAssertNotNil(model.reticle)
        model.receiveFailure()
        XCTAssertFalse(model.isLocked)
        XCTAssertNil(model.reticle)
    }

    func testFailedLockKeepsTheEarlierLockWhichIsStillTrue() {
        let model = makeModel()
        model.receive(FocusExposureState(isLocked: true, exposureBias: 0))
        tap(model)
        model.receiveFailure()
        XCTAssertTrue(model.isLocked)
    }

    /// 73.3: a tap on a locked camera unlocks and keeps the new reticle.
    func testTapOnLockedCameraUnlocksAndKeepsTheReticle() {
        let model = makeModel()
        model.receive(FocusExposureState(isLocked: true, exposureBias: 0))
        tap(model)
        model.receive(.initial)
        XCTAssertFalse(model.isLocked)
        XCTAssertNotNil(model.reticle)
    }

    // MARK: new tap resets exposure (TASK-88)

    /// 88.5a: a tap elsewhere shows 0 at once, before the camera answers.
    func testNewTapZeroesTheDisplayedBiasImmediately() {
        let model = makeModel(hold: .seconds(5))
        let start = startAdjusting(model)
        model.touchChanged(startLocation: start, location: CGPoint(x: 150, y: 120), viewfinderSize: size)
        model.receive(FocusExposureState(isLocked: false, exposureBias: 1))
        model.touchEnded()
        XCTAssertEqual(model.displayedBias, 1, accuracy: 0.0001)
        tap(model, at: CGPoint(x: 40, y: 60))
        XCTAssertEqual(model.displayedBias, 0)
    }

    /// 88.5a: the same spot again resets too.
    func testSamePointTapZeroesTheBias() {
        let model = makeModel()
        let spot = CGPoint(x: 150, y: 200)
        tap(model, at: spot)
        model.receive(FocusExposureState(isLocked: false, exposureBias: 0.7))
        tap(model, at: spot)
        XCTAssertEqual(model.displayedBias, 0)
    }

    /// 88.5b: a tap clears the lock shown until the camera reports.
    func testNewTapClearsTheLock() {
        let model = makeModel()
        model.receive(FocusExposureState(isLocked: true, exposureBias: 0))
        XCTAssertTrue(model.isLocked)
        tap(model, at: CGPoint(x: 40, y: 60))
        XCTAssertFalse(model.isLocked)
    }

    /// 88.5c: an answer to the old drag's request never writes back after a tap.
    func testStaleBiasRequestDoesNotComeBackAfterANewTap() {
        let model = makeModel(hold: .seconds(5))
        let start = startAdjusting(model)
        model.touchChanged(startLocation: start, location: CGPoint(x: 150, y: 120), viewfinderSize: size)
        model.touchChanged(startLocation: start, location: CGPoint(x: 150, y: 90), viewfinderSize: size)
        XCTAssertGreaterThan(model.displayedBias, 0, "request pending")
        tap(model, at: CGPoint(x: 40, y: 60))
        XCTAssertEqual(model.displayedBias, 0)
        model.receive(FocusExposureState(isLocked: false, exposureBias: 0))
        XCTAssertEqual(model.displayedBias, 0)
    }

    // MARK: exposure drag

    private func startAdjusting(_ model: ViewfinderFocusModel) -> CGPoint {
        let start = CGPoint(x: 150, y: 200)
        tap(model, at: start)
        model.receive(.initial) // the camera answers the tap with the default exposure
        model.touchChanged(startLocation: start, location: start, viewfinderSize: size)
        return start
    }

    /// 73.2: dragging up brightens, 80pt per EV, no jump when the drag starts.
    func testDragUpRaisesTheBiasAndDragDownLowersIt() {
        let model = makeModel(hold: .seconds(5))
        let start = startAdjusting(model)
        model.touchChanged(startLocation: start, location: CGPoint(x: 150, y: 195), viewfinderSize: size)
        XCTAssertTrue(biases.isEmpty, "inside the slop nothing moves")
        model.touchChanged(startLocation: start, location: CGPoint(x: 150, y: 150), viewfinderSize: size)
        XCTAssertEqual(biases.last ?? 0, 0, accuracy: 0.0001, "the drag starts where the slop was crossed")
        model.touchChanged(startLocation: start, location: CGPoint(x: 150, y: 110), viewfinderSize: size)
        XCTAssertEqual(biases.last ?? 0, 0.5, accuracy: 0.0001)
        XCTAssertEqual(model.displayedBias, 0.5, accuracy: 0.0001)
        model.touchChanged(startLocation: start, location: CGPoint(x: 150, y: 230), viewfinderSize: size)
        XCTAssertEqual(biases.last ?? 0, -1.0, accuracy: 0.0001)
    }

    /// 73.2 and #315 QA: the drag stops at the device's own limit.
    func testDragStopsAtTheDeviceRangeIntersectedWithTwoEV() {
        deviceRange = -1.5...1
        let model = makeModel(hold: .seconds(5))
        let start = startAdjusting(model)
        model.touchChanged(startLocation: start, location: CGPoint(x: 150, y: 150), viewfinderSize: size)
        model.touchChanged(startLocation: start, location: CGPoint(x: 150, y: -300), viewfinderSize: size)
        XCTAssertEqual(biases.last, 1)
        model.touchChanged(startLocation: start, location: CGPoint(x: 150, y: 700), viewfinderSize: size)
        XCTAssertEqual(biases.last, -1.5)
        XCTAssertTrue(biases.allSatisfy { (-1.5...1).contains($0) })
    }

    func testTwoEVCapAppliesWhenTheDeviceAllowsMore() {
        let model = makeModel(hold: .seconds(5))
        let start = startAdjusting(model)
        model.touchChanged(startLocation: start, location: CGPoint(x: 150, y: 150), viewfinderSize: size)
        model.touchChanged(startLocation: start, location: CGPoint(x: 150, y: -300), viewfinderSize: size)
        XCTAssertEqual(biases.last, 2)
    }

    func testDragWithoutAReticleDoesNothing() {
        let model = makeModel(hold: .seconds(5))
        let start = CGPoint(x: 150, y: 200)
        model.touchChanged(startLocation: start, location: start, viewfinderSize: size)
        model.touchChanged(startLocation: start, location: CGPoint(x: 150, y: 100), viewfinderSize: size)
        model.touchEnded()
        XCTAssertTrue(biases.isEmpty)
        XCTAssertTrue(focused.isEmpty, "a drag is not a tap")
    }

    func testSidewaysDragDoesNothing() {
        let model = makeModel(hold: .seconds(5))
        let start = startAdjusting(model)
        model.touchChanged(startLocation: start, location: CGPoint(x: 250, y: 205), viewfinderSize: size)
        model.touchChanged(startLocation: start, location: CGPoint(x: 250, y: 100), viewfinderSize: size)
        XCTAssertTrue(biases.isEmpty)
    }

    func testEqualStepsAreSentOnce() {
        let model = makeModel(hold: .seconds(5))
        let start = startAdjusting(model)
        model.touchChanged(startLocation: start, location: CGPoint(x: 150, y: 150), viewfinderSize: size)
        model.touchChanged(startLocation: start, location: CGPoint(x: 150, y: 110), viewfinderSize: size)
        model.touchChanged(startLocation: start, location: CGPoint(x: 150, y: 109), viewfinderSize: size)
        XCTAssertEqual(biases.count, 1, "the 1pt move rounds to the same step")
    }

    /// 73.2: the bias stays after the finger lifts and follows the service.
    func testBiasStaysAfterRelease() {
        let model = makeModel(hold: .seconds(5))
        let start = startAdjusting(model)
        model.touchChanged(startLocation: start, location: CGPoint(x: 150, y: 150), viewfinderSize: size)
        model.touchChanged(startLocation: start, location: CGPoint(x: 150, y: 70), viewfinderSize: size)
        model.touchEnded()
        XCTAssertEqual(model.displayedBias, 1, accuracy: 0.0001)
        model.receive(FocusExposureState(isLocked: false, exposureBias: 1))
        XCTAssertEqual(model.displayedBias, 1, accuracy: 0.0001)
    }

    /// #315 QA: a failed bias request reverts to what the device has.
    func testFailedBiasRevertsToTheDeviceValue() {
        let model = makeModel(hold: .seconds(5))
        let start = startAdjusting(model)
        model.receive(FocusExposureState(isLocked: false, exposureBias: 0.5))
        model.touchChanged(startLocation: start, location: CGPoint(x: 150, y: 150), viewfinderSize: size)
        model.touchChanged(startLocation: start, location: CGPoint(x: 150, y: 110), viewfinderSize: size)
        XCTAssertEqual(model.displayedBias, 1, accuracy: 0.0001)
        model.receiveFailure()
        XCTAssertEqual(model.displayedBias, 0.5, accuracy: 0.0001)
    }

    // MARK: reset and fade

    /// 73.4 / 73.5: a reset by the camera clears reticle and bias.
    func testResetStateRemovesTheReticleAndTheBias() {
        let model = makeModel()
        model.receive(FocusExposureState(isLocked: true, exposureBias: 1))
        tap(model)
        model.receiveReset()
        XCTAssertNil(model.reticle)
        XCTAssertEqual(model.displayedBias, 0)
        XCTAssertFalse(model.isLocked)
    }

    /// Codex P2: a scene-change reset while the state was already at rest
    /// publishes no state, only the reset event, and must still clear the frame.
    func testResetWhileAlreadyAtRestStillHidesTheReticle() {
        let model = makeModel()
        tap(model)
        XCTAssertNotNil(model.reticle)
        model.receiveReset()
        XCTAssertNil(model.reticle)
    }

    /// Codex P2: a quick drag through 0 and release; the older answers (0.5,
    /// then 0 = the initial state) arrive after the finger lifted. They must
    /// neither drop the request nor close the frame.
    func testOlderAnswersAfterAFastDragThroughZeroKeepTheLastRequest() {
        let model = makeModel(hold: .seconds(5))
        let start = startAdjusting(model)
        model.receive(FocusExposureState(isLocked: false, exposureBias: 0.5))
        model.touchChanged(startLocation: start, location: CGPoint(x: 150, y: 150), viewfinderSize: size)
        model.touchChanged(startLocation: start, location: CGPoint(x: 150, y: 190), viewfinderSize: size)
        model.touchChanged(startLocation: start, location: CGPoint(x: 150, y: 230), viewfinderSize: size)
        XCTAssertEqual(biases, [0, -0.5])
        model.touchEnded()
        model.receive(.initial)
        XCTAssertNotNil(model.reticle, "an older answer is not a reset")
        XCTAssertEqual(model.displayedBias, -0.5, accuracy: 0.0001, "the request still shows")
        model.receive(FocusExposureState(isLocked: false, exposureBias: -0.5))
        XCTAssertEqual(model.displayedBias, -0.5, accuracy: 0.0001)
        XCTAssertNotNil(model.reticle)
        model.receive(FocusExposureState(isLocked: false, exposureBias: 1))
        XCTAssertEqual(model.displayedBias, 1, "settled: the device value shows again")
    }

    /// The last answer settles the request, so a later device value shows.
    func testLastAnswerSettlesTheRequest() {
        let model = makeModel(hold: .seconds(5))
        let start = startAdjusting(model)
        model.touchChanged(startLocation: start, location: CGPoint(x: 150, y: 150), viewfinderSize: size)
        model.touchChanged(startLocation: start, location: CGPoint(x: 150, y: 110), viewfinderSize: size)
        model.touchEnded()
        model.receive(FocusExposureState(isLocked: false, exposureBias: 0.5))
        model.receiveReset()
        XCTAssertEqual(model.displayedBias, 0)
    }

    /// Dragging the bias back through 0 is not a reset: the reticle stays.
    func testDraggingTheBiasBackToZeroKeepsTheReticle() {
        let model = makeModel(hold: .seconds(5))
        let start = startAdjusting(model)
        model.receive(FocusExposureState(isLocked: false, exposureBias: 0.5))
        model.touchChanged(startLocation: start, location: CGPoint(x: 150, y: 150), viewfinderSize: size)
        model.touchChanged(startLocation: start, location: CGPoint(x: 150, y: 190), viewfinderSize: size)
        XCTAssertEqual(biases.last, 0)
        model.receive(.initial)
        XCTAssertNotNil(model.reticle)
        model.touchEnded()
        model.receive(.initial)
        XCTAssertNotNil(model.reticle)
    }

    /// TASK-82: a reset the device ran before a newer tap, announced after it,
    /// must not close the new tap's frame.
    func testLateResetFromBeforeTheLatestTapKeepsTheFrame() {
        let model = makeModel()
        tap(model)
        model.receiveReset(appliedRequestID: 0)
        XCTAssertNotNil(model.reticle)
    }

    /// A reset that ran after the latest tap closes it.
    func testResetAfterTheLatestTapClosesTheFrame() {
        let model = makeModel()
        tap(model)
        model.receiveReset(appliedRequestID: requestCounter)
        XCTAssertNil(model.reticle)
    }

    /// The race in order: tap, reset on the device, second tap, then the
    /// reset's event arrives. The second frame stays; an event for a reset
    /// after the second tap closes it.
    func testResetBetweenTwoTapsKeepsTheSecondFrameOnly() {
        let model = makeModel()
        tap(model)
        let first = requestCounter
        tap(model, at: CGPoint(x: 60, y: 80))
        model.receiveReset(appliedRequestID: first)
        XCTAssertEqual(model.reticle?.layerPoint, CGPoint(x: 60, y: 80))
        model.receiveReset(appliedRequestID: requestCounter)
        XCTAssertNil(model.reticle)
    }

    /// A late reset also leaves a lock and a bias the new request owns alone.
    func testLateResetDoesNotClearLockOrBias() {
        let model = makeModel()
        model.receive(FocusExposureState(isLocked: true, exposureBias: 1))
        tap(model)
        model.receiveReset(appliedRequestID: 0)
        model.receiveFailure() // the tap's reset-to-default shows until then; the device value is untouched
        XCTAssertTrue(model.isLocked)
        XCTAssertEqual(model.displayedBias, 1)
    }

    // MARK: TASK-82 gaps from QA #337

    /// 82.2: a panel that opens under the finger during the hold means no lock.
    func testPanelOpeningDuringTheHoldDoesNotLock() async {
        let model = makeModel()
        let start = CGPoint(x: 150, y: 200)
        model.touchChanged(startLocation: start, location: start, viewfinderSize: size)
        accepts = false
        await settle(150)
        model.touchEnded()
        XCTAssertTrue(locked.isEmpty)
        XCTAssertTrue(focused.isEmpty)
        XCTAssertNil(model.reticle)
    }

    /// 82.3: a touch whose end never came does not swallow the next one.
    func testNextTapIsHandledAfterATouchThatNeverEnded() async {
        let model = makeModel()
        let first = CGPoint(x: 40, y: 40)
        model.touchChanged(startLocation: first, location: first, viewfinderSize: size)
        await settle(150)
        locked.removeAll()
        let second = CGPoint(x: 200, y: 300)
        tap(model, at: second)
        XCTAssertEqual(focused, [CGPoint(x: 200.0 / 300.0, y: 300.0 / 400.0)])
    }

    /// 82.3: the stale touch is dropped, not ended: no tap comes from it.
    func testAStaleTouchMakesNoTapOfItsOwn() {
        let model = makeModel(hold: .seconds(5))
        let first = CGPoint(x: 40, y: 40)
        model.touchChanged(startLocation: first, location: first, viewfinderSize: size)
        let second = CGPoint(x: 200, y: 300)
        model.touchChanged(startLocation: second, location: second, viewfinderSize: size)
        model.touchEnded()
        XCTAssertEqual(focused, [CGPoint(x: 200.0 / 300.0, y: 300.0 / 400.0)])
    }

    /// 82.3: a cancelled gesture is discarded without a tap, and the hold dies.
    func testDiscardedTouchNeitherTapsNorLocks() async {
        let model = makeModel()
        let start = CGPoint(x: 150, y: 200)
        model.touchChanged(startLocation: start, location: start, viewfinderSize: size)
        model.discardTouch()
        await settle(150)
        XCTAssertTrue(focused.isEmpty)
        XCTAssertTrue(locked.isEmpty)
    }

    /// 82.4: the UI and the service cut a device range beyond 2 EV the same way.
    func testRangeBeyondTwoEVMatchesTheService() {
        for range: ClosedRange<Float> in [3...5, -5 ... -3, -8...8, -1.5...1, 0...0] {
            XCTAssertEqual(ViewfinderFocusModel.effectiveBiasRange(deviceRange: range),
                           CameraService.exposureBiasRange(minimum: range.lowerBound, maximum: range.upperBound),
                           "\(range)")
        }
    }

    func testHideReticleClearsIt() {
        let model = makeModel()
        tap(model)
        model.hideReticle()
        XCTAssertNil(model.reticle)
        XCTAssertFalse(model.isReticleDimmed)
    }

    /// 73.1: bright, then half opacity, then gone when nothing is behind it.
    func testReticleDimsThenGoes() async {
        let model = makeModel(dim: .milliseconds(50), hide: .milliseconds(150))
        tap(model)
        XCTAssertFalse(model.isReticleDimmed)
        await settle(100)
        XCTAssertTrue(model.isReticleDimmed)
        XCTAssertNotNil(model.reticle)
        await settle(250)
        XCTAssertNil(model.reticle)
    }

    func testReticleWithABiasDimsButStays() async {
        let model = makeModel()
        tap(model)
        model.receive(.initial)
        model.receive(FocusExposureState(isLocked: false, exposureBias: 1))
        await settle(250)
        XCTAssertTrue(model.isReticleDimmed)
        XCTAssertNotNil(model.reticle)
    }

    func testAdjustingBringsTheReticleBack() async {
        let model = makeModel(hold: .seconds(5), dim: .milliseconds(80), hide: .seconds(5))
        let start = startAdjusting(model)
        await settle(150)
        XCTAssertTrue(model.isReticleDimmed)
        model.touchChanged(startLocation: start, location: CGPoint(x: 150, y: 150), viewfinderSize: size)
        model.touchChanged(startLocation: start, location: CGPoint(x: 150, y: 100), viewfinderSize: size)
        XCTAssertFalse(model.isReticleDimmed)
    }
}
