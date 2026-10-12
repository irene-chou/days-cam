import AVFoundation
import XCTest
@testable import DaysCam

/// TASK-130 wiring: the camera screen tells the camera which flash mode the
/// next photo will use, so the photo output can prepare for it.
@MainActor
final class CameraScreenModelPrepareCaptureTests: XCTestCase {

    private final class StubAuthorizer: CameraAuthorizing {
        func authorizationStatus() -> AVAuthorizationStatus { .notDetermined }
        func requestAccess(completion: @escaping (Bool) -> Void) { completion(false) }
    }

    private final class EmptyDeviceProvider: CaptureDeviceProviding {
        func device(for facing: CameraFacing) -> AVCaptureDevice? { nil }
    }

    private var directory = URL(fileURLWithPath: NSTemporaryDirectory())
    private var defaults = UserDefaults.standard
    private var suiteName = ""

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PrepareCaptureTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "PrepareCaptureTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
        try super.tearDownWithError()
    }

    private func makeModel(prepared: @escaping (FlashMode) -> Void) -> CameraScreenModel {
        let service = CameraService(authorizer: StubAuthorizer(), deviceProvider: EmptyDeviceProvider(),
                                    isCaptureSupported: false)
        let profiles = ProfileStore(directory: directory, calendar: DateFixture.taipei, now: { Date() }, defaults: defaults)
        profiles.load()
        return CameraScreenModel(cameraService: service,
                                 profileStore: profiles,
                                 captureSettingsStore: CaptureSettingsStore(defaults: defaults),
                                 capturedPhotoStore: CapturedPhotoStore(directory: directory.appendingPathComponent("photos", isDirectory: true)),
                                 prepareCapture: prepared)
    }

    /// The current mode is sent at once, then every change, with the new value.
    func testFlashModeChangesAreSentToTheCamera() {
        var modes: [FlashMode] = []
        let model = makeModel { modes.append($0) }
        XCTAssertEqual(modes, [.off], "initial mode")

        model.captureSettingsStore.cycleFlash()
        model.captureSettingsStore.cycleFlash()
        model.captureSettingsStore.cycleFlash()
        XCTAssertEqual(modes, [.off, .auto, .on, .off])
    }

    /// Appearing again sends the current mode, so the camera has it once the session starts.
    func testOnAppearSendsTheCurrentFlashMode() {
        var modes: [FlashMode] = []
        let model = makeModel { modes.append($0) }
        model.captureSettingsStore.cycleFlash()
        modes.removeAll()

        model.onAppear()
        XCTAssertEqual(modes, [.auto])
    }
}
