import AVFoundation
import Combine
import UIKit
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
}
