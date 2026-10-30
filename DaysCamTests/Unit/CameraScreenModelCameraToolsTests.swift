import XCTest
@testable import DaysCam

/// Covers the tools capsule's expand/collapse rules (issue #135, C.11); the
/// overlay panel they once also closed is gone from the camera (#621).
@MainActor
final class CameraScreenModelCameraToolsTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private let suiteName = "CameraScreenModelCameraToolsTests"

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func makeModel() throws -> CameraScreenModel {
        let store = ProfileStore(directory: directory, scheduler: ProfileStore.immediateScheduler)
        store.load()
        return CameraScreenModel(cameraService: CameraService(),
                                 profileStore: store,
                                 profileID: try XCTUnwrap(store.profiles.first?.id),
                                 captureSettingsStore: CaptureSettingsStore(defaults: defaults))
    }

    func testStartsCollapsed() throws {
        XCTAssertFalse(try makeModel().isCameraToolsExpanded)
    }

    func testToggleExpandsThenCollapses() throws {
        let model = try makeModel()
        model.toggleCameraTools()
        XCTAssertTrue(model.isCameraToolsExpanded)
        model.toggleCameraTools()
        XCTAssertFalse(model.isCameraToolsExpanded)
    }

    func testCyclingToolsKeepsCapsuleOpen() throws {
        let model = try makeModel()
        model.toggleCameraTools()
        model.cycleFlash()
        model.cycleTimer()
        model.toggleGrid()
        XCTAssertTrue(model.isCameraToolsExpanded)
    }

    /// A viewfinder tap closes the tools capsule.
    func testViewfinderTapCollapsesCapsule() throws {
        let model = try makeModel()
        model.toggleCameraTools()
        model.handleViewfinderTap()
        XCTAssertFalse(model.isCameraToolsExpanded)
    }

    /// TASK-72, 72.3: a viewfinder tap also closes the zoom capsule.
    func testViewfinderTapCollapsesZoomCapsule() throws {
        let model = try makeModel()
        model.zoomExpansion.expand()
        model.handleViewfinderTap()
        XCTAssertFalse(model.zoomExpansion.isExpanded)
    }

    func testOtherButtonsCollapseCapsuleAndStillAct() throws {
        let model = try makeModel()

        model.toggleCameraTools()
        model.switchCamera()
        XCTAssertFalse(model.isCameraToolsExpanded)

        model.toggleCameraTools()
        model.capturePhoto()
        XCTAssertFalse(model.isCameraToolsExpanded)
    }

    func testCollapseWhenAlreadyCollapsedIsNoOp() throws {
        let model = try makeModel()
        model.collapseCameraTools()
        XCTAssertFalse(model.isCameraToolsExpanded)
    }
}
