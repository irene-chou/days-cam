import Photos
import XCTest
@testable import DaysCam

/// Covers TASK-28's data layer (PRD 0.2 FR-15.1, FR-15.3, FR-15.4):
/// acceptance 28.1, 28.2, 28.4, 28.5.
///
/// Every test gets its own temporary directory, same convention as
/// `ProfileStoreTests`, so nothing here touches the real Application Support
/// directory. The photo library itself is always a fake — a real `PHAsset`
/// has no public initializer, the same boundary `CameraServiceTests`
/// documents for `AVCaptureDevice`.
final class CapturedPhotoStoreTests: XCTestCase {

    private var directory = URL(fileURLWithPath: NSTemporaryDirectory())

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("CapturedPhotoStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    // MARK: - Double

    private final class FakeLibrary: PhotoLibraryReadAccessing {
        var status: PHAuthorizationStatus
        var grants: PHAuthorizationStatus
        /// Identifiers currently visible under the injected permission status.
        var existing: Set<String>
        var statusAfterFetch: PHAuthorizationStatus?

        private(set) var requestCount = 0

        init(status: PHAuthorizationStatus = .notDetermined,
            grants: PHAuthorizationStatus = .authorized,
            existing: Set<String> = []) {
            self.status = status
            self.grants = grants
            self.existing = existing
        }

        func readAuthorizationStatus() -> PHAuthorizationStatus { status }

        func requestReadAuthorization(handler: @escaping (PHAuthorizationStatus) -> Void) {
            requestCount += 1
            status = grants
            handler(grants)
        }

        func existingIdentifiers(among identifiers: [String]) -> Set<String> {
            if let statusAfterFetch { status = statusAfterFetch }
            return existing.intersection(identifiers)
        }
    }

    // MARK: - Helpers

    private func makeStore(library: PhotoLibraryReadAccessing = FakeLibrary()) -> CapturedPhotoStore {
        CapturedPhotoStore(directory: directory, library: library)
    }

    private var fileURL: URL {
        directory.appendingPathComponent(CapturedPhotoStore.fileName)
    }

    // MARK: - 28.1: recording, newest first, survives a reload

    func test_recordingTwoAssets_newestFirst_survivesAReload() {
        let store = makeStore()

        store.recordCapturedAsset("A")
        store.recordCapturedAsset("B")

        XCTAssertEqual(store.capturedAssetIDs, ["B", "A"])

        let reloaded = makeStore()
        XCTAssertEqual(reloaded.capturedAssetIDs, ["B", "A"], "must survive a relaunch")
    }

    func test_recordingTheSameAssetTwiceDoesNotDuplicateIt() {
        let store = makeStore()

        store.recordCapturedAsset("A")
        store.recordCapturedAsset("B")
        store.recordCapturedAsset("A") // e.g. a defensive re-record

        XCTAssertEqual(store.capturedAssetIDs, ["A", "B"])
    }

    // MARK: - 28.2: fetchAssets prunes deleted photos

    func test_fetchAssets_prunesAnIdentifierTheLibraryNoLongerHas() {
        let library = FakeLibrary(status: .authorized, existing: ["B"]) // "A" was deleted from Photos
        let store = makeStore(library: library)
        store.recordCapturedAsset("A")
        store.recordCapturedAsset("B")
        XCTAssertEqual(store.capturedAssetIDs, ["B", "A"])

        let fetched = store.fetchAssets()

        XCTAssertEqual(fetched, ["B"])
        XCTAssertEqual(store.capturedAssetIDs, ["B"])

        let data = try? Data(contentsOf: fileURL)
        let onDisk = data.flatMap { try? JSONDecoder().decode([String].self, from: $0) }
        XCTAssertEqual(onDisk, ["B"], "the pruned identifier must be removed from the file too")
    }

    func test_fetchAssets_keepsOrderWhenNothingWasDeleted() {
        let library = FakeLibrary(status: .authorized, existing: ["A", "B", "C"])
        let store = makeStore(library: library)
        store.recordCapturedAsset("A")
        store.recordCapturedAsset("B")
        store.recordCapturedAsset("C")

        XCTAssertEqual(store.fetchAssets(), ["C", "B", "A"])
    }

    // MARK: - Issue #186: limited visibility must not erase photo history

    func test_fetchAssets_limitedPreservesInvisibleIDsOnDiskAndReload() throws {
        let library = FakeLibrary(status: .limited, existing: ["B"])
        let store = makeStore(library: library)
        store.recordCapturedAsset("A")
        store.recordCapturedAsset("B")
        let originalData = try Data(contentsOf: fileURL)

        XCTAssertEqual(store.fetchAssets(), ["B"])
        XCTAssertEqual(store.capturedAssetIDs, ["B", "A"])
        XCTAssertEqual(try Data(contentsOf: fileURL), originalData)
        let reloaded = makeStore(library: library)
        XCTAssertEqual(reloaded.capturedAssetIDs, ["B", "A"])
        XCTAssertEqual(reloaded.fetchAssets(), ["B"])
        XCTAssertEqual(try Data(contentsOf: fileURL), originalData)

        // Selecting the hidden photo again restores it without recording it anew.
        library.existing = ["A", "B"]
        XCTAssertEqual(reloaded.fetchAssets(), ["B", "A"])
        XCTAssertEqual(try Data(contentsOf: fileURL), originalData)
        XCTAssertEqual(library.requestCount, 0)
    }

    func test_fetchAssets_authorizedAfterLimitedPrunesOnlyDeletedIDs() throws {
        let library = FakeLibrary(status: .limited, existing: ["C"])
        let store = makeStore(library: library)
        for id in ["A", "B", "C"] { store.recordCapturedAsset(id) }

        XCTAssertEqual(store.fetchAssets(), ["C"])
        XCTAssertEqual(store.capturedAssetIDs, ["C", "B", "A"])

        // A was deleted; B was merely hidden by limited access.
        library.status = .authorized
        library.existing = ["B", "C"]
        XCTAssertEqual(store.fetchAssets(), ["C", "B"])
        XCTAssertEqual(store.capturedAssetIDs, ["C", "B"])
        let onDisk = try JSONDecoder().decode([String].self, from: Data(contentsOf: fileURL))
        XCTAssertEqual(onDisk, ["C", "B"])
        XCTAssertEqual(makeStore(library: library).capturedAssetIDs, ["C", "B"])
    }

    func test_fetchAssets_noVisiblePhotosPreservesIDsWithoutFullAccess() throws {
        for status: PHAuthorizationStatus in [.limited, .denied, .restricted, .notDetermined] {
            let library = FakeLibrary(status: status)
            let store = makeStore(library: library)
            store.recordCapturedAsset("A")
            let originalData = try Data(contentsOf: fileURL)

            XCTAssertEqual(store.fetchAssets(), [], "status: \(status)")
            XCTAssertEqual(store.capturedAssetIDs, ["A"])
            XCTAssertEqual(try Data(contentsOf: fileURL), originalData)
            XCTAssertEqual(makeStore(library: library).capturedAssetIDs, ["A"])
            XCTAssertEqual(library.requestCount, 0)
        }
    }

    func test_fetchAssets_authorizedPrunesWhenAllPhotosWereDeleted() throws {
        let store = makeStore(library: FakeLibrary(status: .authorized))
        store.recordCapturedAsset("A")

        XCTAssertEqual(store.fetchAssets(), [])
        XCTAssertEqual(store.capturedAssetIDs, [])
        let onDisk = try JSONDecoder().decode([String].self, from: Data(contentsOf: fileURL))
        XCTAssertEqual(onDisk, [])
    }

    func test_fetchAssets_permissionChangesDuringLookupPreserveIDs() throws {
        for (before, after): (PHAuthorizationStatus, PHAuthorizationStatus) in [
            (.authorized, .limited), (.limited, .authorized)
        ] {
            let library = FakeLibrary(status: before, existing: ["B"])
            library.statusAfterFetch = after
            let store = makeStore(library: library)
            store.recordCapturedAsset("A")
            store.recordCapturedAsset("B")
            let originalData = try Data(contentsOf: fileURL)

            XCTAssertEqual(store.fetchAssets(), ["B"])
            XCTAssertEqual(store.capturedAssetIDs, ["B", "A"])
            XCTAssertEqual(try Data(contentsOf: fileURL), originalData)
        }
    }

    // MARK: - 28.4: requestReadAccessIfNeeded

    func test_requestReadAccessIfNeeded_requestsExactlyOnceThenNeverAgain() {
        let library = FakeLibrary(status: .notDetermined, grants: .authorized)
        let store = makeStore(library: library)
        var results: [PHAuthorizationStatus] = []

        store.requestReadAccessIfNeeded { results.append($0) }
        store.requestReadAccessIfNeeded { results.append($0) }
        store.requestReadAccessIfNeeded { results.append($0) }

        XCTAssertEqual(library.requestCount, 1, "must not prompt again once settled")
        XCTAssertEqual(results, [.authorized, .authorized, .authorized])
    }

    func test_requestReadAccessIfNeeded_alreadyAuthorizedNeverPrompts() {
        let library = FakeLibrary(status: .authorized)
        let store = makeStore(library: library)

        store.requestReadAccessIfNeeded()

        XCTAssertEqual(library.requestCount, 0)
    }

    func test_requestReadAccessIfNeeded_deniedNeverPromptsEither() {
        let library = FakeLibrary(status: .denied)
        let store = makeStore(library: library)

        store.requestReadAccessIfNeeded()

        XCTAssertEqual(library.requestCount, 0, "a settled refusal must not be re-prompted")
    }

    // MARK: - 28.5: a corrupt file behaves like an empty list

    func test_corruptFileIsTreatedAsAnEmptyListWithoutCrashing() throws {
        try "not valid json at all".write(to: fileURL, atomically: true, encoding: .utf8)

        let store = makeStore()

        XCTAssertEqual(store.capturedAssetIDs, [])

        // And it must still be usable afterwards: recording works normally.
        store.recordCapturedAsset("A")
        XCTAssertEqual(store.capturedAssetIDs, ["A"])
    }

    func test_missingFileIsTreatedAsAnEmptyList() {
        let store = makeStore()
        XCTAssertEqual(store.capturedAssetIDs, [])
    }
}
