import AVFoundation
import Combine
import XCTest
@testable import DaysCam

/// Issue #359 (TASK-88 core-device), 88.5a / 88.5b / 88.5c: independent probes
/// of CameraService's tap reset, written against a fake that logs the exact
/// order of lock, bias and focus/exposure writes.
private final class OrderedFocusDevice: FocusExposureCaptureDevice {
    var isFocusPointOfInterestSupported = true
    var isExposurePointOfInterestSupported = true
    var supportedFocusModes: Set<AVCaptureDevice.FocusMode> = [.locked, .autoFocus, .continuousAutoFocus]
    var supportedExposureModes: Set<AVCaptureDevice.ExposureMode> = [.locked, .autoExpose, .continuousAutoExposure]
    var minExposureTargetBias: Float = -8
    var maxExposureTargetBias: Float = 8
    var isSubjectAreaChangeMonitoringEnabled = false
    var lockFails = false
    private(set) var log: [String] = []
    private(set) var bias: Float = 0
    private(set) var lockCount = 0

    var focusPointOfInterest = CGPoint(x: 0.5, y: 0.5) { didSet { log.append("focusPoint") } }
    var exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5) { didSet { log.append("exposurePoint") } }
    var focusMode: AVCaptureDevice.FocusMode = .continuousAutoFocus { didSet { log.append("focusMode:\(focusMode.rawValue)") } }
    var exposureMode: AVCaptureDevice.ExposureMode = .continuousAutoExposure {
        didSet { log.append("exposureMode:\(exposureMode.rawValue)") }
    }

    struct LockError: Error {}

    func isFocusModeSupported(_ focusMode: AVCaptureDevice.FocusMode) -> Bool { supportedFocusModes.contains(focusMode) }
    func isExposureModeSupported(_ exposureMode: AVCaptureDevice.ExposureMode) -> Bool {
        supportedExposureModes.contains(exposureMode)
    }

    func setExposureTargetBias(_ bias: Float, completionHandler handler: ((CMTime) -> Void)?) {
        self.bias = bias
        log.append("bias:\(bias)")
    }

    func lockForConfiguration() throws {
        if lockFails { throw LockError() }
        lockCount += 1
        log.append("lock")
    }

    func unlockForConfiguration() { log.append("unlock") }
}

final class RetapResetAcceptanceTests: XCTestCase {

