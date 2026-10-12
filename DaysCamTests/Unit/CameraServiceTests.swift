import AVFoundation
import Combine
import UIKit
import os
import XCTest
@testable import DaysCam

/// Covers the parts of TASK-07 that can run without capture hardware: the
/// permission state machine (PRD §2.3), the unavailable branches (PRD §2.4)
/// and the guards on the shutter path.
///
/// Both seams the service exposes for testing are stubbed here, so no test
/// ever asks the simulator for a camera: `CameraAuthorizing` stands in for
/// `AVCaptureDevice.authorizationStatus`, and `CaptureDeviceProviding` stands
/// in for the discovery session. Anything that needs a real
/// `AVCaptureDeviceInput` is a B-level (device) acceptance item instead.
final class CameraServiceTests: XCTestCase {

    private var cancellables: Set<AnyCancellable> = []

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    // MARK: - Doubles

    private final class StubAuthorizer: CameraAuthorizing {
        var status: AVAuthorizationStatus
        var grants: Bool
        private(set) var requestCount = 0
        private(set) var statusReadCount = 0

        init(status: AVAuthorizationStatus, grants: Bool = true) {
            self.status = status
            self.grants = grants
        }

        func authorizationStatus() -> AVAuthorizationStatus {
            statusReadCount += 1
            return status
        }

        func requestAccess(completion: @escaping (Bool) -> Void) {
            requestCount += 1
            let granted = grants
            status = granted ? .authorized : .denied
            completion(granted)
        }
    }

    /// Always reports "no camera here". Handing back a real `AVCaptureDevice`
    /// is impossible in the simulator, so the configured-session path is
    /// verified on device (7.5-7.12) rather than here.
    private final class EmptyDeviceProvider: CaptureDeviceProviding {
        private(set) var requestedFacings: [CameraFacing] = []

        func device(for facing: CameraFacing) -> AVCaptureDevice? {
            requestedFacings.append(facing)
            return nil
        }
    }

    // MARK: - Helpers

    private func makeService(status: AVAuthorizationStatus,
                             grants: Bool = true,
                             captureSupported: Bool = false)
        -> (CameraService, StubAuthorizer, EmptyDeviceProvider) {
        let authorizer = StubAuthorizer(status: status, grants: grants)
        let provider = EmptyDeviceProvider()
        let service = CameraService(authorizer: authorizer,
                                    deviceProvider: provider,
                                    isCaptureSupported: captureSupported)
        return (service, authorizer, provider)
    }

    private func expect(_ service: CameraService,
                        status expected: CameraStatus,
                        file: StaticString = #filePath,
                        line: UInt = #line) {
        let reached = expectation(description: "status becomes \(expected)")
        reached.assertForOverFulfill = false
        service.$status
            .sink { if $0 == expected { reached.fulfill() } }
            .store(in: &cancellables)
        wait(for: [reached], timeout: 2)
        XCTAssertEqual(service.status, expected, file: file, line: line)
    }

    private func expect(_ service: CameraService,
                        permission expected: CameraPermission,
                        file: StaticString = #filePath,
                        line: UInt = #line) {
        let reached = expectation(description: "permission becomes \(expected)")
        reached.assertForOverFulfill = false
        service.$permission
            .sink { if $0 == expected { reached.fulfill() } }
            .store(in: &cancellables)
        wait(for: [reached], timeout: 2)
        XCTAssertEqual(service.permission, expected, file: file, line: line)
    }

    /// Lets anything already queued on the session queue and the main queue
    /// drain, for the assertions that something did *not* happen.
    private func settle() {
        let drained = expectation(description: "queues drain")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { drained.fulfill() }
        wait(for: [drained], timeout: 2)
    }

    // MARK: - Initial state

    func testStartsIdleOnTheBackCameraWithAnIdleSession() {
        let (service, _, _) = makeService(status: .notDetermined)

        XCTAssertEqual(service.status, .idle)
        XCTAssertEqual(service.permission, .notDetermined)
        XCTAssertEqual(service.facing, .back)
        XCTAssertFalse(service.session.isRunning)
    }

    func testEachServiceOwnsItsOwnSessionForTheViewToAttachTo() {
        let (first, _, _) = makeService(status: .authorized)
        let (second, _, _) = makeService(status: .authorized)

        // The view layer owns the `AVCaptureVideoPreviewLayer` and attaches it
        // to `session`. Two services must not hand out the same one, or two
        // camera screens would fight over a single session.
        XCTAssertFalse(first.session === second.session)
    }

    // MARK: - Permission state machine (PRD §2.3)

    func testAuthorizedStartPublishesAuthorized() {
        let (service, authorizer, _) = makeService(status: .authorized)

        service.start()

        expect(service, permission: .authorized)
        XCTAssertEqual(authorizer.requestCount, 0, "already-granted access must not prompt again")
    }

    func testNotDeterminedStartPromptsOnceAndPublishesTheAnswer() {
        let (service, authorizer, _) = makeService(status: .notDetermined, grants: true, captureSupported: true)

        service.start()

        expect(service, permission: .authorized)
        XCTAssertEqual(authorizer.requestCount, 1)
    }

    func testDeclinedPromptPublishesDeniedAndAsksForTheGuidanceScreen() {
        let (service, _, _) = makeService(status: .notDetermined, grants: false, captureSupported: true)

        service.start()

        expect(service, permission: .denied)
        XCTAssertTrue(service.permission.needsGuidance)
    }

    func testRestrictedAsksForTheGuidanceScreenToo() {
        let (service, _, _) = makeService(status: .restricted, captureSupported: true)

        service.start()

        expect(service, permission: .restricted)
        XCTAssertTrue(service.permission.needsGuidance)
    }

    func testAuthorizedPermissionDoesNotAskForTheGuidanceScreen() {
        XCTAssertFalse(CameraPermission.authorized.needsGuidance)
        XCTAssertFalse(CameraPermission.notDetermined.needsGuidance)
    }

    func testDeniedStartNeverTouchesTheCaptureHardware() {
        let (service, _, provider) = makeService(status: .denied, captureSupported: true)

        service.start()

        expect(service, permission: .denied)
        XCTAssertTrue(provider.requestedFacings.isEmpty)
    }

    /// PRD §2.3, last row: granting from Settings and coming back must recover
    /// without a relaunch.
    func testRefreshPermissionPicksUpAGrantMadeInSettings() {
        let (service, authorizer, _) = makeService(status: .denied, captureSupported: true)
        service.start()
        expect(service, permission: .denied)

        authorizer.status = .authorized
        service.refreshPermission()

        expect(service, permission: .authorized)
    }

    /// The counterpart: once the screen has gone, coming back to the
    /// foreground must not light the camera behind it.
    func testReturningToTheForegroundDoesNotRestartAStoppedSession() {
        let (service, _, _) = makeService(status: .authorized)
        service.start()
        expect(service, status: .unavailable(.simulator))
        service.stop()
        expect(service, status: .idle)

        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification,
                                        object: nil)
        settle()

