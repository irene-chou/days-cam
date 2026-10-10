import CoreMedia
import Photos
import UIKit
import XCTest
@testable import DaysCam

/// Covers the `PhotoSaver` half of TASK-10: the add-only permission branches
/// (PRD §2.3) and the guarantees the shutter relies on.
///
/// `PHPhotoLibrary` cannot be driven from a unit test — it prompts and writes
/// to the real library — so every test here stubs `PhotoLibraryAccessing`.
/// Whether a photo really lands in 「最近項目」 is a device check (10.5, 10.23).
final class PhotoSaverTests: XCTestCase {

    // MARK: - Double

    private final class StubLibrary: PhotoLibraryAccessing {
        var status: PHAuthorizationStatus
        /// What the prompt returns; only consulted from `.notDetermined`.
        var grants: PHAuthorizationStatus
        /// Non-nil makes the write fail with this error.
        var writeError: Error?
        /// The identifier a successful write reports back (TASK-28, FR-15.1).
        var identifierToReturn = "stub-asset-identifier"

        /// `.readWrite`'s status, separate from the `.addOnly` one in `status`
        /// (issue #281).
        var readWriteStatus: PHAuthorizationStatus = .notDetermined
        /// Non-nil makes `saveToAlbum` fail with this error.
        var albumWriteError: Error?
        /// The album id a successful `saveToAlbum` reports back.
        var albumIdentifierToReturn = "album-1"

        private(set) var requestedLevels: [PHAccessLevel] = []
        private(set) var checkedLevels: [PHAccessLevel] = []
        private(set) var writeCount = 0
        private(set) var albumWrites: [(albumIdentifier: String?, albumTitle: String)] = []

        init(status: PHAuthorizationStatus, grants: PHAuthorizationStatus = .authorized) {
            self.status = status
            self.grants = grants
        }

        func authorizationStatus(for level: PHAccessLevel) -> PHAuthorizationStatus {
            checkedLevels.append(level)
            return level == .readWrite ? readWriteStatus : status
        }

        func requestAuthorization(for level: PHAccessLevel, handler: @escaping (PHAuthorizationStatus) -> Void) {
            requestedLevels.append(level)
            status = grants
            handler(grants)
        }

        func performChanges(_ changes: @escaping () -> String?,
                           completion: @escaping (Bool, String?, Error?) -> Void) {
            writeCount += 1
            // The real library runs `changes` to collect change requests; it
            // is not run here because `PHAssetChangeRequest` needs a real
            // library. The identifier it would have produced is supplied
            // directly instead.
            if let writeError {
                completion(false, nil, writeError)
            } else {
                completion(true, identifierToReturn, nil)
            }
        }

        func saveToAlbum(_ image: UIImage,
                         albumIdentifier: String?,
                         albumTitle: String,
                         completion: @escaping (AlbumWriteResult) -> Void) {
            albumWrites.append((albumIdentifier, albumTitle))
            if let albumWriteError {
                completion(AlbumWriteResult(succeeded: false, assetIdentifier: nil,
                                            albumIdentifier: nil, error: albumWriteError))
            } else {
                completion(AlbumWriteResult(succeeded: true, assetIdentifier: identifierToReturn,
                                            albumIdentifier: albumIdentifierToReturn, error: nil))
            }
        }
    }

    /// The album switch, in memory.
    private final class FakeAlbumSettings: AlbumSaveSettings {
        var isAlbumSavingEnabled: Bool
        private(set) var albumIdentifier: String?
        private(set) var rememberCount = 0

        init(enabled: Bool = false, albumIdentifier: String? = nil) {
            isAlbumSavingEnabled = enabled
            self.albumIdentifier = albumIdentifier
        }

        func rememberAlbum(identifier: String) {
            albumIdentifier = identifier
            rememberCount += 1
        }
    }

    // MARK: - Helpers

