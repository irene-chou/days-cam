import AVFoundation
import XCTest
@testable import DaysCam

/// Issue #303 (TASK-73 ui-shell, PR #337): independent probes of the
/// viewfinder focus model and the published bias range that the developer
/// tests do not pin down.
private final class BiasRangeDevice: FocusExposureCaptureDevice {
    var isFocusPointOfInterestSupported = false
    var isExposurePointOfInterestSupported = false
    var supportedFocusModes: Set<AVCaptureDevice.FocusMode> = []
    var supportedExposureModes: Set<AVCaptureDevice.ExposureMode> = []
    var focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
    var exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
    var focusMode: AVCaptureDevice.FocusMode = .continuousAutoFocus
    var exposureMode: AVCaptureDevice.ExposureMode = .continuousAutoExposure
    var minExposureTargetBias: Float = -8
    var maxExposureTargetBias: Float = 8
    var isSubjectAreaChangeMonitoringEnabled = false

    func isFocusModeSupported(_ focusMode: AVCaptureDevice.FocusMode) -> Bool { supportedFocusModes.contains(focusMode) }
    func isExposureModeSupported(_ exposureMode: AVCaptureDevice.ExposureMode) -> Bool {
        supportedExposureModes.contains(exposureMode)
    }
    func setExposureTargetBias(_ bias: Float, completionHandler handler: ((CMTime) -> Void)?) {}
    func lockForConfiguration() throws {}
    func unlockForConfiguration() {}
}

@MainActor
final class ViewfinderFocusAcceptanceTests: XCTestCase {
    private var focused: [CGPoint] = []
    private var locked: [CGPoint] = []
    private var biases: [Float] = []
    private var deviceRange: ClosedRange<Float> = -8...8
    private var accepts = true
    private var requestID = 0
    private let size = CGSize(width: 300, height: 400)

    private func makeModel(mirrored: Bool = false) -> ViewfinderFocusModel {
        let model = ViewfinderFocusModel(
            actions: FocusExposureActions(
                focusAndExpose: { [unowned self] in focused.append($0); requestID += 1; return requestID },
                lock: { [unowned self] in locked.append($0); requestID += 1; return requestID },
                setBias: { [unowned self] in biases.append($0) },
                deviceBiasRange: { [unowned self] in deviceRange }),
            convert: { point, size in
                let x = point.x / size.width
                return CGPoint(x: mirrored ? 1 - x : x, y: point.y / size.height)
            },
            holdDuration: .milliseconds(40), dimDelay: .seconds(30), hideDelay: .seconds(30))
        model.canAcceptGesture = { [unowned self] in accepts }
        return model
    }

    private func settle(_ milliseconds: UInt64) async {
        try? await Task.sleep(nanoseconds: milliseconds * 1_000_000)
    }

    private func tap(_ model: ViewfinderFocusModel, at point: CGPoint) {
        model.touchChanged(startLocation: point, location: point, viewfinderSize: size)
        model.touchEnded()
    }

    private func drag(_ model: ViewfinderFocusModel, from start: CGPoint, dy: CGFloat) {
        model.touchChanged(startLocation: start, location: start, viewfinderSize: size)
        model.touchChanged(startLocation: start, location: CGPoint(x: start.x, y: start.y + (dy < 0 ? -11 : 11)), viewfinderSize: size)
        model.touchChanged(startLocation: start, location: CGPoint(x: start.x, y: start.y + dy), viewfinderSize: size)
        model.touchEnded()
    }

    // MARK: 73.5 front camera mirroring

    /// The model hands the converter's point to the camera untouched and draws
    /// the reticle where the finger is: mirroring belongs to the preview layer.
    func testMirroredConversionReachesTheCameraAndTheReticleStaysUnderTheFinger() {
        let model = makeModel(mirrored: true)
        tap(model, at: CGPoint(x: 75, y: 100))
        XCTAssertEqual(focused, [CGPoint(x: 0.75, y: 0.25)])
        XCTAssertEqual(model.reticle?.layerPoint, CGPoint(x: 75, y: 100))
    }

    func testPreviewBridgeWithoutALayerGivesNoPoint() {
        XCTAssertNil(PreviewLayerBridge().devicePoint(forLayerPoint: CGPoint(x: 10, y: 10)))
    }

    func testPreviewBridgeWithASessionlessLayerDoesNotCrash() {
        let bridge = PreviewLayerBridge()
        let layer = AVCaptureVideoPreviewLayer()
        layer.frame = CGRect(x: 0, y: 0, width: 300, height: 400)
        bridge.layer = layer
        if let point = bridge.devicePoint(forLayerPoint: CGPoint(x: 150, y: 200)) {
            XCTAssertTrue(point.x.isFinite && point.y.isFinite)
        }
    }

    // MARK: 73.3 lock