        XCTAssertEqual(service.status, .idle,
                       "a stopped session must stay stopped until the screen asks again")
        XCTAssertEqual(service.permission, .authorized, "permission is still re-read")
    }

    func testStartAfterStopBringsTheSessionBack() {
        let (service, _, _) = makeService(status: .authorized)
        service.start()
        service.stop()
        expect(service, status: .idle)

        service.start()

        expect(service, status: .unavailable(.simulator))
    }

    func testReturningToTheForegroundRechecksPermission() {
        let (service, authorizer, _) = makeService(status: .denied, captureSupported: true)
        service.start()
        expect(service, permission: .denied)

        authorizer.status = .authorized
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification,
                                        object: nil)

        expect(service, permission: .authorized)
    }

    // MARK: - Simulator skips the permission flow (PRD §2.4, issue #64)

    /// S.1: unsupported capture must never ask about camera permission at
    /// all — there is no camera to ask about — so the guidance screen never
    /// shows over the placeholder viewfinder.
    func testUnsupportedCaptureSkipsThePermissionFlowOnStart() {
        let (service, authorizer, _) = makeService(status: .denied, captureSupported: false)

        service.start()

        expect(service, permission: .authorized)
        XCTAssertFalse(service.permission.needsGuidance)
        XCTAssertEqual(authorizer.statusReadCount, 0)
        XCTAssertEqual(authorizer.requestCount, 0)
    }

    /// S.2: the same holds for the foreground/Settings recheck path.
    func testUnsupportedCaptureSkipsThePermissionFlowOnRefresh() {
        let (service, authorizer, _) = makeService(status: .denied, captureSupported: false)

        service.refreshPermission()

        expect(service, permission: .authorized)
        XCTAssertFalse(service.permission.needsGuidance)
        XCTAssertEqual(authorizer.statusReadCount, 0)
        XCTAssertEqual(authorizer.requestCount, 0)
    }

    /// S.3: on a real device (capture supported) the guidance screen must
    /// still show for a denied permission — this fix must not touch that
    /// path.
    func testSupportedCaptureStillAsksForTheGuidanceScreenWhenDenied() {
        let (service, authorizer, _) = makeService(status: .denied, captureSupported: true)

        service.start()

        expect(service, permission: .denied)
        XCTAssertTrue(service.permission.needsGuidance)
        XCTAssertEqual(authorizer.statusReadCount, 1)
    }

    // MARK: - Unavailable branches (PRD §2.4)

    func testUnsupportedCaptureReportsSimulatorWithoutCrashing() {
        let (service, _, provider) = makeService(status: .authorized, captureSupported: false)

        service.start()

        expect(service, status: .unavailable(.simulator))
        XCTAssertFalse(service.isCaptureSupported)
        XCTAssertTrue(provider.requestedFacings.isEmpty, "no device lookup when capture is unsupported")
    }

    func testMissingCaptureDeviceReportsUnavailable() {
        let (service, _, provider) = makeService(status: .authorized, captureSupported: true)

        service.start()

        expect(service, status: .unavailable(.noCaptureDevice))
        XCTAssertEqual(provider.requestedFacings, [.back])
    }

    func testInterruptionIsPublishedAndClearedAgain() {
        let (service, _, _) = makeService(status: .authorized)
        service.start()
        expect(service, status: .unavailable(.simulator))

        NotificationCenter.default.post(name: AVCaptureSession.wasInterruptedNotification,
                                        object: service.session)
        expect(service, status: .interrupted)

        NotificationCenter.default.post(name: AVCaptureSession.interruptionEndedNotification,
                                        object: service.session)
        // The interruption ended, so the service tries to run again and lands
        // back on the reason it could not run in the first place.
        expect(service, status: .unavailable(.simulator))
    }

    func testRuntimeErrorReportsSessionFailure() {
        let (service, _, _) = makeService(status: .authorized)

        NotificationCenter.default.post(name: AVCaptureSession.runtimeErrorNotification,
                                        object: service.session)

        expect(service, status: .unavailable(.sessionFailure))
    }

    func testStopReturnsToIdle() {
        let (service, _, _) = makeService(status: .authorized)
        service.start()
        expect(service, status: .unavailable(.simulator))

        service.stop()

        expect(service, status: .idle)
        XCTAssertFalse(service.session.isRunning)
    }

    /// 7.4: repeatedly entering and leaving the camera screen must not crash.
    func testRepeatedStartStopCyclesStaySafe() {
        let (service, _, _) = makeService(status: .authorized, captureSupported: true)

        for _ in 0..<10 {
            service.start()
            service.stop()
        }

        expect(service, status: .idle)
    }

    // MARK: - Camera switching (PRD FR-5.8)

    func testFacingFlipsToTheOppositeSide() {
        XCTAssertEqual(CameraFacing.back.opposite, .front)
        XCTAssertEqual(CameraFacing.front.opposite, .back)
    }

    func testSwitchCameraKeepsTheCurrentFacingWhenTheDeviceIsMissing() {
        let (service, _, provider) = makeService(status: .authorized, captureSupported: true)
        service.start()
        expect(service, status: .unavailable(.noCaptureDevice))

        service.switchCamera()
        settle()

        XCTAssertEqual(service.facing, .back, "a failed switch must not leave a lie in the UI")
        XCTAssertTrue(provider.requestedFacings.contains(.front))
    }

    func testSwitchCameraIsANoOpWhenCaptureIsUnsupported() {
        let (service, _, provider) = makeService(status: .authorized, captureSupported: false)
        service.start()
        expect(service, status: .unavailable(.simulator))

        service.switchCamera()

        XCTAssertEqual(service.facing, .back)
        XCTAssertTrue(provider.requestedFacings.isEmpty)
    }

    // MARK: - Shutter guards (PRD FR-5.5, §2.4)

    func testCapturePhotoRefusesWhenCaptureIsUnsupported() {
        let (service, _, _) = makeService(status: .authorized, captureSupported: false)
        service.start()

        let done = expectation(description: "capture completes")
        var result: Result<UIImage, CameraCaptureError>?
        service.capturePhoto { result = $0; done.fulfill() }
        wait(for: [done], timeout: 2)

        switch result {
        case .failure(let error): XCTAssertEqual(error, .captureUnavailable)
        default: XCTFail("expected a failure, got \(String(describing: result))")
        }
    }

    func testCapturePhotoRefusesWhenTheSessionIsNotRunning() {
        let (service, _, _) = makeService(status: .authorized, captureSupported: true)
        service.start()
        expect(service, status: .unavailable(.noCaptureDevice))

        let done = expectation(description: "capture completes")
        var result: Result<UIImage, CameraCaptureError>?
        service.capturePhoto { result = $0; done.fulfill() }
        wait(for: [done], timeout: 2)

        switch result {
        case .failure(let error): XCTAssertEqual(error, .notRunning)
        default: XCTFail("expected a failure, got \(String(describing: result))")
        }
    }

    /// Called off the main thread, so the answer has to actually hop queues
    /// rather than take the already-on-main shortcut.
    func testCapturePhotoDeliversItsAnswerOnTheMainQueueFromAnyCaller() {
        let (service, _, _) = makeService(status: .authorized, captureSupported: false)
        service.start()

        let done = expectation(description: "capture completes")
        var wasOnMain = false
        DispatchQueue.global(qos: .userInitiated).async {
            service.capturePhoto { _ in
                wasOnMain = Thread.isMainThread
                done.fulfill()
            }
        }
        wait(for: [done], timeout: 2)

        XCTAssertTrue(wasOnMain)
    }

    // MARK: - The capture delegate answers exactly once (PRD FR-5.5)

    /// TASK-10 disables the shutter for the duration of a capture, so a
    /// completion that never runs — or runs twice — is what wedges it.
    func testCaptureDelegateAnswersAtMostOnce() {
        var results: [Result<UIImage, CameraCaptureError>] = []
        let delegate = PhotoCaptureDelegate { result, _ in results.append(result) }

        delegate.cancel()
        delegate.cancel()
        delegate.cancel()

        XCTAssertEqual(results.count, 1)
        switch results.first {
        case .failure(let error): XCTAssertEqual(error, .notRunning)
        default: XCTFail("expected a failure, got \(String(describing: results.first))")
        }
    }

    /// 125.1 (#465): `AVCapturePhoto` and `AVCaptureResolvedPhotoSettings`
    /// cannot be built in a test, so the racing callers are concurrent
    /// `cancel()` calls — they go through the same `deliver` guard the
    /// AVFoundation callbacks use.
    func testCaptureDelegateAnswersExactlyOnceUnderConcurrentCallers() {
        for _ in 0..<1000 {
            let count = OSAllocatedUnfairLock(initialState: 0)
            let delegate = PhotoCaptureDelegate { _, _ in count.withLock { $0 += 1 } }

            DispatchQueue.concurrentPerform(iterations: 4) { _ in delegate.cancel() }

            XCTAssertEqual(count.withLock { $0 }, 1)
        }
    }

    func testCaptureDelegateHandsItselfBackSoTheServiceCanReleaseIt() {
        var handedBack: PhotoCaptureDelegate?
        let delegate = PhotoCaptureDelegate { _, source in handedBack = source }

        delegate.cancel()

        XCTAssertTrue(handedBack === delegate)
    }

    // Not covered here: `stop()` draining a capture that is genuinely in
    // flight. Reaching that path needs a configured, running session, which
    // needs real hardware — a test written against the simulator would be
    // answered by `capturePhoto`'s `status == .running` guard long before the
    // drain ran, and would pass whether or not the drain existed. It is a
    // device-level check instead; the once-guard above is what the drain
    // relies on.

    // MARK: - Flash (PRD 0.2 FR-7.4, FR-5.12, TASK-19 acceptance 19.4)

    /// `CameraService.isFlashAvailable(facing:hasFlash:)` and
    /// `effectiveFlashMode(requested:isFlashAvailable:)` are pure functions
    /// of their arguments precisely so this branch is testable here: a real
    /// `AVCaptureDevice` cannot be constructed to report `hasFlash`, and (see
    /// the camera-switching tests above) `EmptyDeviceProvider` cannot make a
    /// real switch to the front camera succeed either.
    func test_isFlashAvailable_falseOnFrontCameraRegardlessOfHasFlash() {
        XCTAssertFalse(CameraService.isFlashAvailable(facing: .front, hasFlash: true))
        XCTAssertFalse(CameraService.isFlashAvailable(facing: .front, hasFlash: false))
    }

    func test_isFlashAvailable_falseOnBackCameraWithNoFlashUnit() {
        XCTAssertFalse(CameraService.isFlashAvailable(facing: .back, hasFlash: false))
    }

    func test_isFlashAvailable_trueOnBackCameraWithAFlashUnit() {
        XCTAssertTrue(CameraService.isFlashAvailable(facing: .back, hasFlash: true))
    }

    /// 19.4: whatever was requested, an unavailable flash is sent as `.off`.
    func test_effectiveFlashMode_forcesOffWhenUnavailable() {
        for requested: FlashMode in [.off, .auto, .on] {
            XCTAssertEqual(CameraService.effectiveFlashMode(requested: requested, isFlashAvailable: false), .off)
        }
    }

    func test_effectiveFlashMode_passesThroughWhenAvailable() {
        XCTAssertEqual(CameraService.effectiveFlashMode(requested: .off, isFlashAvailable: true), .off)
        XCTAssertEqual(CameraService.effectiveFlashMode(requested: .auto, isFlashAvailable: true), .auto)
        XCTAssertEqual(CameraService.effectiveFlashMode(requested: .on, isFlashAvailable: true), .on)
    }

    /// The instance property wires the two pure functions above to the live
    /// `facing`/`flashCapabilityProvider` — this is the "no flash unit on
    /// the current side" half of 19.4 exercised through the real object.
    func test_isFlashAvailableProperty_reflectsTheInjectedCapabilityProvider() {
        struct NoFlash: FlashCapabilityProviding {
            func hasFlash(for facing: CameraFacing) -> Bool { false }
        }
        let service = CameraService(authorizer: StubAuthorizer(status: .authorized),
                                    deviceProvider: EmptyDeviceProvider(),
                                    flashCapabilityProvider: NoFlash(),
                                    isCaptureSupported: false)

        XCTAssertEqual(service.facing, .back, "starts on the back camera")
        XCTAssertFalse(service.isFlashAvailable, "the fake device reports no flash unit")
    }

    private final class CountingFlashProvider: FlashCapabilityProviding {
        var calls: [CameraFacing] = []
        var backHasFlash = true
        func hasFlash(for facing: CameraFacing) -> Bool {
            calls.append(facing)
            return facing == .back && backHasFlash
        }
    }

    /// 131.1 (#471): repeated reads do not repeat the device lookup.
    func test_isFlashAvailable_looksUpTheDeviceOncePerSide() {
        let provider = CountingFlashProvider()
        let service = CameraService(authorizer: StubAuthorizer(status: .authorized),
                                    deviceProvider: EmptyDeviceProvider(),
                                    flashCapabilityProvider: provider,
                                    isCaptureSupported: false)
        for _ in 0..<100 { _ = service.isFlashAvailable }
        XCTAssertEqual(provider.calls, [.back], "131.1")
    }

    /// 131.2 (#471): the value follows the side after a switch.
    func test_isFlashAvailable_followsTheFacingAfterASwitch() {
        let provider = CountingFlashProvider()
        let service = CameraService(authorizer: StubAuthorizer(status: .authorized),
                                    deviceProvider: EmptyDeviceProvider(),
                                    flashCapabilityProvider: provider,
                                    isCaptureSupported: false)
        XCTAssertEqual(service.isFlashAvailable, CameraService.isFlashAvailable(facing: .back, hasFlash: true))
        service.setFacingForTesting(.front)
        for _ in 0..<100 { _ = service.isFlashAvailable }
        XCTAssertFalse(service.isFlashAvailable, "131.2 front has no flash")
        XCTAssertEqual(provider.calls, [.back, .front], "131.1 once per side")
        service.setFacingForTesting(.back)
        XCTAssertEqual(service.isFlashAvailable, CameraService.isFlashAvailable(facing: .back, hasFlash: true), "131.2")
        XCTAssertEqual(provider.calls.count, 2)
    }
}

