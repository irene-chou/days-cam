import XCTest
@testable import DaysCam

/// Issue #359 (TASK-88, PR #370): independent probes of what a new tap does
/// to the shown bias, the lock label and the tagged bias requests.
@MainActor
final class RetapFocusAcceptanceTests: XCTestCase {
    private var requestID = 0
    private var tagged: [(Float, Int)] = []
    private var untagged: [Float] = []
    private let size = CGSize(width: 300, height: 400)

    private func makeModel() -> ViewfinderFocusModel {
        let model = ViewfinderFocusModel(
            actions: FocusExposureActions(
                focusAndExpose: { [unowned self] _ in requestID += 1; return requestID },
                lock: { [unowned self] _ in requestID += 1; return requestID },
                setBias: { [unowned self] in untagged.append($0) },
                setBiasForRequest: { [unowned self] in tagged.append(($0, $1)) },
                deviceBiasRange: { -2...1 }),
            convert: { point, size in CGPoint(x: point.x / size.width, y: point.y / size.height) },
            holdDuration: .milliseconds(40), dimDelay: .seconds(30), hideDelay: .seconds(30))
        return model
    }

    private func tap(_ model: ViewfinderFocusModel, _ point: CGPoint) {
        model.touchChanged(startLocation: point, location: point, viewfinderSize: size)
        model.touchEnded()
    }

    private func drag(_ model: ViewfinderFocusModel, from start: CGPoint, dy: CGFloat) {
        model.touchChanged(startLocation: start, location: start, viewfinderSize: size)
        model.touchChanged(startLocation: start, location: CGPoint(x: start.x, y: start.y + (dy < 0 ? -11 : 11)), viewfinderSize: size)
        model.touchChanged(startLocation: start, location: CGPoint(x: start.x, y: start.y + dy), viewfinderSize: size)
        model.touchEnded()
    }

    private func longPress(_ model: ViewfinderFocusModel, _ point: CGPoint) async {
        model.touchChanged(startLocation: point, location: point, viewfinderSize: size)
        try? await Task.sleep(nanoseconds: 150_000_000)
        model.touchEnded()
    }

    /// 88.5a: a tap elsewhere shows 0 at once, before any camera answer.
    func testNewTapShowsZeroAtOnce() {
        let model = makeModel()
        tap(model, CGPoint(x: 100, y: 100))
        model.receive(.initial)
        model.receive(.init(isLocked: false, exposureBias: 1.0))
        XCTAssertEqual(model.displayedBias, 1.0)
        tap(model, CGPoint(x: 200, y: 300))
        XCTAssertEqual(model.displayedBias, 0)
        XCTAssertEqual(model.reticle?.id, 2)
    }

    /// 88.5a: the same point tapped again also resets.
    func testSamePointTapShowsZeroAndANewReticleID() async {
        let model = makeModel()
        tap(model, CGPoint(x: 100, y: 100))
        model.receive(.init(isLocked: false, exposureBias: -1.0))
        let first = model.reticle?.id
        try? await Task.sleep(nanoseconds: 120_000_000) // past newTouchGap
        tap(model, CGPoint(x: 100, y: 100))
        XCTAssertEqual(model.displayedBias, 0)
        XCTAssertNotEqual(model.reticle?.id, first)
    }

    /// 88.5c: the old tap's late bias answer never repaints the sun at the
    /// new point; only the camera's default exposure settles it.
    func testLateOldBiasAnswerDoesNotComeBackAtTheNewPoint() {
        let model = makeModel()
        tap(model, CGPoint(x: 100, y: 100))
        model.receive(.initial)
        drag(model, from: CGPoint(x: 100, y: 100), dy: -64) // about +0.8
        XCTAssertEqual(tagged.last?.1, 1, "bias request carries the tap's id")
        tap(model, CGPoint(x: 220, y: 300))
        model.receive(.init(isLocked: false, exposureBias: 0.8)) // late answer for the old point
        XCTAssertEqual(model.displayedBias, 0, "old bias came back at the new point")
        model.receive(.initial)
        XCTAssertEqual(model.displayedBias, 0)
    }

