import AVFoundation
import XCTest
@testable import DaysCam

/// Issue #303 (TASK-73 core-device), 73.7 / 73.8: independent probes of the
/// focus/exposure device calls that the developer tests do not pin down.
private final class RecordingFocusDevice: FocusExposureCaptureDevice {
    var isFocusPointOfInterestSupported = true
    var isExposurePointOfInterestSupported = true
    var supportedFocusModes: Set<AVCaptureDevice.FocusMode> = [.locked, .autoFocus, .continuousAutoFocus]
    var supportedExposureModes: Set<AVCaptureDevice.ExposureMode> = [.locked, .autoExpose, .continuousAutoExposure]
    var focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
    var exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
    var focusMode: AVCaptureDevice.FocusMode = .continuousAutoFocus
    var exposureMode: AVCaptureDevice.ExposureMode = .continuousAutoExposure
    var minExposureTargetBias: Float = -8
    var maxExposureTargetBias: Float = 8
    var isSubjectAreaChangeMonitoringEnabled = false
    var lockFails = false
    private(set) var isHeld = false
    private(set) var lockCount = 0
    private(set) var unlockCount = 0
    private(set) var mutationsOutsideLock = 0
    private(set) var biasHistory: [Float] = []

    struct LockError: Error {}

    func isFocusModeSupported(_ focusMode: AVCaptureDevice.FocusMode) -> Bool { supportedFocusModes.contains(focusMode) }
    func isExposureModeSupported(_ exposureMode: AVCaptureDevice.ExposureMode) -> Bool {
        supportedExposureModes.contains(exposureMode)
    }

    func setExposureTargetBias(_ bias: Float, completionHandler handler: ((CMTime) -> Void)?) {
        if !isHeld { mutationsOutsideLock += 1 }
        biasHistory.append(bias)
    }

    func lockForConfiguration() throws {
        if lockFails { throw LockError() }
        isHeld = true
        lockCount += 1
    }

    func unlockForConfiguration() {
        isHeld = false
        unlockCount += 1
    }
}

final class FocusExposureAcceptanceTests: XCTestCase {

    // 73.7: a point supported for exposure only still meters, and focus is untouched.
    func testFocusModeUnsupportedButPointSupportedSkipsFocus() {
        let device = RecordingFocusDevice()
        device.supportedFocusModes = [.locked]
        let outcome = CameraService.applyFocusAndExpose(at: CGPoint(x: 0.3, y: 0.3), to: device)
        XCTAssertEqual(outcome, CameraService.FocusExposureOutcome(focus: false, exposure: true))
        XCTAssertEqual(device.focusMode, .continuousAutoFocus)
        XCTAssertEqual(device.focusPointOfInterest, CGPoint(x: 0.5, y: 0.5))
    }

    // 73.7: exposure unsupported (point or mode) leaves exposure alone while focus applies.
    func testExposureUnsupportedSkipsExposureOnly() {
        let device = RecordingFocusDevice()
        device.isExposurePointOfInterestSupported = false
        var outcome = CameraService.applyFocusAndExpose(at: CGPoint(x: 0.3, y: 0.3), to: device)
        XCTAssertEqual(outcome, CameraService.FocusExposureOutcome(focus: true, exposure: false))
        XCTAssertEqual(device.exposureMode, .continuousAutoExposure)

        let other = RecordingFocusDevice()
        other.supportedExposureModes = [.locked]
        outcome = CameraService.applyFocusAndExpose(at: CGPoint(x: 0.3, y: 0.3), to: other)
        XCTAssertEqual(outcome, CameraService.FocusExposureOutcome(focus: true, exposure: false))
        XCTAssertEqual(other.exposureMode, .continuousAutoExposure)
    }