// MARK: - Front camera mirroring (issue #272, TASK-59)

/// A capture connection reduced to its mirroring switches. Starts the way
/// AVFoundation hands a fresh connection out — automatic adjustment on — and
/// fails the test on the two assignments AVFoundation would raise on.
private final class FakeMirroringConnection: VideoMirroringConfigurable {
    let isVideoMirroringSupported: Bool
    var automaticallyAdjustsVideoMirroring = true
    var isVideoMirrored = false {
        didSet {
            XCTAssertTrue(isVideoMirroringSupported, "mirroring set on an unsupported connection")
            XCTAssertFalse(automaticallyAdjustsVideoMirroring, "mirroring set while automatic adjustment is on")
            assignments += 1
        }
    }
    private(set) var assignments = 0

    init(isVideoMirroringSupported: Bool = true) {
        self.isVideoMirroringSupported = isVideoMirroringSupported
    }
}

final class CameraServiceMirroringTests: XCTestCase {

    /// 59.1 / 59.3: front mirrored like its preview, back never.
    func testOnlyTheFrontCameraIsMirrored() {
        XCTAssertTrue(CameraService.isPhotoMirrored(facing: .front))
        XCTAssertFalse(CameraService.isPhotoMirrored(facing: .back))
    }

    func testFrontConnectionIsMirroredWithAutomaticAdjustmentOff() {
        let connection = FakeMirroringConnection()
        CameraService.configureMirroring(of: connection, for: .front)
        XCTAssertFalse(connection.automaticallyAdjustsVideoMirroring)
        XCTAssertTrue(connection.isVideoMirrored)
    }