    /// 88.5c carry: after a new tap, a drag is tagged with the new id.
    func testDragAfterANewTapCarriesTheNewRequestID() {
        let model = makeModel()
        tap(model, CGPoint(x: 100, y: 100))
        model.receive(.initial)
        tap(model, CGPoint(x: 220, y: 300))
        model.receive(.initial)
        drag(model, from: CGPoint(x: 220, y: 300), dy: -40)
        XCTAssertFalse(tagged.isEmpty)
        XCTAssertTrue(tagged.allSatisfy { $0.1 == 2 }, "\(tagged)")
        XCTAssertTrue(untagged.isEmpty, "fell back to the untagged setter")
    }

    /// 88.5b: a tap after a lock drops the label at once; a late lock answer
    /// stays hidden until the camera answers unlocked.
    func testNewTapClearsTheLockAndALateLockAnswerStaysHidden() async {
        let model = makeModel()
        await longPress(model, CGPoint(x: 100, y: 100))
        model.receive(.init(isLocked: true, exposureBias: 0))
        XCTAssertTrue(model.isLocked)
        tap(model, CGPoint(x: 220, y: 300))
        XCTAssertFalse(model.isLocked)
        model.receive(.init(isLocked: true, exposureBias: 0)) // late
        XCTAssertFalse(model.isLocked, "stale lock answer showed the label again")
        model.receive(.initial)
        XCTAssertFalse(model.isLocked)
    }

    /// 88.5b: a long press itself does not blank the label of an earlier lock
    /// before the camera answers, and a lock answer then shows.
    func testLongPressAfterALockStillShowsTheLock() async {
        let model = makeModel()
        await longPress(model, CGPoint(x: 100, y: 100))
        model.receive(.init(isLocked: true, exposureBias: 0))
        await longPress(model, CGPoint(x: 220, y: 300))
        XCTAssertTrue(model.isLocked)
        model.receive(.init(isLocked: true, exposureBias: 0))
        XCTAssertTrue(model.isLocked)
    }

    /// Lock tap confirmation: an older tap's confirmation is ignored, the
    /// newest one ends the wait even when no state was published.
    func testTapResetConfirmationOnlyCountsForTheNewestTap() {
        let model = makeModel()
        tap(model, CGPoint(x: 100, y: 100)) // id 1
        model.receive(.init(isLocked: false, exposureBias: 0.5))
        tap(model, CGPoint(x: 220, y: 300)) // id 2
        model.receiveTapReset(appliedRequestID: 1)
        XCTAssertEqual(model.displayedBias, 0)
        model.receive(.init(isLocked: false, exposureBias: 0.5)) // stale
        XCTAssertEqual(model.displayedBias, 0, "an older confirmation ended the wait")
        model.receiveTapReset(appliedRequestID: 2)
        // wait ended: the device's own value shows now
        XCTAssertEqual(model.displayedBias, 0.5)
    }

    /// 88.5 failure: a tap the camera could not apply shows the device's real
    /// bias and lock, not a made-up 0.
    func testFailedTapShowsTheDevicesRealBiasAndLock() async {
        let model = makeModel()
        await longPress(model, CGPoint(x: 100, y: 100))
        model.receive(.init(isLocked: true, exposureBias: 0.7))
        tap(model, CGPoint(x: 220, y: 300))
        XCTAssertEqual(model.displayedBias, 0)
        XCTAssertFalse(model.isLocked)
        model.receiveFailure()
        XCTAssertEqual(model.displayedBias, 0.7, accuracy: 0.001)
        XCTAssertTrue(model.isLocked)
        XCTAssertNotNil(model.reticle, "reticle with a lock behind it must stay")
    }

    /// Failure on an at-rest device: nothing to show, so the reticle goes.
    func testFailedTapOnARestingDeviceRemovesTheReticle() {
        let model = makeModel()
        tap(model, CGPoint(x: 100, y: 100))
        model.receive(.initial)
        tap(model, CGPoint(x: 220, y: 300))
        model.receiveFailure()
        XCTAssertEqual(model.displayedBias, 0)
        XCTAssertNil(model.reticle)
    }
}