    /// The label follows the service only: pressing long enough asks, but
    /// nothing shows until the service answers.
    func testHoldRequestsTheLockButShowsNothingUntilTheServiceAnswers() async {
        let model = makeModel()
        model.touchChanged(startLocation: CGPoint(x: 150, y: 200), location: CGPoint(x: 150, y: 200), viewfinderSize: size)
        await settle(150)
        XCTAssertEqual(locked.count, 1)
        XCTAssertFalse(model.isLocked)
        model.receive(FocusExposureState(isLocked: true, exposureBias: 0))
        XCTAssertTrue(model.isLocked)
        model.touchEnded()
        XCTAssertTrue(focused.isEmpty, "the lift after a hold is not a tap")
    }

    /// After the hold took effect, moving the finger must not turn into an
    /// exposure drag nor cancel anything.
    func testMovingAfterTheLockSendsNoBias() async {
        let model = makeModel()
        let start = CGPoint(x: 150, y: 200)
        model.touchChanged(startLocation: start, location: start, viewfinderSize: size)
        await settle(150)
        model.touchChanged(startLocation: start, location: CGPoint(x: 150, y: 120), viewfinderSize: size)
        model.touchEnded()
        XCTAssertTrue(biases.isEmpty)
        XCTAssertEqual(locked.count, 1)
    }

    /// 73.6: a panel that opens while the finger is down must not be followed by a lock.
    func testPanelOpeningDuringTheHoldDoesNotLock() async {
        let model = makeModel()
        let start = CGPoint(x: 150, y: 200)
        model.touchChanged(startLocation: start, location: start, viewfinderSize: size)
        accepts = false
        await settle(150)
        model.touchEnded()
        XCTAssertTrue(locked.isEmpty)
        XCTAssertTrue(focused.isEmpty)
    }

    /// A tap that cannot unlock (device busy) leaves the label up: it is still true.
    func testFailedUnlockTapKeepsTheLockLabel() {
        let model = makeModel()
        model.receive(FocusExposureState(isLocked: true, exposureBias: 0))
        tap(model, at: CGPoint(x: 60, y: 80))
        model.receiveFailure()
        XCTAssertTrue(model.isLocked)
    }

    // MARK: robustness of the touch state machine

    /// SwiftUI skips `onEnded` when a gesture is cancelled (the app goes to
    /// the background mid-touch, a system gesture steals it). The next touch
    /// must still be handled as its own touch, not swallowed or aimed at the
    /// old start.
    func testNextTapIsHandledAfterATouchThatNeverEnded() async {
        let model = makeModel()
        let first = CGPoint(x: 40, y: 40)
        model.touchChanged(startLocation: first, location: first, viewfinderSize: size)
        await settle(150) // the hold fires and locks; no touchEnded ever comes
        locked.removeAll()
        let second = CGPoint(x: 200, y: 300)
        tap(model, at: second)
        XCTAssertEqual(focused, [CGPoint(x: 200.0 / 300.0, y: 300.0 / 400.0)])
    }

    // MARK: 73.2 bias

    func testSecondDragContinuesFromTheShownBias() {
        let model = makeModel()
        tap(model, at: CGPoint(x: 150, y: 200))
        drag(model, from: CGPoint(x: 150, y: 300), dy: -80)
        XCTAssertEqual(try XCTUnwrap(biases.last), 1.0, accuracy: 0.15)
        model.receive(FocusExposureState(isLocked: false, exposureBias: 1.0))
        drag(model, from: CGPoint(x: 150, y: 300), dy: 40)
        XCTAssertEqual(try XCTUnwrap(biases.last), 0.5, accuracy: 0.15)
    }

    /// A device that cannot compensate (range 0...0) never gets a non-zero bias.
    func testNoBiasBeyondAZeroWidthDeviceRange() {
        deviceRange = 0...0
        let model = makeModel()
        tap(model, at: CGPoint(x: 150, y: 200))
        drag(model, from: CGPoint(x: 150, y: 300), dy: -200)
        XCTAssertTrue(biases.allSatisfy { $0 == 0 })
        XCTAssertEqual(model.displayedBias, 0)
    }

    /// After a failed bias a fresh drag works again from the device's value.
    func testDragWorksAgainAfterAFailedBias() {
        let model = makeModel()
        tap(model, at: CGPoint(x: 150, y: 200))
        drag(model, from: CGPoint(x: 150, y: 300), dy: -80)
        model.receiveFailure()
        XCTAssertEqual(model.displayedBias, 0)
        XCTAssertNil(model.reticle, "nothing behind the reticle, so it goes")
        biases.removeAll()
        tap(model, at: CGPoint(x: 150, y: 200))
        drag(model, from: CGPoint(x: 150, y: 300), dy: -40)
        XCTAssertEqual(try XCTUnwrap(biases.last), 0.5, accuracy: 0.15)
    }