    // 73.7: a device that supports nothing is not touched beyond the lock pair.
    func testNothingSupportedLeavesEveryPropertyAlone() {
        let device = RecordingFocusDevice()
        device.isFocusPointOfInterestSupported = false
        device.isExposurePointOfInterestSupported = false
        _ = CameraService.applyFocusAndExpose(at: CGPoint(x: 0.9, y: 0.9), to: device)
        XCTAssertEqual(device.focusMode, .continuousAutoFocus)
        XCTAssertEqual(device.exposureMode, .continuousAutoExposure)
        XCTAssertEqual(device.focusPointOfInterest, CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(device.exposurePointOfInterest, CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(device.lockCount, device.unlockCount)
        XCTAssertFalse(device.isHeld)
    }

    // 73.7: lockForConfiguration failing never touches the device, for every call.
    func testFailedLockMutatesNothingAndNeverUnlocks() {
        let device = RecordingFocusDevice()
        device.lockFails = true
        device.focusMode = .autoFocus
        device.exposureMode = .autoExpose
        device.isSubjectAreaChangeMonitoringEnabled = true
        _ = CameraService.applyFocusAndExpose(at: CGPoint(x: 0.1, y: 0.1), to: device)
        _ = CameraService.applyExposureBias(1, to: device)
        _ = CameraService.applyContinuousAuto(to: device)
        XCTAssertEqual(device.focusMode, .autoFocus)
        XCTAssertEqual(device.exposureMode, .autoExpose)
        XCTAssertTrue(device.isSubjectAreaChangeMonitoringEnabled)
        XCTAssertTrue(device.biasHistory.isEmpty)
        XCTAssertEqual(device.unlockCount, 0, "unlocking a lock never taken")
    }

    // 73.8: every bias write happens under the configuration lock and the lock is released.
    func testBiasWritesHappenUnderTheLockAndReleaseIt() {
        let device = RecordingFocusDevice()
        _ = CameraService.applyExposureBias(1, to: device)
        _ = CameraService.applyContinuousAuto(to: device)
        XCTAssertEqual(device.mutationsOutsideLock, 0)
        XCTAssertEqual(device.lockCount, device.unlockCount)
        XCTAssertFalse(device.isHeld)
    }

    // 73.8: clamp edges, infinities rejected, zero stays zero.
    func testBiasClampEdges() {
        let device = RecordingFocusDevice()
        XCTAssertEqual(CameraService.applyExposureBias(2, to: device), 2)
        XCTAssertEqual(CameraService.applyExposureBias(-2, to: device), -2)
        XCTAssertEqual(CameraService.applyExposureBias(0, to: device), 0)
        XCTAssertEqual(CameraService.applyExposureBias(.infinity, to: device), nil)
        XCTAssertEqual(CameraService.applyExposureBias(-.infinity, to: device), nil)
        XCTAssertEqual(CameraService.applyExposureBias(1e9, to: device), 2)
    }

    // 73.8: a device that reports a zero-width range is never asked for a value outside it.
    func testZeroWidthDeviceRangePinsBiasToThatValue() {
        let device = RecordingFocusDevice()
        device.minExposureTargetBias = 0
        device.maxExposureTargetBias = 0
        XCTAssertEqual(CameraService.applyExposureBias(1.5, to: device), 0)
        XCTAssertEqual(CameraService.applyExposureBias(-1.5, to: device), 0)
    }

    // 73.8: reset restores the centre point only where the point is supported, always clears bias and monitoring.
    func testResetWithoutPointSupportKeepsPointsButClearsBiasAndMonitoring() {
        let device = RecordingFocusDevice()
        device.isFocusPointOfInterestSupported = false
        device.isExposurePointOfInterestSupported = false
        device.focusPointOfInterest = CGPoint(x: 0.2, y: 0.2)
        device.isSubjectAreaChangeMonitoringEnabled = true
        XCTAssertTrue(CameraService.applyContinuousAuto(to: device))
        XCTAssertEqual(device.focusPointOfInterest, CGPoint(x: 0.2, y: 0.2))
        XCTAssertEqual(device.biasHistory, [0])
        XCTAssertFalse(device.isSubjectAreaChangeMonitoringEnabled)
        XCTAssertEqual(device.focusMode, .continuousAutoFocus)
    }

    // 73.8: policy covers every trigger, locked or not, with no unhandled case.
    func testPolicyTable() {
        let expected: [(FocusExposureTrigger, Bool, Bool)] = [
            (.subjectAreaChanged, false, true), (.subjectAreaChanged, true, false),
            (.cameraFlipped, false, true), (.cameraFlipped, true, true),
            (.zoomPresetSelected, false, true), (.zoomPresetSelected, true, true),
            (.enteredForeground, false, true), (.enteredForeground, true, true),
            (.pinchZoomed, false, false), (.pinchZoomed, true, false)
        ]
        for (trigger, locked, reset) in expected {
            XCTAssertEqual(FocusExposurePolicy.shouldReset(on: trigger, isLocked: locked), reset, "\(trigger) locked=\(locked)")
        }
    }

    // 73.7: without a camera the service stays at the initial state and never reports a failure.
    func testServiceWithoutCameraPublishesNoStateOrFailure() {
        let service = CameraService(isCaptureSupported: false)
        var failures = 0
        let cancellable = service.focusExposureFailurePublisher.sink { _ in failures += 1 }
        service.lockFocusAndExposure(at: CGPoint(x: 0.5, y: 0.5))
        service.setExposureBias(1)
        service.resetForForeground()
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 2)
        XCTAssertEqual(service.focusExposureState, .initial)
        XCTAssertEqual(failures, 0)
        cancellable.cancel()
    }
}
