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

    // MARK: - Initial state

    func testStartsIdleOnTheBackCameraWithAnIdleSession() {
        let (service, _, _) = makeService(status: .notDetermined)

        XCTAssertEqual(service.status, .idle)
        XCTAssertEqual(service.permission, .notDetermined)
        XCTAssertEqual(service.facing, .back)
        XCTAssertFalse(service.session.isRunning)
    }

    func testSessionIsExposedSoTheViewCanBuildItsOwnPreviewLayer() {
        let (service, _, _) = makeService(status: .authorized)

        // The view layer owns the `AVCaptureVideoPreviewLayer`; the service
        // only hands out the session it should be attached to.
        XCTAssertTrue(service.session === service.session)
    }

    // MARK: - Permission state machine (PRD §2.3)

    func testAuthorizedStartPublishesAuthorized() {
        let (service, authorizer, _) = makeService(status: .authorized)

        service.start()

        expect(service, permission: .authorized)
        XCTAssertEqual(authorizer.requestCount, 0, "already-granted access must not prompt again")
    }

    func testNotDeterminedStartPromptsOnceAndPublishesTheAnswer() {
        let (service, authorizer, _) = makeService(status: .notDetermined, grants: true)

        service.start()

        expect(service, permission: .authorized)
        XCTAssertEqual(authorizer.requestCount, 1)
    }

    func testDeclinedPromptPublishesDeniedAndAsksForTheGuidanceScreen() {
        let (service, _, _) = makeService(status: .notDetermined, grants: false)

        service.start()

        expect(service, permission: .denied)
        XCTAssertTrue(service.permission.needsGuidance)
    }

    func testRestrictedAsksForTheGuidanceScreenToo() {
        let (service, _, _) = makeService(status: .restricted)

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
        let (service, authorizer, _) = makeService(status: .denied)
        service.start()
        expect(service, permission: .denied)

        authorizer.status = .authorized
        service.refreshPermission()

        expect(service, permission: .authorized)
    }

    func testReturningToTheForegroundRechecksPermission() {
        let (service, authorizer, _) = makeService(status: .denied)
        service.start()
        expect(service, permission: .denied)

        authorizer.status = .authorized
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification,
                                        object: nil)

        expect(service, permission: .authorized)
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

        let settled = expectation(description: "switch attempt finishes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { settled.fulfill() }
        wait(for: [settled], timeout: 2)

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

    func testCapturePhotoDeliversItsAnswerOnTheMainQueue() {
        let (service, _, _) = makeService(status: .authorized, captureSupported: false)
        service.start()

        let done = expectation(description: "capture completes")
        var wasOnMain = false
        service.capturePhoto { _ in
            wasOnMain = Thread.isMainThread
            done.fulfill()
        }
        wait(for: [done], timeout: 2)

        XCTAssertTrue(wasOnMain)
    }
}