    /// 59.3: the back camera is set explicitly, not left to the default.
    func testBackConnectionIsExplicitlyNotMirrored() {
        let connection = FakeMirroringConnection()
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = true
        CameraService.configureMirroring(of: connection, for: .back)
        XCTAssertFalse(connection.automaticallyAdjustsVideoMirroring)
        XCTAssertFalse(connection.isVideoMirrored)
    }

    func testUnsupportedConnectionIsLeftAlone() {
        let connection = FakeMirroringConnection(isVideoMirroringSupported: false)
        CameraService.configureMirroring(of: connection, for: .front)
        XCTAssertTrue(connection.automaticallyAdjustsVideoMirroring)
        XCTAssertEqual(connection.assignments, 0)
    }

    /// 59.4 on one connection: many switches end on the last side's setting.
    func testRepeatedSwitchesOnOneConnectionFollowTheCurrentSide() {
        let connection = FakeMirroringConnection()
        var facing = CameraFacing.back
        CameraService.configureMirroring(of: connection, for: facing)
        for _ in 0..<7 {
            facing = facing.opposite
            CameraService.configureMirroring(of: connection, for: facing)
            XCTAssertEqual(connection.isVideoMirrored, facing == .front, "\(facing)")
            XCTAssertFalse(connection.automaticallyAdjustsVideoMirroring)
        }
        XCTAssertEqual(facing, .front)
        XCTAssertTrue(connection.isVideoMirrored)
    }

    /// 59.4 with a rebuilt connection after every input swap, which is what
    /// AVFoundation does: each fresh connection comes back on automatic and
    /// still ends up right.
    func testRepeatedSwitchesWithARebuiltConnectionFollowTheCurrentSide() {
        var facing = CameraFacing.back
        for _ in 0..<8 {
            facing = facing.opposite
            let connection = FakeMirroringConnection()
            CameraService.configureMirroring(of: connection, for: facing)
            XCTAssertFalse(connection.automaticallyAdjustsVideoMirroring)
            XCTAssertEqual(connection.isVideoMirrored, facing == .front, "\(facing)")
        }
    }
}

// MARK: - Zoom (issue #274, TASK-61 acceptance 61.3, 61.4, 61.7)

/// A capture device reduced to its zoom. Fails the test on a zoom set without
/// holding the configuration lock, which AVFoundation would raise on.
private final class FakeZoomDevice: ZoomableCaptureDevice {
    let minAvailableVideoZoomFactor: CGFloat
    let maxAvailableVideoZoomFactor: CGFloat
    var videoZoomFactor: CGFloat = 1 {
        didSet { XCTAssertTrue(isLocked, "videoZoomFactor set without the configuration lock") }
    }
    var lockFails = false
    private(set) var isLocked = false
    private(set) var lockCount = 0

    struct LockError: Error {}

    init(min: CGFloat = 1, max: CGFloat = 16) {
        minAvailableVideoZoomFactor = min
        maxAvailableVideoZoomFactor = max
    }

    func lockForConfiguration() throws {
        if lockFails { throw LockError() }
        isLocked = true
        lockCount += 1
    }

    func unlockForConfiguration() {
        isLocked = false
    }
}

final class CameraServiceZoomTests: XCTestCase {

    // MARK: Range

    /// 61.3: never past 10×, even when the device goes further.
    func testRangeIsCappedAtTenTimes() {
        XCTAssertEqual(CameraService.zoomRange(minAvailable: 1, maxAvailable: 123),
                       ZoomRange(minimum: 1, maximum: 10))
    }

    /// 61.3: a device that stops short of 10× keeps its own maximum.
    func testRangeKeepsASmallerDeviceMaximum() {
        XCTAssertEqual(CameraService.zoomRange(minAvailable: 1, maxAvailable: 4),
                       ZoomRange(minimum: 1, maximum: 4))
    }

    /// A device that can go below 1× (an ultra-wide virtual device) keeps it.
    func testRangeKeepsADeviceMinimumBelowOne() {
        XCTAssertEqual(CameraService.zoomRange(minAvailable: 0.5, maxAvailable: 15),
                       ZoomRange(minimum: 0.5, maximum: 10))
    }

    // MARK: Clamping (61.7)

    func testFactorBelowTheMinimumIsRaisedToIt() {
        let device = FakeZoomDevice(min: 1, max: 16)
        XCTAssertEqual(CameraService.applyZoom(0.3, to: device), 1)
        XCTAssertEqual(device.videoZoomFactor, 1)
    }

    func testFactorAboveTheDeviceMaximumIsLoweredToIt() {
        let device = FakeZoomDevice(min: 1, max: 4)
        XCTAssertEqual(CameraService.applyZoom(6, to: device), 4)
        XCTAssertEqual(device.videoZoomFactor, 4)
    }

    func testFactorAboveTenIsLoweredToTen() {
        let device = FakeZoomDevice(min: 1, max: 16)
        XCTAssertEqual(CameraService.applyZoom(12.5, to: device), 10)
        XCTAssertEqual(device.videoZoomFactor, 10)
    }

