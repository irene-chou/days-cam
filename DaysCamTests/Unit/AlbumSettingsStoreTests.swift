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

    /// 79.5 replaces the limited-access branch of 64.4.
    func testGrantingLimitedAccessTurnsTheSwitchOn() {
        let library = FakeLibrary(readWriteStatus: .notDetermined, grants: .limited)
        let store = AlbumSettingsStore(defaults: defaults, library: library)
        let (result, _) = enable(store)
        XCTAssertEqual(result, .limited)
        XCTAssertTrue(store.savesToAlbum)
        XCTAssertTrue(store.isAlbumSavingEnabled)
        XCTAssertEqual(library.requestedLevels, [.readWrite])
    }

    /// 64.4: refusing leaves the switch off.
    func testRefusingLeavesTheSwitchOff() {
        let library = FakeLibrary(readWriteStatus: .notDetermined, grants: .denied)
        let store = AlbumSettingsStore(defaults: defaults, library: library)
        let (result, _) = enable(store)
        XCTAssertEqual(result, .denied)
        XCTAssertFalse(store.savesToAlbum)
    }

    /// Settled permissions never prompt again; limited access enables saving.
    func testSettledLimitedOrDeniedNeverPromptsAgain() {
        let cases: [(PHAuthorizationStatus, AlbumAccessResult)] = [
            (.limited, .limited), (.denied, .denied), (.restricted, .denied)
        ]
        for (status, expected) in cases {
            let library = FakeLibrary(readWriteStatus: status)
            let store = AlbumSettingsStore(defaults: defaults, library: library)
            let (result, _) = enable(store)
            XCTAssertEqual(result, expected, "\(status.rawValue)")
            XCTAssertEqual(store.savesToAlbum, status == .limited)
            XCTAssertEqual(store.isAlbumSavingEnabled, status == .limited)
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

    /// Denied and restricted access still trigger the 64.5 notice once.
    func testReconcileTurnsOffAndAsksForTheNoticeOnce() {
        let library = FakeLibrary(readWriteStatus: .authorized)
        let store = AlbumSettingsStore(defaults: defaults, library: library)
        _ = enable(store)
        library.readWriteStatus = .denied

        XCTAssertTrue(store.reconcile(), "first visit shows the notice")
        XCTAssertFalse(store.savesToAlbum)
        XCTAssertFalse(store.isAlbumSavingEnabled)
        XCTAssertFalse(store.reconcile(), "and only once")
        XCTAssertTrue(library.requestedLevels.isEmpty, "reconciling never prompts")
    }

    /// A privacy reset withdraws the persisted switch without requesting access again.
    func testNotDeterminedAfterPrivacyResetWithdrawsTheSwitchAndAlbumRoute() {
        let library = FakeLibrary(readWriteStatus: .authorized)
        let store = AlbumSettingsStore(defaults: defaults, library: library)
        _ = enable(store)
        store.rememberAlbum(identifier: "album-9")
        library.readWriteStatus = .notDetermined

        XCTAssertEqual(PhotoSaver.route(albumEnabled: store.isAlbumSavingEnabled) {
            library.readWriteStatus
        }, .recentsOnly, "undecided access cannot route to the album even before reconciliation")
        XCTAssertTrue(store.reconcile(), "the gallery shows the withdrawn-permission notice")
        XCTAssertFalse(store.savesToAlbum)
        XCTAssertFalse(store.isAlbumSavingEnabled)
        XCTAssertFalse(store.reconcile(), "the notice appears only once")
        XCTAssertEqual(PhotoSaver.route(albumEnabled: store.isAlbumSavingEnabled) {
            XCTFail("a disabled switch must not check readWrite access")
            return library.readWriteStatus
        }, .recentsOnly)
        XCTAssertTrue(library.requestedLevels.isEmpty)
        let relaunched = AlbumSettingsStore(defaults: defaults, library: library)
        XCTAssertFalse(relaunched.savesToAlbum, "withdrawal persists across a relaunch")
        XCTAssertEqual(relaunched.albumIdentifier, "album-9")
    }

    func testReconcileKeepsTheSwitchAndIdentifierAcrossLimitedAndFullAccess() {
        let library = FakeLibrary(readWriteStatus: .authorized)
        let store = AlbumSettingsStore(defaults: defaults, library: library)
        _ = enable(store)
        store.rememberAlbum(identifier: "album-9")
        for status: PHAuthorizationStatus in [.limited, .authorized, .limited] {
            library.readWriteStatus = status
            XCTAssertFalse(store.reconcile())
            XCTAssertTrue(store.savesToAlbum)
            XCTAssertTrue(store.isAlbumSavingEnabled)
            XCTAssertEqual(store.albumIdentifier, "album-9")
        }
        XCTAssertTrue(library.requestedLevels.isEmpty)
        let relaunched = AlbumSettingsStore(defaults: defaults, library: library)
        XCTAssertFalse(relaunched.reconcile())
        XCTAssertTrue(relaunched.savesToAlbum)
        XCTAssertEqual(relaunched.albumIdentifier, "album-9")
    }

    func testRestrictedAccessWithdrawsTheSwitchOnce() {
        let library = FakeLibrary(readWriteStatus: .limited)
        let store = AlbumSettingsStore(defaults: defaults, library: library)
        _ = enable(store)
        library.readWriteStatus = .restricted
        XCTAssertTrue(store.reconcile())
        XCTAssertFalse(store.isAlbumSavingEnabled)
        XCTAssertFalse(store.reconcile())
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
