import Photos
import UIKit
import XCTest
@testable import DaysCam

/// Issue #329 / PR #330 independent QA (TASK-79, 79.1／79.4／79.5): limited
/// access turns the album switch on and takes the album route; only denied or
/// restricted withdraws it; a failed album transaction (3311) still keeps the
/// photo; `.readWrite` is requested only by the switch, never by saving.
final class AlbumLimitedAccessAcceptanceTests: XCTestCase {
    private final class StubLibrary: PhotoLibraryAccessing {
        var addOnlyStatus: PHAuthorizationStatus = .authorized
        var readWriteStatus: PHAuthorizationStatus
        var grants: PHAuthorizationStatus
        var albumError: Error?
        private(set) var requestedLevels: [PHAccessLevel] = []
        private(set) var checkedLevels: [PHAccessLevel] = []
        private(set) var recentsWrites = 0
        private(set) var albumWrites = 0

        init(readWriteStatus: PHAuthorizationStatus, grants: PHAuthorizationStatus = .authorized) {
            self.readWriteStatus = readWriteStatus
            self.grants = grants
        }

        func authorizationStatus(for level: PHAccessLevel) -> PHAuthorizationStatus {
            checkedLevels.append(level)
            return level == .readWrite ? readWriteStatus : addOnlyStatus
        }

        func requestAuthorization(for level: PHAccessLevel, handler: @escaping (PHAuthorizationStatus) -> Void) {
            requestedLevels.append(level)
            if level == .readWrite { readWriteStatus = grants } else { addOnlyStatus = grants }
            handler(grants)
        }

        func performChanges(_ changes: @escaping () -> String?,
                            completion: @escaping (Bool, String?, Error?) -> Void) {
            recentsWrites += 1
            completion(true, "recents-asset", nil)
        }

        func saveToAlbum(_ image: UIImage, albumIdentifier: String?, albumTitle: String,
                         completion: @escaping (AlbumWriteResult) -> Void) {
            albumWrites += 1
            if let albumError {
                completion(AlbumWriteResult(succeeded: false, assetIdentifier: nil,
                                            albumIdentifier: nil, error: albumError))
            } else {
                completion(AlbumWriteResult(succeeded: true, assetIdentifier: "album-asset",
                                            albumIdentifier: "album-new", error: nil))
            }
        }
    }

    private var defaults: UserDefaults!
    private var suiteName: String!
    private let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { _ in }

    override func setUp() {
        super.setUp()
        suiteName = "qa-329-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func enable(_ store: AlbumSettingsStore) -> AlbumAccessResult {
        let done = expectation(description: "enable")
        var result: AlbumAccessResult = .denied
        var calls = 0
        store.requestEnabling { result = $0; calls += 1; done.fulfill() }
        wait(for: [done], timeout: 2)
        XCTAssertEqual(calls, 1)
        return result
    }

    private func save(_ saver: PhotoSaver) throws -> Result<String, PhotoSaveError> {
        let done = expectation(description: "save")
        var result: Result<String, PhotoSaveError>?
        var calls = 0
        saver.saveReturningIdentifier(image) { result = $0; calls += 1; done.fulfill() }
        wait(for: [done], timeout: 2)
        XCTAssertEqual(calls, 1)
        return try XCTUnwrap(result)
    }

    // MARK: - 79.1 / 79.5 switch

    /// Fresh install: the prompt ends in limited -> switch persists on, only
    /// `.readWrite` was requested, and a relaunch still reads it as on.
    func testPromptEndingInLimitedTurnsSwitchOnAndPersists() {
        let library = StubLibrary(readWriteStatus: .notDetermined, grants: .limited)
        let store = AlbumSettingsStore(defaults: defaults, library: library)
        XCTAssertEqual(enable(store), .limited)
        XCTAssertEqual(library.requestedLevels, [.readWrite])
        XCTAssertTrue(AlbumSettingsStore(defaults: defaults, library: library).isAlbumSavingEnabled)
    }

    /// Already settled limited: the switch turns on without any prompt.
    func testAlreadyLimitedTurnsOnWithoutPrompt() {
        let library = StubLibrary(readWriteStatus: .limited)
        let store = AlbumSettingsStore(defaults: defaults, library: library)
        XCTAssertEqual(enable(store), .limited)
        XCTAssertTrue(store.savesToAlbum)
        XCTAssertTrue(library.requestedLevels.isEmpty)
    }

    /// Authorized behaves as before: `.full`, on.
    func testAuthorizedStillFullAndOn() {
        let library = StubLibrary(readWriteStatus: .authorized)
        let store = AlbumSettingsStore(defaults: defaults, library: library)
        XCTAssertEqual(enable(store), .full)
        XCTAssertTrue(store.savesToAlbum)
    }

    /// 79.4: denied / restricted / refused prompt never turn the switch on.
    func testDeniedRestrictedAndRefusedPromptKeepSwitchOff() {
        for status: PHAuthorizationStatus in [.denied, .restricted] {
            let store = AlbumSettingsStore(defaults: defaults,
                                           library: StubLibrary(readWriteStatus: status))
            XCTAssertEqual(enable(store), .denied)
            XCTAssertFalse(store.savesToAlbum)
        }
        let refused = AlbumSettingsStore(defaults: defaults,
                                         library: StubLibrary(readWriteStatus: .notDetermined, grants: .denied))
        XCTAssertEqual(enable(refused), .denied)
        XCTAssertFalse(refused.savesToAlbum)
    }

