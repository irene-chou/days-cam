import Photos
import UIKit
import XCTest
@testable import DaysCam

/// Covers the 「存到『DaysCam』相簿」 switch (issue #281, TASK-64 acceptance
/// 64.1, 64.4～64.7): persistence, the one place `.readWrite` is requested,
/// and the withdrawn-permission notice.
final class AlbumSettingsStoreTests: XCTestCase {

    // MARK: - Double

    private final class FakeLibrary: PhotoLibraryAccessing {
        var readWriteStatus: PHAuthorizationStatus
        var grants: PHAuthorizationStatus
        private(set) var checkedLevels: [PHAccessLevel] = []
        private(set) var requestedLevels: [PHAccessLevel] = []

        init(readWriteStatus: PHAuthorizationStatus = .notDetermined, grants: PHAuthorizationStatus = .authorized) {
            self.readWriteStatus = readWriteStatus
            self.grants = grants
        }

        func authorizationStatus(for level: PHAccessLevel) -> PHAuthorizationStatus {
            checkedLevels.append(level)
            return level == .readWrite ? readWriteStatus : .notDetermined
        }

        func requestAuthorization(for level: PHAccessLevel, handler: @escaping (PHAuthorizationStatus) -> Void) {
            requestedLevels.append(level)
            readWriteStatus = grants
            let granted = grants
            // The system answers on a background queue.
            DispatchQueue.global().async { handler(granted) }
        }

        func performChanges(_ changes: @escaping () -> String?,
                            completion: @escaping (Bool, String?, Error?) -> Void) {
            XCTFail("the store never writes")
        }

        func saveToAlbum(_ image: UIImage, albumIdentifier: String?, albumTitle: String,
                         completion: @escaping (AlbumWriteResult) -> Void) {
            XCTFail("the store never writes")
        }
    }

    // MARK: - Helpers

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "AlbumSettingsStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func enable(_ store: AlbumSettingsStore) -> (AlbumAccessResult?, Bool) {
        let done = expectation(description: "request completes")
        var result: AlbumAccessResult?
        var wasOnMain = false
        store.requestEnabling {
            result = $0
            wasOnMain = Thread.isMainThread
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
        return (result, wasOnMain)
    }

    // MARK: - Default and persistence (64.1, 64.6)

    func testOffByDefault() {
        let store = AlbumSettingsStore(defaults: defaults, library: FakeLibrary())
        XCTAssertFalse(store.savesToAlbum)
        XCTAssertFalse(store.isAlbumSavingEnabled)
        XCTAssertNil(store.albumIdentifier)
    }

    /// Creating the store (as at launch) never touches the photo library.
    func testCreatingTheStoreNeverPrompts() {
        let library = FakeLibrary()
        _ = AlbumSettingsStore(defaults: defaults, library: library)
        XCTAssertTrue(library.checkedLevels.isEmpty)
        XCTAssertTrue(library.requestedLevels.isEmpty)
    }

    /// 64.6: the switch and the album id survive a relaunch.
    func testSwitchAndAlbumSurviveARelaunch() {
        let store = AlbumSettingsStore(defaults: defaults, library: FakeLibrary(readWriteStatus: .authorized))
        _ = enable(store)
        store.rememberAlbum(identifier: "album-9")

        let relaunched = AlbumSettingsStore(defaults: defaults, library: FakeLibrary())
        XCTAssertTrue(relaunched.savesToAlbum)
        XCTAssertTrue(relaunched.isAlbumSavingEnabled)
        XCTAssertEqual(relaunched.albumIdentifier, "album-9")
    }

    func testDisablePersists() {
        let store = AlbumSettingsStore(defaults: defaults, library: FakeLibrary(readWriteStatus: .authorized))
        _ = enable(store)
        store.disable()
        XCTAssertFalse(store.savesToAlbum)
        XCTAssertFalse(AlbumSettingsStore(defaults: defaults, library: FakeLibrary()).savesToAlbum)
    }

    // MARK: - Enabling (64.2, 64.4)

    func testAlreadyFullAccessTurnsOnWithoutPrompting() {
        let library = FakeLibrary(readWriteStatus: .authorized)
        let store = AlbumSettingsStore(defaults: defaults, library: library)
        let (result, onMain) = enable(store)
        XCTAssertEqual(result, .full)
        XCTAssertTrue(onMain)
        XCTAssertTrue(store.savesToAlbum)
        XCTAssertTrue(library.requestedLevels.isEmpty)
    }