    /// Codex P2 on #337: replies to earlier requests arriving after the lift
    /// must not drop the reticle or the last requested bias.
    func testLateRepliesAfterReleaseKeepTheReticleAndTheLastBias() {
        let model = makeModel()
        tap(model, at: CGPoint(x: 150, y: 200))
        model.receive(FocusExposureState(isLocked: false, exposureBias: 1.0))
        drag(model, from: CGPoint(x: 150, y: 100), dy: 120) // 1.0 down through 0 to about -0.5
        XCTAssertEqual(try XCTUnwrap(biases.last), -0.5, accuracy: 0.11)
        model.receive(FocusExposureState(isLocked: false, exposureBias: 0.5))
        model.receive(.initial)
        model.receive(FocusExposureState(isLocked: false, exposureBias: biases.last ?? 0))
        XCTAssertNotNil(model.reticle)
        XCTAssertEqual(model.displayedBias, biases.last ?? 0, accuracy: 0.001)
    }

    /// Codex P2 on #337: a reset at rest (state already .initial) still reaches the UI.
    func testResetPublisherFiresEvenWhenTheStateWasAlreadyAtRest() {
        let service = CameraService(isCaptureSupported: false)
        var resets = 0
        let cancel = service.focusExposureResetPublisher.sink { _ in resets += 1 }
        service.resetFocusExposure(on: BiasRangeDevice()); pump()
        XCTAssertEqual(resets, 1)
        cancel.cancel()
    }

    func testResetEventRemovesTheReticleOfAPlainTap() {
        let model = makeModel()
        tap(model, at: CGPoint(x: 150, y: 200))
        model.receiveReset()
        XCTAssertNil(model.reticle)
    }

    // MARK: 82.1 late reset

    /// A reset that ran before the latest tap was executed must not close its frame.
    func testResetFromBeforeTheLatestTapKeepsTheFrame() {
        let model = makeModel()
        tap(model, at: CGPoint(x: 100, y: 100))
        tap(model, at: CGPoint(x: 200, y: 200)) // request id 2
        model.receiveReset(appliedRequestID: 1)
        XCTAssertEqual(model.reticle?.layerPoint, CGPoint(x: 200, y: 200))
        model.receiveReset(appliedRequestID: 2)
        XCTAssertNil(model.reticle, "a reset after the tap closes it")
    }

    /// A late reset leaves a lock and a bias the user set after it alone.
    func testLateResetKeepsTheLockLabel() {
        let model = makeModel()
        tap(model, at: CGPoint(x: 100, y: 100)) // id 1
        model.receive(FocusExposureState(isLocked: true, exposureBias: 0))
        model.receiveReset(appliedRequestID: 0)
        XCTAssertTrue(model.isLocked)
        XCTAssertNotNil(model.reticle)
    }

    // MARK: 82.3 stale touch at the same point

    /// onEnded lost, then the user taps the very same spot: the tap must still count.
    func testNextTapAtTheSamePointAfterALostEndStillFocuses() async {
        let model = makeModel()
        let spot = CGPoint(x: 150, y: 200)
        model.touchChanged(startLocation: spot, location: spot, viewfinderSize: size)
        await settle(150) // locked, onEnded never arrives
        focused.removeAll()
        tap(model, at: spot)
        XCTAssertEqual(focused.count, 1)
    }

    // MARK: cross ownership: CameraService.exposureBiasRange: CameraService.exposureBiasRange

    private func pump() {
        let done = expectation(description: "main drained")
        DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 2)
    }

    /// Back camera (wide range) -> front camera (narrow or no compensation) -> back again.
    func testPublishedRangeFollowsEveryCameraSwitch() {
        let service = CameraService(isCaptureSupported: false)
        let device = BiasRangeDevice()

        device.minExposureTargetBias = -8; device.maxExposureTargetBias = 8
        service.resetFocusExposure(on: device); pump()
        XCTAssertEqual(service.exposureBiasRange, -2...2)

        device.minExposureTargetBias = 0; device.maxExposureTargetBias = 0
        service.resetFocusExposure(on: device); pump()
        XCTAssertEqual(service.exposureBiasRange, 0...0)

        device.minExposureTargetBias = -3; device.maxExposureTargetBias = 0.5
        service.resetFocusExposure(on: device); pump()
        XCTAssertEqual(service.exposureBiasRange, -2...0.5)

        device.minExposureTargetBias = -8; device.maxExposureTargetBias = 8
        service.resetFocusExposure(on: device); pump()
        XCTAssertEqual(service.exposureBiasRange, -2...2)
    }

    /// The UI range and the service range agree for every combination.
    func testUIRangeEqualsServiceRangeForManyDeviceRanges() {
        let device = BiasRangeDevice()
        for low in stride(from: Float(-9), through: 3, by: 1.5) {
            for high in stride(from: low, through: 9, by: 1.5) {
                device.minExposureTargetBias = low
                device.maxExposureTargetBias = high
                XCTAssertEqual(ViewfinderFocusModel.effectiveBiasRange(deviceRange: low...high),
                               CameraService.exposureBiasRange(of: device), "\(low)...\(high)")
            }
        }
    }
}