    func testFactorInRangeIsSetAsIsUnderTheLock() {
        let device = FakeZoomDevice()
        XCTAssertEqual(CameraService.applyZoom(2.3, to: device), 2.3)
        XCTAssertEqual(device.videoZoomFactor, 2.3)
        XCTAssertEqual(device.lockCount, 1)
        XCTAssertFalse(device.isLocked, "the lock is released again")
    }

    func testFailedLockLeavesTheZoomAlone() {
        let device = FakeZoomDevice()
        device.lockFails = true
        XCTAssertNil(CameraService.applyZoom(3, to: device))
        XCTAssertEqual(device.videoZoomFactor, 1)
    }

    // MARK: Switching (61.4, 61.7)

    /// 61.4: the reset a switch applies brings either side back to 1×, even
    /// though a device keeps its factor across input swaps — going back to a
    /// side zoomed earlier must not resume at the old factor.
    func testSwitchResetBringsEachSideBackToOne() {
        let back = FakeZoomDevice(min: 1, max: 16)
        let front = FakeZoomDevice(min: 1, max: 4)

        CameraService.applyZoom(3, to: back)
        CameraService.applyZoom(1, to: front) // switch to front
        CameraService.applyZoom(2, to: front)
        CameraService.applyZoom(1, to: back) // switch back

        XCTAssertEqual(back.videoZoomFactor, 1)
        XCTAssertEqual(front.videoZoomFactor, 2, "front untouched until it is switched to again")
        CameraService.applyZoom(1, to: front) // and to front again
        XCTAssertEqual(front.videoZoomFactor, 1)
    }

    // MARK: Service

    func testServiceStartsUnzoomedWithAFixedRange() {
        let service = CameraService(isCaptureSupported: false)
        XCTAssertEqual(service.zoomFactor, 1)
        XCTAssertEqual(service.zoomRange, .fixed)
    }

    /// Without a camera (the simulator) zooming is a no-op, not a crash.
    func testSetZoomFactorIsANoOpWithoutCapture() {
        let service = CameraService(isCaptureSupported: false)
        service.setZoomFactor(5)
        let drained = expectation(description: "queues drain")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { drained.fulfill() }
        wait(for: [drained], timeout: 2)
        XCTAssertEqual(service.zoomFactor, 1)
    }
}

// MARK: - Focus and exposure (issue #303, acceptance 73.7 / 73.8)

private final class FakeFocusDevice: FocusExposureCaptureDevice {
    var isFocusPointOfInterestSupported = true
    var isExposurePointOfInterestSupported = true
    var supportedFocusModes: Set<AVCaptureDevice.FocusMode> = [.locked, .autoFocus, .continuousAutoFocus]
    var supportedExposureModes: Set<AVCaptureDevice.ExposureMode> = [.locked, .autoExpose, .continuousAutoExposure]
    var focusPointOfInterest = CGPoint(x: 0.5, y: 0.5) {
        didSet { XCTAssertTrue(isLocked, "focus point set outside lock") }
    }
    var exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5) {
        didSet { XCTAssertTrue(isLocked, "exposure point set outside lock") }
    }
    var focusMode: AVCaptureDevice.FocusMode = .continuousAutoFocus {
        didSet { if focusMode == .autoFocus { XCTAssertTrue(isLocked, "focus mode set outside lock") } }
    }
    var exposureMode: AVCaptureDevice.ExposureMode = .continuousAutoExposure {
        didSet { if exposureMode == .autoExpose { XCTAssertTrue(isLocked, "exposure mode set outside lock") } }
    }
    var minExposureTargetBias: Float = -8
    var maxExposureTargetBias: Float = 8
    var isSubjectAreaChangeMonitoringEnabled = false
    private(set) var bias: Float = 0
    var lockFails = false
    private(set) var isLocked = false
    private(set) var lockCount = 0
    private(set) var unlockCount = 0

    struct LockError: Error {}

    func isFocusModeSupported(_ focusMode: AVCaptureDevice.FocusMode) -> Bool { supportedFocusModes.contains(focusMode) }
    func isExposureModeSupported(_ exposureMode: AVCaptureDevice.ExposureMode) -> Bool {
        supportedExposureModes.contains(exposureMode)
    }

    func setExposureTargetBias(_ bias: Float, completionHandler handler: ((CMTime) -> Void)?) {
        XCTAssertTrue(isLocked, "bias set without the configuration lock")
        self.bias = bias
    }

    func lockForConfiguration() throws {
        if lockFails { throw LockError() }
        isLocked = true
        lockCount += 1
    }

    func unlockForConfiguration() {
        isLocked = false
        unlockCount += 1
    }
}

final class CameraServiceFocusExposureTests: XCTestCase {

    func testNewAndRepeatedTapResetBiasAndUnlockInOneConfiguration() {
        let device = FakeFocusDevice()
        let points = [CGPoint(x: 0.2, y: 0.7), CGPoint(x: 0.8, y: 0.1), CGPoint(x: 0.8, y: 0.1)]
        for point in points {
            CameraService.applyExposureBias(1, to: device)
            device.focusMode = .locked
            device.exposureMode = .locked
            let before = device.lockCount
            CameraService.applyFocusAndExpose(at: point, to: device)
            XCTAssertEqual(device.bias, 0)
            XCTAssertEqual(device.focusMode, .autoFocus)
            XCTAssertEqual(device.exposureMode, .autoExpose)
            XCTAssertEqual(device.focusPointOfInterest, point)
            XCTAssertEqual(device.exposurePointOfInterest, point)
            XCTAssertEqual(device.lockCount, before + 1)
            XCTAssertEqual(device.unlockCount, device.lockCount)
        }
    }

    func testLongPressLockKeepsBias() {
        let device = FakeFocusDevice()
        CameraService.applyExposureBias(1, to: device)
        CameraService.applyFocusAndExpose(at: CGPoint(x: 0.3, y: 0.6), to: device, resetBias: false)
        XCTAssertEqual(device.bias, 1)
    }

    func testTapPublishesZeroUnlockedAndConfirmationEvenForRepeatedTap() {
        let service = CameraService(isCaptureSupported: false)
        let device = FakeFocusDevice()
        var confirmations: [Int] = []
        let subscription = service.focusExposureTapResetPublisher.sink { confirmations.append($0) }
        service.lastAppliedFocusRequestID = 1
        service.applyBias(1, forFocusRequestID: 1, to: device)
        service.lastAppliedFocusRequestID = 2
        service.applyTap(at: CGPoint(x: 0.8, y: 0.1), to: device)
        service.lastAppliedFocusRequestID = 3
        service.applyTap(at: CGPoint(x: 0.8, y: 0.1), to: device)
        let flushed = expectation(description: "tap feedback delivered")
        DispatchQueue.main.async { flushed.fulfill() }
        wait(for: [flushed], timeout: 2)
        XCTAssertEqual(service.focusExposureState, .initial)
        XCTAssertEqual(confirmations, [2, 3])
        subscription.cancel()
    }

