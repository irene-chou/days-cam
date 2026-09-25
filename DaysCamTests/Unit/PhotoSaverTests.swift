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

        private(set) var requestedLevels: [PHAccessLevel] = []
        private(set) var checkedLevels: [PHAccessLevel] = []
        private(set) var writeCount = 0

        init(status: PHAuthorizationStatus, grants: PHAuthorizationStatus = .authorized) {
            self.status = status
            self.grants = grants
        }

        func authorizationStatus(for level: PHAccessLevel) -> PHAuthorizationStatus {
            checkedLevels.append(level)
            return status
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
        let saver = PhotoSaver(library: library)
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
    }

    // MARK: - Identifier (TASK-28, PRD 0.2 FR-15.1)

    /// `saveReturningIdentifier` (TASK-21 will call this from
    /// `CapturedPhotoStore.recordCapturedAsset(_:)`) reports the new asset's
    /// identifier on success.
    func testSaveReturningIdentifierReportsTheNewAssetsLocalIdentifier() throws {
        let library = StubLibrary(status: .authorized)
        library.identifierToReturn = "asset-42"
        let saver = PhotoSaver(library: library)
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
        let saver = PhotoSaver(library: library)
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
        let saver = PhotoSaver(library: library)
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
        let saver = PhotoSaver(library: library)
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

    func testLargestPhotoDimensionsOfNothingIsNil() {
        XCTAssertNil(CameraService.largestPhotoDimensions(from: []))
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
