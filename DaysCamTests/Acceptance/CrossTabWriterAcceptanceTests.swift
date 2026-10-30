import XCTest
@testable import DaysCam

/// #70 M.1–M.4 (cross-tab edits never overwrite each other) through the
/// export page's editor (`StyleEditingCenter.makeStyleEditor`), since the
/// camera tests that covered them were deleted in #621. Written by qa for
/// PR #636; added by the developer with Lead's authorization.
@MainActor
final class CrossTabWriterAcceptanceTests: XCTestCase {
    private var directory = URL(fileURLWithPath: NSTemporaryDirectory())
    private var defaults = UserDefaults.standard
    private var suiteName = ""

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("QACrossTab-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "QACrossTab-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
        try super.tearDownWithError()
    }

    private func make(position: OverlayPlacement? = nil) throws -> (StyleEditingCenter, ProfileStore, ProfileStyleEditor, UUID) {
        let now = try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 8))
        let store = ProfileStore(directory: directory, calendar: DateFixture.taipei, now: { now }, defaults: defaults, scheduler: ProfileStore.immediateScheduler)
        var profile = CameraProfile(name: "小寶", startDate: DateFixture.components(2026, 1, 1))
        if let position { profile.position = position }
        let added = try store.add(profile)
        store.select(id: added.id)
        let center = StyleEditingCenter(profileStore: store, fontLibrary: FakeShellFontLibrary([.huninn: .available]),
                                        calendar: DateFixture.taipei,
                                        calculator: DayCountCalculator(calendar: DateFixture.taipei, now: { now }),
                                        notify: { _ in })
        let editor = try XCTUnwrap(center.makeStyleEditor(for: added.id))
        return (center, store, editor, added.id)
    }

    func test_M1_M2_editsAcrossTabsAllSurvive() throws {
        do {
            let (center, store, editor, id) = try make()
            editor.styleTabModel.selectFont(.huninn)
            editor.positionTabModel.selectAnchor(.bottomLeading)
            editor.formatTabModel.displaySettings.setShowDate(true)
            let stored = try XCTUnwrap(store.profiles.first { $0.id == id }); withExtendedLifetime(center) {}
            XCTAssertEqual(stored.style.fontID, .huninn, "M.1")
            XCTAssertEqual(stored.position, .anchor(.bottomLeading), "M.1")
            XCTAssertTrue(stored.showDate, "M.1")
        }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("profiles.json"))
        do {
            let (center, store, editor, id) = try make()
            editor.formatTabModel.displaySettings.setShowDate(true)
            editor.positionTabModel.selectAnchor(.bottomLeading)
            editor.styleTabModel.selectFont(.huninn)
            let stored = try XCTUnwrap(store.profiles.first { $0.id == id }); withExtendedLifetime(center) {}
            XCTAssertEqual(stored.style.fontID, .huninn, "M.2")
            XCTAssertEqual(stored.position, .anchor(.bottomLeading), "M.2")
            XCTAssertTrue(stored.showDate, "M.2")
        }
    }

    func test_M3_dragThenStyleKeepsThePosition() throws {
        let (center, store, editor, id) = try make(position: .anchor(.middleCenter))
        editor.dragAdapter.overlayDragEnded(center: CGPoint(x: 144, y: 192), viewfinderSize: CGSize(width: 288, height: 384))
        editor.styleTabModel.selectFont(.huninn)
        let stored = try XCTUnwrap(store.profiles.first { $0.id == id }); withExtendedLifetime(center) {}
        XCTAssertEqual(stored.position, .custom(x: 0.5, y: 0.5), "M.3")
        XCTAssertEqual(stored.style.fontID, .huninn, "M.3")
    }

    func test_M4_renameOutsideThenStyleKeepsTheName() throws {
        let (center, store, editor, id) = try make()
        var renamed = try XCTUnwrap(store.profiles.first { $0.id == id })
        renamed.name = "阿寶"
        try store.update(renamed)
        editor.styleTabModel.selectTextColor(.black)
        let stored = try XCTUnwrap(store.profiles.first { $0.id == id }); withExtendedLifetime(center) {}
        XCTAssertEqual(stored.name, "阿寶", "M.4")
        XCTAssertEqual(stored.style.textColor, .black, "M.4")
    }
}