    func testOldBiasCannotOverwriteNewTapButNewDragStillApplies() {
        let service = CameraService(isCaptureSupported: false)
        let device = FakeFocusDevice()
        service.lastAppliedFocusRequestID = 1
        service.applyBias(1, forFocusRequestID: 1, to: device)
        service.lastAppliedFocusRequestID = 2
        service.applyTap(at: CGPoint(x: 0.8, y: 0.1), to: device)
        let count = device.lockCount
        service.applyBias(1.5, forFocusRequestID: 1, to: device)
        XCTAssertEqual(device.bias, 0)
        XCTAssertEqual(device.lockCount, count)
        let flushed = expectation(description: "stale bias publishes nothing")
        DispatchQueue.main.async { flushed.fulfill() }
        wait(for: [flushed], timeout: 2)
        XCTAssertEqual(service.focusExposureState, .initial)
        service.applyBias(-0.7, forFocusRequestID: 2, to: device)
        XCTAssertEqual(device.bias, -0.7)
    }

    func testFailedOrInvalidTapDoesNotResetBiasOrConfirmSuccess() {
        let service = CameraService(isCaptureSupported: false)
        let device = FakeFocusDevice()
        service.applyBias(1, forFocusRequestID: 0, to: device)
        var confirmations = 0
        let subscription = service.focusExposureTapResetPublisher.sink { _ in confirmations += 1 }
        service.applyTap(at: CGPoint(x: .nan, y: 0.5), to: device)
        device.lockFails = true
        service.applyTap(at: CGPoint(x: 0.2, y: 0.7), to: device)
        let flushed = expectation(description: "failure delivered")
        DispatchQueue.main.async { flushed.fulfill() }
        wait(for: [flushed], timeout: 2)
        XCTAssertEqual(device.bias, 1)
        XCTAssertEqual(service.focusExposureState.exposureBias, 1)
        XCTAssertEqual(confirmations, 0)
        subscription.cancel()
    }

    func testUnsupportedTapPublishesActualStateWithoutSuccessConfirmation() {
        for unsupportedPoints in [true, false] {
            let service = CameraService(isCaptureSupported: false)
            let device = FakeFocusDevice()
            device.focusMode = .locked
            device.exposureMode = .locked
            if unsupportedPoints {
                device.isFocusPointOfInterestSupported = false
                device.isExposurePointOfInterestSupported = false
            } else {
                device.supportedFocusModes = [.locked]
                device.supportedExposureModes = [.locked]
            }
            service.applyBias(1, forFocusRequestID: 0, to: device)
            var confirmations = 0
            let subscription = service.focusExposureTapResetPublisher.sink { _ in confirmations += 1 }
            service.applyTap(at: CGPoint(x: 0.2, y: 0.7), to: device)
            let flushed = expectation(description: "unsupported tap state delivered")
            DispatchQueue.main.async { flushed.fulfill() }
            wait(for: [flushed], timeout: 2)
            XCTAssertEqual(service.focusExposureState.exposureBias, 0)
            XCTAssertTrue(service.focusExposureState.isLocked)
            XCTAssertEqual(confirmations, 0)
            subscription.cancel()
        }
    }

    func testTapSetsPointsModesAndMonitoring() {
        let device = FakeFocusDevice()
        let outcome = CameraService.applyFocusAndExpose(at: CGPoint(x: 0.2, y: 0.7), to: device)
        XCTAssertEqual(outcome, CameraService.FocusExposureOutcome(focus: true, exposure: true))
        XCTAssertEqual(device.focusPointOfInterest, CGPoint(x: 0.2, y: 0.7))
        XCTAssertEqual(device.exposurePointOfInterest, CGPoint(x: 0.2, y: 0.7))
        XCTAssertEqual(device.focusMode, .autoFocus)
        XCTAssertEqual(device.exposureMode, .autoExpose)
        XCTAssertTrue(device.isSubjectAreaChangeMonitoringEnabled)
        XCTAssertEqual(device.lockCount, device.unlockCount)
    }

    func testPointOutsideTheRangeIsClamped() {
        let device = FakeFocusDevice()
        CameraService.applyFocusAndExpose(at: CGPoint(x: -1, y: 3), to: device)
        XCTAssertEqual(device.focusPointOfInterest, CGPoint(x: 0, y: 1))
    }

    func testNonFinitePointChangesNothing() {
        let device = FakeFocusDevice()
        let outcome = CameraService.applyFocusAndExpose(at: CGPoint(x: .nan, y: 0.5), to: device)
        XCTAssertEqual(outcome, CameraService.FocusExposureOutcome())
        XCTAssertEqual(device.lockCount, 0)
        XCTAssertEqual(device.focusMode, .continuousAutoFocus)
    }

    func testUnsupportedFocusPointIsSkippedAndExposureStillApplies() {
        let device = FakeFocusDevice()
        device.isFocusPointOfInterestSupported = false
        let outcome = CameraService.applyFocusAndExpose(at: CGPoint(x: 0.1, y: 0.1), to: device)
        XCTAssertEqual(outcome, CameraService.FocusExposureOutcome(focus: false, exposure: true))
        XCTAssertEqual(device.focusMode, .continuousAutoFocus)
        XCTAssertEqual(device.exposureMode, .autoExpose)
    }

    func testNothingSupportedTakesNoEffectAndKeepsMonitoringOff() {
        let device = FakeFocusDevice()
        device.isFocusPointOfInterestSupported = false
        device.isExposurePointOfInterestSupported = false
        let outcome = CameraService.applyFocusAndExpose(at: CGPoint(x: 0.1, y: 0.1), to: device)
        XCTAssertEqual(outcome?.tookEffect, false)
        XCTAssertFalse(device.isSubjectAreaChangeMonitoringEnabled)
    }

    func testFailedLockReturnsNilAndChangesNothing() {
        let device = FakeFocusDevice()
        device.lockFails = true
        XCTAssertNil(CameraService.applyFocusAndExpose(at: CGPoint(x: 0.1, y: 0.1), to: device))
        XCTAssertNil(CameraService.applyExposureBias(1, to: device))
        XCTAssertFalse(CameraService.applyContinuousAuto(to: device))
        XCTAssertEqual(device.focusMode, .continuousAutoFocus)
        XCTAssertEqual(device.bias, 0)
    }

    func testBiasIsClampedToTwoEV() {
        let device = FakeFocusDevice()
        XCTAssertEqual(CameraService.applyExposureBias(5, to: device), 2)
        XCTAssertEqual(device.bias, 2)
        XCTAssertEqual(CameraService.applyExposureBias(-5, to: device), -2)
        XCTAssertEqual(CameraService.applyExposureBias(0.7, to: device), 0.7)
        XCTAssertEqual(device.lockCount, device.unlockCount)
    }

