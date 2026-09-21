import AVFoundation
import Combine
import XCTest
@testable import DaysCam

/// Covers `CameraScreenModel`'s TASK-07 slice: how it turns `CameraService`'s
/// published state into what the viewfinder should show (placeholder,
/// shutter-disabled, transient status message) and that it forwards its
/// lifecycle/action calls to the service.
///
/// Like `CameraServiceTests`, every test stubs `CameraAuthorizing` and
/// `CaptureDeviceProviding` so nothing here touches real hardware or a real
/// permission prompt. A `CaptureDeviceProviding` that hands back a real
/// device is impossible on the simulator, so — matching `CameraServiceTests`'
/// own documented boundary — the fully-`.running` shutter-enabled state is a
/// B-level (device) acceptance item, not covered here.
@MainActor
final class CameraScreenModelTests: XCTestCase {
    private var cancellables: Set<AnyCancellable> = []

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    // MARK: - Doubles (mirrors CameraServiceTests' private doubles)

    private final class StubAuthorizer: CameraAuthorizing {
        var status: AVAuthorizationStatus
        init(status: AVAuthorizationStatus) { self.status = status }
        func authorizationStatus() -> AVAuthorizationStatus { status }
        func requestAccess(completion: @escaping (Bool) -> Void) {
            let granted = status == .authorized
            completion(granted)
        }
    }

    private final class EmptyDeviceProvider: CaptureDeviceProviding {
        private(set) var requestedFacings: [CameraFacing] = []
        func device(for facing: CameraFacing) -> AVCaptureDevice? {
            requestedFacings.append(facing)
            return nil
        }
    }

    // MARK: - Helpers

    private func makeModel(status: AVAuthorizationStatus = .notDetermined,
                           captureSupported: Bool = false) -> (CameraScreenModel, CameraService, EmptyDeviceProvider) {
        let authorizer = StubAuthorizer(status: status)
        let provider = EmptyDeviceProvider()
        let service = CameraService(authorizer: authorizer, deviceProvider: provider, isCaptureSupported: captureSupported)
        return (CameraScreenModel(cameraService: service), service, provider)
    }

    private func waitUntil(_ condition: @escaping () -> Bool, timeout: TimeInterval = 2) {
        if condition() { return }
        let exp = expectation(description: "condition became true")
        let deadline = Date().addingTimeInterval(timeout)
        func poll() {
            if condition() || Date() >= deadline {
                exp.fulfill()
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01, execute: poll)
        }
        poll()
        wait(for: [exp], timeout: timeout + 1)
        XCTAssertTrue(condition(), "condition never became true within \(timeout)s")
    }

    // MARK: - showsPlaceholder

    func testShowsPlaceholderWhenCaptureNotSupported() {
        let (model, _, _) = makeModel(captureSupported: false)
        XCTAssertTrue(model.showsPlaceholder)
    }

    func testDoesNotShowPlaceholderWhenCaptureSupported() {
        let (model, _, _) = makeModel(captureSupported: true)
        XCTAssertFalse(model.showsPlaceholder)
    }

    // MARK: - isShutterDisabled

    func testShutterDisabledWhenCaptureNotSupported() {
        let (model, _, _) = makeModel(captureSupported: false)
        XCTAssertTrue(model.isShutterDisabled)
    }

    func testShutterDisabledBeforeSessionStarts() {
        // captureSupported: true, but `onAppear` was never called, so status
        // is still `.idle` — the shutter must not be enabled before a live
        // picture is actually on screen.
        let (model, _, _) = makeModel(captureSupported: true)
        XCTAssertTrue(model.isShutterDisabled)
    }

    func testShutterDisabledWhenPermissionDenied() {
        let (model, service, _) = makeModel(status: .denied, captureSupported: true)
        model.onAppear()
        waitUntil { service.permission == .denied }
        XCTAssertTrue(model.isShutterDisabled)
    }

    func testShutterDisabledWhenPermissionRestricted() {
        let (model, service, _) = makeModel(status: .restricted, captureSupported: true)
        model.onAppear()
        waitUntil { service.permission == .restricted }
        XCTAssertTrue(model.isShutterDisabled)
    }

    // MARK: - statusMessage

    func testStatusMessageNilWhenIdle() {
        let (model, _, _) = makeModel(captureSupported: true)
        XCTAssertNil(model.statusMessage)
    }

    func testStatusMessageNilForSimulatorPlaceholder() {
        // The simulator gets its own placeholder + label; the generic
        // "相機暫時無法使用" message would be redundant on top of it.
        let (model, service, _) = makeModel(status: .authorized, captureSupported: false)
        model.onAppear()
        waitUntil { service.status == .unavailable(.simulator) }
        XCTAssertNil(model.statusMessage)
    }

    func testStatusMessageForNoCaptureDevice() {
        // `EmptyDeviceProvider` always hands back nil, so an authorized,
        // capture-supported session still fails to configure.
        let (model, service, _) = makeModel(status: .authorized, captureSupported: true)
        model.onAppear()
        waitUntil { service.status == .unavailable(.noCaptureDevice) }
        XCTAssertEqual(model.statusMessage, "相機暫時無法使用")
    }

    func testStatusMessageForInterruption() {
        let (model, service, _) = makeModel(captureSupported: true)
        NotificationCenter.default.post(name: AVCaptureSession.wasInterruptedNotification, object: service.session)
        waitUntil { service.status == .interrupted }
        XCTAssertEqual(model.statusMessage, "相機暫時無法使用")
    }

    // MARK: - Lifecycle forwarding

    func testOnAppearStartsTheService() {
        let (model, service, _) = makeModel(status: .authorized, captureSupported: false)
        XCTAssertEqual(service.permission, .notDetermined)
        model.onAppear()
        waitUntil { service.permission == .authorized }
    }

    func testOnDisappearStopsTheService() {
        let (model, service, _) = makeModel(status: .authorized, captureSupported: false)
        model.onAppear()
        waitUntil { service.status == .unavailable(.simulator) }
        model.onDisappear()
        waitUntil { service.status == .idle }
    }

    // MARK: - switchCamera forwarding

    func testSwitchCameraNoOpsWhenCaptureNotSupported() {
        let (model, _, provider) = makeModel(captureSupported: false)
        model.switchCamera()
        // The guard in `CameraService.switchCamera()` returns before ever
        // touching the session queue, so this is observable synchronously.
        XCTAssertTrue(provider.requestedFacings.isEmpty)
    }

    func testSwitchCameraForwardsToServiceWhenCaptureSupported() {
        let (model, _, provider) = makeModel(captureSupported: true)
        model.switchCamera()
        waitUntil { !provider.requestedFacings.isEmpty }
        XCTAssertEqual(provider.requestedFacings, [.front])
    }
}