    private let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
        UIColor.white.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
    }

    @discardableResult
    private func save(with library: StubLibrary,
                      file: StaticString = #filePath,
                      line: UInt = #line) throws -> Result<Void, PhotoSaveError> {
        let saver = PhotoSaver(library: library, albumSettings: FakeAlbumSettings())
        let done = expectation(description: "save completes")
        var result: Result<Void, PhotoSaveError>?
        saver.save(image) {
            result = $0
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
        return try XCTUnwrap(result, "completion never ran", file: file, line: line)
    }

    private func assertFailure(_ result: Result<Void, PhotoSaveError>,
                               _ expected: PhotoSaveError,
                               file: StaticString = #filePath,
                               line: UInt = #line) {
        switch result {
        case .failure(let error):
            XCTAssertEqual(error, expected, file: file, line: line)
        case .success:
            XCTFail("expected \(expected), got success", file: file, line: line)
        }
    }

    private func assertSuccess(_ result: Result<Void, PhotoSaveError>,
                               file: StaticString = #filePath,
                               line: UInt = #line) {
        if case .failure(let error) = result {
            XCTFail("expected success, got \(error)", file: file, line: line)
        }
    }

    // MARK: - Permission branches (PRD §2.3)

    func testAlreadyAuthorizedSavesWithoutPromptingAgain() throws {
        let library = StubLibrary(status: .authorized)

        assertSuccess(try save(with: library))

        XCTAssertEqual(library.writeCount, 1)
        XCTAssertTrue(library.requestedLevels.isEmpty, "granted access must not prompt again")
    }

    /// PRD §2.2 step 4: the prompt belongs to the first save, not to launch.
    func testNotDeterminedPromptsOnceAndThenSaves() throws {
        let library = StubLibrary(status: .notDetermined, grants: .authorized)

        assertSuccess(try save(with: library))

        XCTAssertEqual(library.requestedLevels.map(\.description), [PHAccessLevel.addOnly.description])
        XCTAssertEqual(library.writeCount, 1)
    }

    func testDeclinedPromptFailsAndWritesNothing() throws {
        let library = StubLibrary(status: .notDetermined, grants: .denied)

        assertFailure(try save(with: library), .permissionDenied)

        XCTAssertEqual(library.requestedLevels.map(\.description), [PHAccessLevel.addOnly.description])
        XCTAssertEqual(library.writeCount, 0, "the photo must not be written without permission")
    }

    func testDeniedFailsWithoutTouchingTheLibrary() throws {
        let library = StubLibrary(status: .denied)

        assertFailure(try save(with: library), .permissionDenied)

        XCTAssertEqual(library.writeCount, 0)
        XCTAssertTrue(library.requestedLevels.isEmpty, "a settled refusal must not be re-prompted")
    }

    /// Lead's ruling: `.restricted` shares `.denied`'s message. PRD §2.3's
    /// photo-library row named only 被拒, which was an omission — its camera
    /// row already covers 被拒／受限.
    func testRestrictedIsTreatedLikeDenied() throws {
        let library = StubLibrary(status: .restricted)

        assertFailure(try save(with: library), .permissionDenied)

        XCTAssertEqual(library.writeCount, 0)
    }

    /// Defensive only: `.limited` belongs to `.readWrite`, so an `.addOnly`
    /// request is not expected to return it. QA cannot reproduce this on a
    /// device — it is here so the branch is defined rather than falling
    /// through to a refusal if that ever changes.
    func testLimitedIsTreatedAsPermissionToAdd() throws {
        let library = StubLibrary(status: .limited)

        assertSuccess(try save(with: library))

        XCTAssertEqual(library.writeCount, 1)
    }

    // MARK: - Access level (10.1)

    func testOnlyEverAsksForAddOnlyAccess() throws {
        let library = StubLibrary(status: .notDetermined, grants: .authorized)

        try save(with: library)

        XCTAssertEqual(library.checkedLevels.map(\.description), [PHAccessLevel.addOnly.description],
                       "only add-only access may be checked")
        XCTAssertEqual(library.requestedLevels.map(\.description), [PHAccessLevel.addOnly.description],
                       "only add-only access may be requested")
    }

    // MARK: - Write failures (PRD §7.3)

    func testWriteFailureCarriesTheSystemDescription() throws {
        let library = StubLibrary(status: .authorized)
        let underlying = NSError(domain: "PHPhotosErrorDomain", code: 3303,
                                 userInfo: [NSLocalizedDescriptionKey: "磁碟空間不足"])
        library.writeError = underlying

        let result = try save(with: library)

        switch result {
        case .failure(.saveFailed(let description)):
            XCTAssertTrue(description.contains("磁碟空間不足"),
                          "the message shown to the user quotes the system error; got \(description)")
        default:
            XCTFail("expected saveFailed, got \(result)")
        }
    }

    /// `performChanges` can report "not successful" with no error at all.
    func testUnsuccessfulWriteWithoutAnErrorStillFails() throws {
        let saver = PhotoSaver(library: FailingSilentlyLibrary())
        let done = expectation(description: "save completes")
        var result: Result<Void, PhotoSaveError>?
        saver.save(image) { result = $0; done.fulfill() }
        wait(for: [done], timeout: 2)

        switch try XCTUnwrap(result) {
        case .failure(.saveFailed):
            break
        default:
            XCTFail("expected saveFailed, got \(String(describing: result))")
        }
    }

    private final class FailingSilentlyLibrary: PhotoLibraryAccessing {
        func authorizationStatus(for level: PHAccessLevel) -> PHAuthorizationStatus { .authorized }
        func requestAuthorization(for level: PHAccessLevel, handler: @escaping (PHAuthorizationStatus) -> Void) {
            handler(.authorized)
        }
        func performChanges(_ changes: @escaping () -> String?,
                           completion: @escaping (Bool, String?, Error?) -> Void) {
            completion(false, nil, nil)
        }
        func saveToAlbum(_ image: UIImage, albumIdentifier: String?, albumTitle: String,
                         completion: @escaping (AlbumWriteResult) -> Void) {
            completion(AlbumWriteResult(succeeded: false, assetIdentifier: nil, albumIdentifier: nil, error: nil))
        }
    }

    // MARK: - Identifier (TASK-28, PRD 0.2 FR-15.1)

    /// `saveReturningIdentifier` (TASK-21 will call this from
    /// `CapturedPhotoStore.recordCapturedAsset(_:)`) reports the new asset's
    /// identifier on success.
    func testSaveReturningIdentifierReportsTheNewAssetsLocalIdentifier() throws {
        let library = StubLibrary(status: .authorized)
        library.identifierToReturn = "asset-42"
        let saver = PhotoSaver(library: library, albumSettings: FakeAlbumSettings())
        let done = expectation(description: "save completes")
        var result: Result<String, PhotoSaveError>?

        saver.saveReturningIdentifier(image) { result = $0; done.fulfill() }
        wait(for: [done], timeout: 2)

        switch try XCTUnwrap(result) {
        case .success(let identifier):
            XCTAssertEqual(identifier, "asset-42")
        case .failure(let error):
            XCTFail("expected success, got \(error)")
        }
    }

    /// `saveReturningIdentifier` shares `save`'s permission branches — a
    /// refusal fails the same way.
    func testSaveReturningIdentifierStillFailsOnPermissionDenial() throws {
        let library = StubLibrary(status: .denied)
        let saver = PhotoSaver(library: library, albumSettings: FakeAlbumSettings())
        let done = expectation(description: "save completes")
        var result: Result<String, PhotoSaveError>?

        saver.saveReturningIdentifier(image) { result = $0; done.fulfill() }
        wait(for: [done], timeout: 2)

        switch try XCTUnwrap(result) {
        case .failure(let error):
            XCTAssertEqual(error, .permissionDenied)
        case .success:
            XCTFail("expected permissionDenied")
        }
    }

    // MARK: - Completion guarantees (the shutter depends on these, FR-5.5)

    func testCompletionRunsOnTheMainQueueEvenWhenCalledOffIt() throws {
        let library = StubLibrary(status: .authorized)
        let saver = PhotoSaver(library: library, albumSettings: FakeAlbumSettings())
        let done = expectation(description: "save completes")
        var wasOnMain = false

        DispatchQueue.global(qos: .userInitiated).async {
            saver.save(self.image) { _ in
                wasOnMain = Thread.isMainThread
                done.fulfill()
            }
        }
        wait(for: [done], timeout: 2)

        XCTAssertTrue(wasOnMain)
    }

    /// A completion that ran twice would re-enable the shutter and show a
    /// second toast; one that never ran would disable it forever.
    func testCompletionRunsExactlyOncePerSave() throws {
        let library = StubLibrary(status: .notDetermined, grants: .authorized)
        let saver = PhotoSaver(library: library, albumSettings: FakeAlbumSettings())
        let done = expectation(description: "save completes")
        done.expectedFulfillmentCount = 1
        done.assertForOverFulfill = true

        saver.save(image) { _ in done.fulfill() }

        wait(for: [done], timeout: 2)
    }

    // MARK: - Native resolution (10.18)

    /// The full-resolution format is the one with the most pixels, not the
    /// widest or the last in the list.
    func testLargestPhotoDimensionsPicksTheBiggestArea() {
        let candidates = [
            CMVideoDimensions(width: 1920, height: 1080),
            CMVideoDimensions(width: 4032, height: 3024),
            CMVideoDimensions(width: 4000, height: 3000)
        ]

        let largest = CameraService.largestPhotoDimensions(from: candidates)

        XCTAssertEqual(largest?.width, 4032)
        XCTAssertEqual(largest?.height, 3024)
    }

    func testLargestPhotoDimensionsPrefersAreaOverWidth() {
        let candidates = [
            CMVideoDimensions(width: 5000, height: 1000),   // widest, 5M pixels
            CMVideoDimensions(width: 4032, height: 3024)    // 12.2M pixels
        ]

        let largest = CameraService.largestPhotoDimensions(from: candidates)

        XCTAssertEqual(largest?.width, 4032)
    }

    func testLargestPhotoDimensionsIgnoresFortyEightMegapixels() {
        let largest = CameraService.largestPhotoDimensions(from: [
            CMVideoDimensions(width: 4032, height: 3024),
            CMVideoDimensions(width: 8064, height: 6048)
        ])

        XCTAssertEqual(largest?.width, 4032)
        XCTAssertEqual(largest?.height, 3024)
    }

    func testLargestPhotoDimensionsPicksTwentyFourMegapixels() {
        let largest = CameraService.largestPhotoDimensions(from: [
            CMVideoDimensions(width: 4032, height: 3024),
            CMVideoDimensions(width: 5712, height: 4284),
            CMVideoDimensions(width: 8064, height: 6048)
        ])

        XCTAssertEqual(largest?.width, 5712)
        XCTAssertEqual(largest?.height, 4284)
    }

    func testLargestPhotoDimensionsFallsBackToSmallestWhenAllOverBudget() {
        let largest = CameraService.largestPhotoDimensions(from: [
            CMVideoDimensions(width: 8064, height: 6048),
            CMVideoDimensions(width: 9000, height: 7000)
        ])

        XCTAssertEqual(largest?.width, 8064)
        XCTAssertEqual(largest?.height, 6048)
    }

    func testLargestPhotoDimensionsOfNothingIsNil() {
        XCTAssertNil(CameraService.largestPhotoDimensions(from: []))
    }
}