    func testBiasIsClampedToANarrowerDeviceRange() {
        let device = FakeFocusDevice()
        device.minExposureTargetBias = -1
        device.maxExposureTargetBias = 1.5
        XCTAssertEqual(CameraService.applyExposureBias(2, to: device), 1.5)
        XCTAssertEqual(CameraService.applyExposureBias(-2, to: device), -1)
    }

    func testNonFiniteBiasIsRejected() {
        let device = FakeFocusDevice()
        XCTAssertNil(CameraService.applyExposureBias(.nan, to: device))
        XCTAssertEqual(device.lockCount, 0)
    }

    func testResetGoesBackToContinuousCentreBiasZero() {
        let device = FakeFocusDevice()
        CameraService.applyFocusAndExpose(at: CGPoint(x: 0.1, y: 0.9), to: device)
        CameraService.applyExposureBias(1.5, to: device)
        XCTAssertTrue(CameraService.applyContinuousAuto(to: device))
        XCTAssertEqual(device.focusMode, .continuousAutoFocus)
        XCTAssertEqual(device.exposureMode, .continuousAutoExposure)
        XCTAssertEqual(device.focusPointOfInterest, CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(device.bias, 0)
        XCTAssertFalse(device.isSubjectAreaChangeMonitoringEnabled)
    }

    func testResetSkipsUnsupportedModes() {
        let device = FakeFocusDevice()
        device.supportedFocusModes = [.locked]
        device.focusMode = .locked
        XCTAssertTrue(CameraService.applyContinuousAuto(to: device))
        XCTAssertEqual(device.focusMode, .locked)
        XCTAssertEqual(device.exposureMode, .continuousAutoExposure)
    }

    // MARK: Published bias range (#315 QA, read by the viewfinder UI)

    func testExposureBiasRangeStartsAtTwoEV() {
        XCTAssertEqual(CameraService(isCaptureSupported: false).exposureBiasRange, -2...2)
    }

    /// The range follows the device that was reset (a flip or lens change),
    /// narrowed to ±2 EV and to the device's own limits.
    func testExposureBiasRangeFollowsTheDeviceAfterAReset() {
        let service = CameraService(isCaptureSupported: false)
        let device = FakeFocusDevice()
        device.minExposureTargetBias = -1.5
        device.maxExposureTargetBias = 1
        service.resetFocusExposure(on: device)
        let published = expectation(description: "range published")
        DispatchQueue.main.async { published.fulfill() }
        wait(for: [published], timeout: 2)
        XCTAssertEqual(service.exposureBiasRange, -1.5...1)

        device.minExposureTargetBias = -8
        device.maxExposureTargetBias = 8
        service.resetFocusExposure(on: device)
        let republished = expectation(description: "range republished")
        DispatchQueue.main.async { republished.fulfill() }
        wait(for: [republished], timeout: 2)
        XCTAssertEqual(service.exposureBiasRange, -2...2)
    }

    /// Codex P2: a reset is announced even when the state was already at rest
    /// and so published nothing.
    func testResetIsAnnouncedEvenWhenTheStateDidNotChange() {
        let service = CameraService(isCaptureSupported: false)
        var resets = 0
        let cancellable = service.focusExposureResetPublisher.sink { _ in resets += 1 }
        service.resetFocusExposure(on: FakeFocusDevice())
        let flushed = expectation(description: "main queue flushed")
        DispatchQueue.main.async { flushed.fulfill() }
        wait(for: [flushed], timeout: 2)
        XCTAssertEqual(resets, 1)
        XCTAssertEqual(service.focusExposureState, .initial)
        cancellable.cancel()
    }

    /// TASK-82: the event says which focus request the device had taken.
    func testResetEventCarriesTheLastAppliedRequestID() {
        let service = CameraService(isCaptureSupported: false)
        var seen: [Int] = []
        let cancellable = service.focusExposureResetPublisher.sink { seen.append($0) }
        service.resetFocusExposure(on: FakeFocusDevice())
        service.lastAppliedFocusRequestID = 7
        service.resetFocusExposure(on: FakeFocusDevice())
        let flushed = expectation(description: "main queue flushed")
        DispatchQueue.main.async { flushed.fulfill() }
        wait(for: [flushed], timeout: 2)
        XCTAssertEqual(seen, [0, 7])
        cancellable.cancel()
    }

    /// TASK-82: without a camera nothing is queued and the id is 0.
    func testRequestsWithoutACameraGetNoID() {
        let service = CameraService(isCaptureSupported: false)
        XCTAssertEqual(service.focusAndExpose(at: CGPoint(x: 0.5, y: 0.5)), 0)
        XCTAssertEqual(service.lockFocusAndExposure(at: CGPoint(x: 0.5, y: 0.5)), 0)
    }

    /// 82.4: a device range wholly beyond 2 EV collapses to the nearest limit,
    /// never to a value outside it.
    func testBiasRangeBeyondTwoEVCollapsesToTheNearestLimit() {
        XCTAssertEqual(CameraService.exposureBiasRange(minimum: 3, maximum: 5), 2...2)
        XCTAssertEqual(CameraService.exposureBiasRange(minimum: -5, maximum: -3), -2 ... -2)
        XCTAssertEqual(CameraService.exposureBiasRange(minimum: -8, maximum: 8), -2...2)
        XCTAssertEqual(CameraService.exposureBiasRange(minimum: -1.5, maximum: 1), -1.5...1)
    }

    func testFailedResetIsNotAnnounced() {
        let service = CameraService(isCaptureSupported: false)
        var resets = 0
        let cancellable = service.focusExposureResetPublisher.sink { _ in resets += 1 }
        let device = FakeFocusDevice()
        device.lockFails = true
        service.resetFocusExposure(on: device)
        let flushed = expectation(description: "main queue flushed")
        DispatchQueue.main.async { flushed.fulfill() }
        wait(for: [flushed], timeout: 2)
        XCTAssertEqual(resets, 0)
        cancellable.cancel()
    }

    // MARK: Service level (no camera, so the calls are no-ops and must not crash)

    func testServiceCallsWithoutACameraDoNothing() {
        let service = CameraService(isCaptureSupported: false)
        service.focusAndExpose(at: CGPoint(x: 0.5, y: 0.5))
        service.lockFocusAndExposure(at: CGPoint(x: 0.5, y: 0.5))
        service.setExposureBias(1)
        service.resetToContinuousAuto()
        XCTAssertEqual(service.focusExposureState, .initial)
    }
}

final class FocusExposurePolicyTests: XCTestCase {

    func testSubjectChangeWhileLockedDoesNotReset() {
        XCTAssertFalse(FocusExposurePolicy.shouldReset(on: .subjectAreaChanged, isLocked: true))
    }

    func testSubjectChangeWhileUnlockedResets() {
        XCTAssertTrue(FocusExposurePolicy.shouldReset(on: .subjectAreaChanged, isLocked: false))
    }

    func testFlipPresetAndForegroundAlwaysReset() {
        for trigger in [FocusExposureTrigger.cameraFlipped, .zoomPresetSelected, .enteredForeground] {
            XCTAssertTrue(FocusExposurePolicy.shouldReset(on: trigger, isLocked: true), "\(trigger) locked")
            XCTAssertTrue(FocusExposurePolicy.shouldReset(on: trigger, isLocked: false), "\(trigger) unlocked")
        }
    }