    private func drainMain() {
        let drained = expectation(description: "main drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 2)
    }

    // 88.5a/b: bias zero, unlock to auto modes and the new point all sit inside one lock window.
    func testTapWritesEverythingInsideOneLockWindowInOrder() {
        let device = OrderedFocusDevice()
        CameraService.applyExposureBias(1, to: device)
        device.focusMode = .locked
        device.exposureMode = .locked
        let mark = device.log.count
        CameraService.applyFocusAndExpose(at: CGPoint(x: 0.25, y: 0.75), to: device)
        let window = Array(device.log[mark...])
        XCTAssertEqual(window.first, "lock")
        XCTAssertEqual(window.last, "unlock")
        XCTAssertEqual(window.filter { $0 == "lock" }.count, 1)
        XCTAssertEqual(window.filter { $0 == "unlock" }.count, 1)
        XCTAssertTrue(window.contains("bias:0.0"))
        XCTAssertTrue(window.contains("focusMode:\(AVCaptureDevice.FocusMode.autoFocus.rawValue)"))
        XCTAssertTrue(window.contains("exposureMode:\(AVCaptureDevice.ExposureMode.autoExpose.rawValue)"))
        XCTAssertTrue(window.contains("focusPoint"))
        XCTAssertTrue(window.contains("exposurePoint"))
        XCTAssertEqual(device.bias, 0)
    }

    // 88.5a: zeroing does not depend on the point/mode support flags.
    func testBiasStillZeroedWhenFocusAndExposureAreUnsupported() {
        let device = OrderedFocusDevice()
        CameraService.applyExposureBias(1.5, to: device)
        device.isFocusPointOfInterestSupported = false
        device.isExposurePointOfInterestSupported = false
        device.supportedFocusModes = []
        device.supportedExposureModes = []
        CameraService.applyFocusAndExpose(at: CGPoint(x: 0.4, y: 0.4), to: device)
        XCTAssertEqual(device.bias, 0)
    }

    // 88.5 (kept behavior): long-press lock path keeps bias, tap path of the same
    // point zeroes it, and the lock-failure path never zeroes.
    func testLockKeepsBiasButTapZeroesAndFailedLockTouchesNothing() {
        let device = OrderedFocusDevice()
        CameraService.applyExposureBias(1, to: device)
        CameraService.applyFocusAndExpose(at: CGPoint(x: 0.3, y: 0.3), to: device, resetBias: false)
        XCTAssertEqual(device.bias, 1)
        device.lockFails = true
        let mark = device.log.count
        XCTAssertNil(CameraService.applyFocusAndExpose(at: CGPoint(x: 0.3, y: 0.3), to: device))
        XCTAssertEqual(device.log.count, mark, "failed lock must write nothing")
        XCTAssertEqual(device.bias, 1)
        device.lockFails = false
        CameraService.applyFocusAndExpose(at: CGPoint(x: 0.3, y: 0.3), to: device)
        XCTAssertEqual(device.bias, 0)
    }

    // 88.5a: the tap confirmation is a separate channel from the automatic-reset
    // channel (which hides the reticle), and carries the applied request ID.
    func testTapConfirmsOnItsOwnChannelAndNeverOnAutomaticReset() {
        let service = CameraService(isCaptureSupported: false)
        let device = OrderedFocusDevice()
        var tapIDs: [Int] = []
        var autoResets = 0
        let tapSub = service.focusExposureTapResetPublisher.sink { tapIDs.append($0) }
        let autoSub = service.focusExposureResetPublisher.sink { _ in autoResets += 1 }
        service.lastAppliedFocusRequestID = 7
        service.applyTap(at: CGPoint(x: 0.5, y: 0.5), to: device)
        drainMain()
        XCTAssertEqual(tapIDs, [7])
        XCTAssertEqual(autoResets, 0)
        service.lastAppliedFocusRequestID = 8
        service.resetFocusExposure(on: device)
        drainMain()
        XCTAssertEqual(tapIDs, [7], "automatic reset must not look like a tap confirmation")
        XCTAssertEqual(autoResets, 1)
        tapSub.cancel()
        autoSub.cancel()
    }

    // 88.5c: a bias tagged with any earlier request ID is rejected, whether the
    // newer request was a tap or a long-press lock; the device is not even locked.
    func testStaleBiasRejectedAfterTapAndAfterLongPress() {
        let service = CameraService(isCaptureSupported: false)
        let device = OrderedFocusDevice()
        service.lastAppliedFocusRequestID = 1
        service.applyBias(1, forFocusRequestID: 1, to: device)
        XCTAssertEqual(device.bias, 1)

        service.lastAppliedFocusRequestID = 2
        service.applyTap(at: CGPoint(x: 0.6, y: 0.6), to: device)
        let locksAfterTap = device.lockCount
        service.applyBias(1.2, forFocusRequestID: 1, to: device)
        XCTAssertEqual(device.bias, 0)
        XCTAssertEqual(device.lockCount, locksAfterTap)

        service.lastAppliedFocusRequestID = 3 // long-press lock, bias retained by design
        CameraService.applyFocusAndExpose(at: CGPoint(x: 0.1, y: 0.1), to: device, resetBias: false)
        let locksAfterLock = device.lockCount
        service.applyBias(0.5, forFocusRequestID: 2, to: device)
        XCTAssertEqual(device.lockCount, locksAfterLock)
        XCTAssertEqual(device.bias, 0)
        service.applyBias(0.5, forFocusRequestID: 3, to: device)
        XCTAssertEqual(device.bias, 0.5)
        drainMain()
        XCTAssertEqual(service.focusExposureState.exposureBias, 0.5)
    }

    // 88.5: public entry points stay callable without a camera and keep source compatibility.
    func testPublicEntryPointsCompileAndNoOpWithoutCamera() {
        let service = CameraService(isCaptureSupported: false)
        XCTAssertEqual(service.focusAndExpose(at: CGPoint(x: 0.5, y: 0.5)), 0)
        XCTAssertEqual(service.lockFocusAndExposure(at: CGPoint(x: 0.5, y: 0.5)), 0)
        service.setExposureBias(1)
        service.setExposureBias(1, forFocusRequestID: 3)
        drainMain()
        XCTAssertEqual(service.focusExposureState, .initial)
    }
}