// MARK: - DaysCam album (issue #281, TASK-64 acceptance 64.1, 64.2, 64.5, 64.7)

extension PhotoSaverTests {

    private func saveReturningIdentifier(with library: StubLibrary,
                                         settings: FakeAlbumSettings,
                                         file: StaticString = #filePath,
                                         line: UInt = #line) throws -> Result<String, PhotoSaveError> {
        let saver = PhotoSaver(library: library, albumSettings: settings)
        let done = expectation(description: "save completes")
        var result: Result<String, PhotoSaveError>?
        saver.saveReturningIdentifier(image) {
            result = $0
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
        return try XCTUnwrap(result, "completion never ran", file: file, line: line)
    }

    // MARK: Route decision (64.7)

    func testSwitchOffAlwaysRoutesToRecentsWithoutReadingReadWrite() {
        let statuses: [PHAuthorizationStatus] = [.notDetermined, .restricted, .denied, .authorized, .limited]
        for status in statuses {
            var asked = false
            let route = PhotoSaver.route(albumEnabled: false) { asked = true; return status }
            XCTAssertEqual(route, .recentsOnly, "\(status.rawValue)")
            XCTAssertFalse(asked, "switch off must not even read .readWrite")
        }
    }

    func testSwitchOnRoutesToTheAlbumWithFullOrLimitedAccess() {
        let cases: [(PHAuthorizationStatus, PhotoSaveRoute)] = [
            (.authorized, .recentsAndAlbum),
            (.limited, .recentsAndAlbum),
            (.denied, .recentsOnly),
            (.restricted, .recentsOnly),
            (.notDetermined, .recentsOnly)
        ]
        for (status, expected) in cases {
            XCTAssertEqual(PhotoSaver.route(albumEnabled: true) { status }, expected, "\(status.rawValue)")
        }
    }

    // MARK: Saving

    /// 64.1: off behaves exactly like 0.4 — add-only only, no album.
    func testSwitchOffSavesLikeBeforeWithAddOnlyOnly() throws {
        let library = StubLibrary(status: .notDetermined, grants: .authorized)
        library.readWriteStatus = .authorized
        let result = try saveReturningIdentifier(with: library, settings: FakeAlbumSettings(enabled: false))

        XCTAssertEqual(try result.get(), "stub-asset-identifier")
        XCTAssertTrue(library.albumWrites.isEmpty)
        XCTAssertEqual(library.writeCount, 1)
        XCTAssertEqual(library.checkedLevels.map(\.description), [PHAccessLevel.addOnly.description])
        XCTAssertEqual(library.requestedLevels.map(\.description), [PHAccessLevel.addOnly.description])
    }

    /// 64.2: on with full access, one album write and nothing else.
    func testSwitchOnWithFullAccessSavesIntoTheAlbumInOneChange() throws {
        let library = StubLibrary(status: .authorized)
        library.readWriteStatus = .authorized
        library.identifierToReturn = "asset-7"
        let settings = FakeAlbumSettings(enabled: true, albumIdentifier: "album-1")

        let result = try saveReturningIdentifier(with: library, settings: settings)

        XCTAssertEqual(try result.get(), "asset-7")
        XCTAssertEqual(library.albumWrites.count, 1)
        XCTAssertEqual(library.albumWrites.first?.albumIdentifier, "album-1")
        XCTAssertEqual(library.albumWrites.first?.albumTitle, "DaysCam")
        XCTAssertEqual(library.writeCount, 0, "the asset is created inside the album change")
        XCTAssertEqual(settings.rememberCount, 0, "same album, nothing new to remember")
    }

    /// 64.3: the first save, or one after the album was deleted, reports a
    /// new album id — it is remembered for the next save.
    func testANewAlbumIdentifierIsRemembered() throws {
        let library = StubLibrary(status: .authorized)
        library.readWriteStatus = .authorized
        library.albumIdentifierToReturn = "album-recreated"
        let settings = FakeAlbumSettings(enabled: true, albumIdentifier: "album-deleted")

        _ = try saveReturningIdentifier(with: library, settings: settings).get()

        XCTAssertEqual(settings.albumIdentifier, "album-recreated")
    }

    /// 79.5 replaces 64.5: limited access keeps writing to the album without prompting.
    func testSwitchOnWithLimitedAccessSavesIntoTheAlbumSilently() throws {
        let library = StubLibrary(status: .authorized)
        library.readWriteStatus = .limited

        let result = try saveReturningIdentifier(with: library, settings: FakeAlbumSettings(enabled: true))

        XCTAssertEqual(try result.get(), "stub-asset-identifier")
        XCTAssertEqual(library.albumWrites.count, 1)
        XCTAssertEqual(library.writeCount, 0)
        XCTAssertTrue(library.requestedLevels.isEmpty)
    }

    func testSwitchOnWithAccessWithdrawnFallsBackToRecents() throws {
        let library = StubLibrary(status: .authorized)
        library.readWriteStatus = .denied

        let result = try saveReturningIdentifier(with: library, settings: FakeAlbumSettings(enabled: true))

        XCTAssertEqual(try result.get(), "stub-asset-identifier")
        XCTAssertTrue(library.albumWrites.isEmpty)
    }

    /// Saving never asks for `.readWrite` — only the gallery switch does.
    func testSavingNeverRequestsReadWrite() throws {
        for readWrite: PHAuthorizationStatus in [.notDetermined, .limited, .denied, .authorized] {
            let library = StubLibrary(status: .notDetermined, grants: .authorized)
            library.readWriteStatus = readWrite
            _ = try saveReturningIdentifier(with: library, settings: FakeAlbumSettings(enabled: true))
            XCTAssertFalse(library.requestedLevels.contains(.readWrite), "\(readWrite.rawValue)")
        }
    }

    /// The album change failed, so nothing was written; the photo is saved
    /// to 「最近項目」 instead and that counts as success.
    func testAlbumFailureStillSavesThePhotoAndSucceeds() throws {
        let library = StubLibrary(status: .authorized)
        library.readWriteStatus = .authorized
        library.albumWriteError = NSError(domain: "test", code: 1)
        let settings = FakeAlbumSettings(enabled: true)

        let result = try saveReturningIdentifier(with: library, settings: settings)

        XCTAssertEqual(try result.get(), "stub-asset-identifier")
        XCTAssertEqual(library.albumWrites.count, 1)
        XCTAssertEqual(library.writeCount, 1, "saved once more, without the album")
        XCTAssertNil(settings.albumIdentifier)
    }

    /// A rejected album transaction must preserve the photo via add-only fallback.
    func testLimitedAlbumError3311PreservesPhotoAndRememberedAlbum() throws {
        let library = StubLibrary(status: .authorized)
        library.readWriteStatus = .limited
        library.albumWriteError = NSError(domain: "PHPhotosErrorDomain", code: 3311)
        let settings = FakeAlbumSettings(enabled: true, albumIdentifier: "remembered-album")

        let result = try saveReturningIdentifier(with: library, settings: settings)

        XCTAssertEqual(try result.get(), "stub-asset-identifier")
        XCTAssertEqual(library.albumWrites.count, 1)
        XCTAssertEqual(library.writeCount, 1)
        XCTAssertEqual(settings.albumIdentifier, "remembered-album")
        XCTAssertEqual(settings.rememberCount, 0)
        XCTAssertTrue(library.requestedLevels.isEmpty)
    }

    /// If the fallback also fails, the photo must not be reported as saved.
    func testAlbumFailureFollowedByAFailedFallbackFails() throws {
        let library = StubLibrary(status: .authorized)
        library.readWriteStatus = .authorized
        library.albumWriteError = NSError(domain: "test", code: 1)
        library.writeError = NSError(domain: "test", code: 2,
                                     userInfo: [NSLocalizedDescriptionKey: "磁碟已滿"])

        let result = try saveReturningIdentifier(with: library, settings: FakeAlbumSettings(enabled: true))

        switch result {
        case .failure(let error): XCTAssertEqual(error, .saveFailed("磁碟已滿"))
        case .success: XCTFail("expected a failure")
        }
    }

    func testAlbumSaveCompletesOnTheMainQueue() throws {
        let library = StubLibrary(status: .authorized)
        library.readWriteStatus = .authorized
        let saver = PhotoSaver(library: library, albumSettings: FakeAlbumSettings(enabled: true))
        let done = expectation(description: "save completes")
        var wasOnMain = false

        DispatchQueue.global(qos: .userInitiated).async {
            saver.save(self.image) { _ in
                wasOnMain = Thread.isMainThread
                done.fulfill()
            }
        }
        wait(for: [done], timeout: 2)

        XCTAssertTrue(wasOnMain)
    }
}

/// `PHAccessLevel` is a plain Objective-C enum, so a failed comparison would
/// otherwise print `[__C.PHAccessLevel]` on both sides and say nothing about
/// which level was actually asked for.
extension PHAccessLevel: @retroactive CustomStringConvertible {
    public var description: String {
        switch self {
        case .addOnly: return "addOnly"
        case .readWrite: return "read-and-write"
        @unknown default: return "unknown(\(rawValue))"
        }
    }
}