    func testPinchAcrossLensesNeverResets() {
        XCTAssertFalse(FocusExposurePolicy.shouldReset(on: .pinchZoomed, isLocked: false))
        XCTAssertFalse(FocusExposurePolicy.shouldReset(on: .pinchZoomed, isLocked: true))
    }

    func testResetClearsBiasAndLockOnTheDevice() {
        let device = FakeFocusDevice()
        CameraService.applyExposureBias(1.5, to: device)
        CameraService.applyContinuousAuto(to: device)
        XCTAssertEqual(device.bias, 0)
    }
}


// MARK: - TASK-130: low-latency capture

/// An output whose support flags are scripted. Assigning `true` to a feature it
/// reports unsupported is what AVFoundation answers with an exception, so the
/// fake fails the test instead.
private final class FakePhotoOutput: PhotoOutputConfiguring {
    var isZeroShutterLagSupported = true
    var isZeroShutterLagEnabled = false
    var isResponsiveCaptureSupported = true
    var isResponsiveCaptureEnabled = false {
        didSet { XCTAssertTrue(isResponsiveCaptureSupported || !isResponsiveCaptureEnabled, "responsive set while unsupported") }
    }
    var isFastCapturePrioritizationSupported = true
    var isFastCapturePrioritizationEnabled = false {
        didSet { XCTAssertTrue(isFastCapturePrioritizationSupported || !isFastCapturePrioritizationEnabled, "fast capture set while unsupported") }
    }
    var maxPhotoQualityPrioritization: AVCapturePhotoOutput.QualityPrioritization = .speed
    var maxPhotoDimensions = CMVideoDimensions(width: 4032, height: 3024)
    var supportedFlashModes: [AVCaptureDevice.FlashMode] = [.off, .auto, .on]
    private(set) var preparedArrays: [[AVCapturePhotoSettings]] = []

    func setPreparedPhotoSettingsArray(_ preparedPhotoSettingsArray: [AVCapturePhotoSettings],
                                       completionHandler: ((Bool, (any Error)?) -> Void)?) {
        preparedArrays.append(preparedPhotoSettingsArray)
    }
}

/// A real `AVCapturePhotoOutput` that only records the prepared settings.
private final class RecordingPhotoOutput: AVCapturePhotoOutput {
    private(set) var preparedArrays: [[AVCapturePhotoSettings]] = []

    override func setPreparedPhotoSettingsArray(_ preparedPhotoSettingsArray: [AVCapturePhotoSettings],
                                                completionHandler: ((Bool, (any Error)?) -> Void)? = nil) {
        preparedArrays.append(preparedPhotoSettingsArray)
    }
}

final class CameraServiceLowLatencyCaptureTests: XCTestCase {

    /// 130.1: supported features are turned on, with quality capped at balanced.
    func testSupportedFeaturesAreEnabled() {
        let output = FakePhotoOutput()
        CameraService.configureLowLatencyCapture(on: output)
        XCTAssertTrue(output.isZeroShutterLagEnabled)
        XCTAssertTrue(output.isResponsiveCaptureEnabled)
        XCTAssertTrue(output.isFastCapturePrioritizationEnabled)
        XCTAssertEqual(output.maxPhotoQualityPrioritization, .balanced)
    }

    /// 130.1: nothing unsupported is set, and nothing crashes.
    func testUnsupportedFeaturesAreNotSet() {
        let output = FakePhotoOutput()
        output.isResponsiveCaptureSupported = false
        output.isFastCapturePrioritizationSupported = false
        CameraService.configureLowLatencyCapture(on: output)
        XCTAssertFalse(output.isResponsiveCaptureEnabled)
        XCTAssertFalse(output.isFastCapturePrioritizationEnabled)
        XCTAssertEqual(output.maxPhotoQualityPrioritization, .balanced)
    }

    /// Fast capture needs responsive capture; it is not enabled alone.
    func testFastCaptureIsNotEnabledWithoutResponsiveCapture() {
        let output = FakePhotoOutput()
        output.isResponsiveCaptureSupported = false
        CameraService.configureLowLatencyCapture(on: output)
        XCTAssertFalse(output.isFastCapturePrioritizationEnabled)
    }

    /// 130.1: a camera swap that drops support turns the features off again.
    func testFeaturesFollowSupportAfterACameraSwap() {
        let output = FakePhotoOutput()
        CameraService.configureLowLatencyCapture(on: output)
        output.isResponsiveCaptureSupported = false
        output.isFastCapturePrioritizationSupported = false
        CameraService.configureLowLatencyCapture(on: output)
        XCTAssertFalse(output.isResponsiveCaptureEnabled)
        XCTAssertFalse(output.isFastCapturePrioritizationEnabled)
    }

    /// Capture and preparation share one recipe: balanced, full size, flash only if supported.
    func testPhotoSettingsAreBalancedFullSizeAndHonourSupportedFlash() {
        let output = FakePhotoOutput()
        let settings = CameraService.makePhotoSettings(for: output, flashMode: .on)
        XCTAssertEqual(settings.photoQualityPrioritization, .balanced)
        XCTAssertEqual(settings.maxPhotoDimensions.width, 4032)
        XCTAssertEqual(settings.flashMode, .on)

        output.supportedFlashModes = [.off]
        XCTAssertEqual(CameraService.makePhotoSettings(for: output, flashMode: .on).flashMode, .off)
    }

    func testPreparePhotoSettingsSendsOneMatchingSettings() {
        let output = FakePhotoOutput()
        CameraService.preparePhotoSettings(on: output, flashMode: .auto)
        XCTAssertEqual(output.preparedArrays.count, 1)
        XCTAssertEqual(output.preparedArrays.first?.count, 1)
        XCTAssertEqual(output.preparedArrays.first?.first?.flashMode, .auto)
        XCTAssertEqual(output.preparedArrays.first?.first?.photoQualityPrioritization, .balanced)
    }

    /// 130.2: preparing is redone on request, with the mode last asked for, and
    /// does nothing before a camera is configured.
    func testPrepareCaptureRedoesPreparationOnceConfigured() {
        let output = RecordingPhotoOutput()
        let service = CameraService(isCaptureSupported: true, photoOutput: output)

        service.prepareCapture(flashMode: .auto)
        service.drainSessionQueueForTesting()
        XCTAssertTrue(output.preparedArrays.isEmpty, "no camera configured yet")

        service.markConfiguredForTesting()
        service.prepareCapture(flashMode: .off)
        service.drainSessionQueueForTesting()
        XCTAssertEqual(output.preparedArrays.count, 1, "130.2")

        service.prepareCapture(flashMode: .off)
        service.drainSessionQueueForTesting()
        XCTAssertEqual(output.preparedArrays.count, 2, "prepared again, as after a camera switch")
    }
}
