import XCTest
@testable import DaysCam

/// Covers the tools capsule's expand/collapse rules (issue #135, C.11).
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

    private func makeModel() -> CameraScreenModel {
        let store = ProfileStore(directory: directory)
        store.load()
        return CameraScreenModel(cameraService: CameraService(),
                                 profileStore: store,
                                 captureSettingsStore: CaptureSettingsStore(defaults: defaults),
                                 capturedPhotoStore: CapturedPhotoStore(directory: directory.appendingPathComponent("photos", isDirectory: true)))
    }

    func testStartsCollapsed() {
        XCTAssertFalse(makeModel().isCameraToolsExpanded)
    }

    func testToggleExpandsThenCollapses() {
        let model = makeModel()
        model.toggleCameraTools()
        XCTAssertTrue(model.isCameraToolsExpanded)
        model.toggleCameraTools()
        XCTAssertFalse(model.isCameraToolsExpanded)
    }

    func testCyclingToolsKeepsCapsuleOpen() {
        let model = makeModel()
        model.toggleCameraTools()
        model.cycleFlash()
        model.cycleTimer()
        model.toggleGrid()
        XCTAssertTrue(model.isCameraToolsExpanded)
    }

    func testViewfinderTapOnlyCollapsesCapsuleAndLeavesOpenPanelAlone() {
        let model = makeModel()
        model.panelModel.open()
        model.toggleCameraTools()
        model.handleViewfinderTap()
        XCTAssertFalse(model.isCameraToolsExpanded)
        XCTAssertTrue(model.panelModel.isOpen)
        model.handleViewfinderTap()
        XCTAssertFalse(model.panelModel.isOpen)
    }

    func testOpeningPanelCollapsesCapsule() {
        let model = makeModel()
        model.toggleCameraTools()
        model.openOverlayPanel()
        XCTAssertFalse(model.isCameraToolsExpanded)
        XCTAssertTrue(model.panelModel.isOpen)
    }

    func testOtherButtonsCollapseCapsuleAndStillAct() {
        let model = makeModel()
        let ratioBefore = model.captureSettingsStore.captureAspectRatio

        model.toggleCameraTools()
        model.cycleAspectRatio()
        XCTAssertFalse(model.isCameraToolsExpanded)
        XCTAssertNotEqual(model.captureSettingsStore.captureAspectRatio, ratioBefore)

        model.toggleCameraTools()
        model.switchCamera()
        XCTAssertFalse(model.isCameraToolsExpanded)

        model.toggleCameraTools()
        model.capturePhoto()
        XCTAssertFalse(model.isCameraToolsExpanded)

        model.toggleCameraTools()
        model.presentProfileManagement()
        XCTAssertFalse(model.isCameraToolsExpanded)
        XCTAssertTrue(model.isProfileListPresented)

        model.toggleCameraTools()
        if let id = model.selectedProfileID {
            model.selectProfile(id: id)
        }
        XCTAssertFalse(model.isCameraToolsExpanded)
    }

    func testCollapseWhenAlreadyCollapsedIsNoOp() {
        let model = makeModel()
        model.collapseCameraTools()
        XCTAssertFalse(model.isCameraToolsExpanded)
    }
}