    func testUndecidedAsksForReadWriteOnceAndTurnsOnWhenGranted() {
        let library = FakeLibrary(readWriteStatus: .notDetermined, grants: .authorized)
        let store = AlbumSettingsStore(defaults: defaults, library: library)
        let (result, onMain) = enable(store)
        XCTAssertEqual(result, .full)
        XCTAssertTrue(onMain, "answered on the main queue even though the system calls back elsewhere")
        XCTAssertTrue(store.savesToAlbum)
        XCTAssertEqual(library.requestedLevels, [.readWrite])
    }

    /// 64.4: choosing limited access leaves the switch off.
    func testGrantingOnlyLimitedAccessLeavesTheSwitchOff() {
        let library = FakeLibrary(readWriteStatus: .notDetermined, grants: .limited)
        let store = AlbumSettingsStore(defaults: defaults, library: library)
        let (result, _) = enable(store)
        XCTAssertEqual(result, .limited)
        XCTAssertFalse(store.savesToAlbum)
        XCTAssertFalse(store.isAlbumSavingEnabled)
    }

    /// 64.4: refusing leaves the switch off.
    func testRefusingLeavesTheSwitchOff() {
        let library = FakeLibrary(readWriteStatus: .notDetermined, grants: .denied)
        let store = AlbumSettingsStore(defaults: defaults, library: library)
        let (result, _) = enable(store)
        XCTAssertEqual(result, .denied)
        XCTAssertFalse(store.savesToAlbum)
    }

    /// Already settled to something short of full: no prompt (the system
    /// would suppress it anyway), the switch stays off.
    func testSettledLimitedOrDeniedNeverPromptsAgain() {
        let cases: [(PHAuthorizationStatus, AlbumAccessResult)] = [
            (.limited, .limited), (.denied, .denied), (.restricted, .denied)
        ]
        for (status, expected) in cases {
            let library = FakeLibrary(readWriteStatus: status)
            let store = AlbumSettingsStore(defaults: defaults, library: library)
            let (result, _) = enable(store)
            XCTAssertEqual(result, expected, "\(status.rawValue)")
            XCTAssertFalse(store.savesToAlbum)
            XCTAssertTrue(library.requestedLevels.isEmpty)
        }
    }

    // MARK: - Withdrawn permission (64.5)

    func testReconcileKeepsTheSwitchWhileFullAccessLasts() {
        let library = FakeLibrary(readWriteStatus: .authorized)
        let store = AlbumSettingsStore(defaults: defaults, library: library)
        _ = enable(store)
        XCTAssertFalse(store.reconcile())
        XCTAssertTrue(store.savesToAlbum)
    }

    /// 64.5: reduced to limited in Settings — the switch goes off and the
    /// notice is asked for exactly once.
    func testReconcileTurnsOffAndAsksForTheNoticeOnce() {
        let library = FakeLibrary(readWriteStatus: .authorized)
        let store = AlbumSettingsStore(defaults: defaults, library: library)
        _ = enable(store)
        library.readWriteStatus = .limited

        XCTAssertTrue(store.reconcile(), "first visit shows the notice")
        XCTAssertFalse(store.savesToAlbum)
        XCTAssertFalse(store.isAlbumSavingEnabled)
        XCTAssertFalse(store.reconcile(), "and only once")
        XCTAssertTrue(library.requestedLevels.isEmpty, "reconciling never prompts")
    }

    func testReconcileWithTheSwitchOffDoesNothing() {
        let library = FakeLibrary(readWriteStatus: .denied)
        let store = AlbumSettingsStore(defaults: defaults, library: library)
        XCTAssertFalse(store.reconcile())
        XCTAssertTrue(library.checkedLevels.isEmpty)
    }

    func testAccessResultMapping() {
        XCTAssertEqual(AlbumSettingsStore.accessResult(for: .authorized), .full)
        XCTAssertEqual(AlbumSettingsStore.accessResult(for: .limited), .limited)
        XCTAssertEqual(AlbumSettingsStore.accessResult(for: .denied), .denied)
        XCTAssertEqual(AlbumSettingsStore.accessResult(for: .restricted), .denied)
        XCTAssertEqual(AlbumSettingsStore.accessResult(for: .notDetermined), .denied)
    }
}