    /// Reconcile matrix with the switch on: only denied / restricted withdraw
    /// (once); limited, authorized and the transient notDetermined do not.
    func testReconcileWithdrawsOnlyForDeniedOrRestricted() {
        let cases: [(PHAuthorizationStatus, Bool)] = [
            (.authorized, false), (.limited, false), (.denied, true), (.restricted, true)
        ]
        for (status, withdraws) in cases {
            defaults.removePersistentDomain(forName: suiteName)
            let library = StubLibrary(readWriteStatus: .authorized)
            let store = AlbumSettingsStore(defaults: defaults, library: library)
            _ = enable(store)
            library.readWriteStatus = status
            XCTAssertEqual(store.reconcile(), withdraws, "\(status.rawValue)")
            XCTAssertEqual(store.savesToAlbum, !withdraws, "\(status.rawValue)")
            XCTAssertFalse(store.reconcile(), "notice only once")
        }
    }

    // MARK: - 79.5 route and saving

    /// Real store + saver sharing one defaults: limited -> album write, id remembered,
    /// recents path untouched, `.readWrite` never requested by saving.
    func testLimitedSaveGoesThroughAlbumAndRemembersIt() throws {
        let library = StubLibrary(readWriteStatus: .limited)
        let store = AlbumSettingsStore(defaults: defaults, library: library)
        _ = enable(store)
        let result = try save(PhotoSaver(library: library, albumSettings: store))
        XCTAssertEqual(try result.get(), "album-asset")
        XCTAssertEqual(library.albumWrites, 1)
        XCTAssertEqual(library.recentsWrites, 0)
        XCTAssertEqual(store.albumIdentifier, "album-new")
        XCTAssertTrue(library.requestedLevels.isEmpty)
    }

    /// 3311 under limited: photo lands in recents exactly once, success carries
    /// the asset id, remembered album kept, no prompt.
    func testLimited3311KeepsPhotoAndRememberedAlbum() throws {
        let library = StubLibrary(readWriteStatus: .limited)
        library.albumError = NSError(domain: "PHPhotosErrorDomain", code: 3311)
        let store = AlbumSettingsStore(defaults: defaults, library: library)
        _ = enable(store)
        store.rememberAlbum(identifier: "keep-me")
        let result = try save(PhotoSaver(library: library, albumSettings: store))
        XCTAssertEqual(try result.get(), "recents-asset")
        XCTAssertEqual(library.albumWrites, 1)
        XCTAssertEqual(library.recentsWrites, 1)
        XCTAssertEqual(store.albumIdentifier, "keep-me")
        XCTAssertTrue(store.isAlbumSavingEnabled, "an album failure is not a revoke")
        XCTAssertTrue(library.requestedLevels.isEmpty)
    }

    /// Denied after the switch was on (before reconcile ran): saver falls back
    /// to recents silently, no album attempt, no readWrite prompt.
    func testWithdrawnAccessSavesToRecentsOnly() throws {
        for status: PHAuthorizationStatus in [.denied, .restricted, .notDetermined] {
            defaults.removePersistentDomain(forName: suiteName)
            let library = StubLibrary(readWriteStatus: .authorized)
            let store = AlbumSettingsStore(defaults: defaults, library: library)
            _ = enable(store)
            library.readWriteStatus = status
            let result = try save(PhotoSaver(library: library, albumSettings: store))
            XCTAssertEqual(try result.get(), "recents-asset", "\(status.rawValue)")
            XCTAssertEqual(library.albumWrites, 0)
            XCTAssertEqual(library.recentsWrites, 1)
            XCTAssertTrue(library.requestedLevels.isEmpty)
        }
    }

    /// #281: with the switch off, saving even under limited readWrite never
    /// asks about or requests `.readWrite`; a fresh addOnly prompt is addOnly.
    func testSwitchOffNeverTouchesReadWrite() throws {
        let library = StubLibrary(readWriteStatus: .limited, grants: .authorized)
        library.addOnlyStatus = .notDetermined
        let store = AlbumSettingsStore(defaults: defaults, library: library)
        XCTAssertFalse(store.isAlbumSavingEnabled)
        let result = try save(PhotoSaver(library: library, albumSettings: store))
        XCTAssertEqual(try result.get(), "recents-asset")
        XCTAssertEqual(library.requestedLevels, [.addOnly])
        XCTAssertFalse(library.checkedLevels.contains(.readWrite))
        XCTAssertEqual(library.albumWrites, 0)
    }

    /// Route function: only the switch plus full/limited reaches the album,
    /// and the readWrite status is not even read when the switch is off.
    func testRouteMatrix() {
        var asked = false
        XCTAssertEqual(PhotoSaver.route(albumEnabled: false) { asked = true; return .limited }, .recentsOnly)
        XCTAssertFalse(asked)
        let cases: [(PHAuthorizationStatus, PhotoSaveRoute)] = [
            (.authorized, .recentsAndAlbum), (.limited, .recentsAndAlbum),
            (.denied, .recentsOnly), (.restricted, .recentsOnly), (.notDetermined, .recentsOnly)
        ]
        for (status, expected) in cases {
            XCTAssertEqual(PhotoSaver.route(albumEnabled: true) { status }, expected, "\(status.rawValue)")
        }
    }
}
