import Photos
import XCTest
@testable import DaysCam

/// Issue #186 / PR #187 independent QA: limited access must never erase
/// recorded photo identifiers; only `.authorized` may prune (TASK-28 28.2, 28.5).
final class CapturedPhotoStoreLimitedAccessAcceptanceTests: XCTestCase {
    private final class StubLibrary: PhotoLibraryReadAccessing {
        var status: PHAuthorizationStatus
        var visible: Set<String>
        private(set) var requestedReadAuthorization = 0

        init(status: PHAuthorizationStatus, visible: Set<String> = []) {
            self.status = status
            self.visible = visible
        }

        func readAuthorizationStatus() -> PHAuthorizationStatus { status }
        func requestReadAuthorization(handler: @escaping (PHAuthorizationStatus) -> Void) {
            requestedReadAuthorization += 1
            handler(status)
        }
        func existingIdentifiers(among identifiers: [String]) -> Set<String> {
            visible.intersection(identifiers)
        }
    }

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("qa-186-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func seededStore(_ library: StubLibrary, ids: [String]) -> CapturedPhotoStore {
        let store = CapturedPhotoStore(directory: directory, library: library)
        for id in ids.reversed() { store.recordCapturedAsset(id) }
        return store
    }

    /// Issue #186 end to end: limited hides A; repeated gallery opens keep the file;
    /// reselect restores A; authorized with A truly deleted prunes it.
    func test_limitedHideReselectThenAuthorizedDeleteLifecycle() throws {
        let library = StubLibrary(status: .limited, visible: ["B"])
        let store = seededStore(library, ids: ["A", "B"])
        let original = try Data(contentsOf: store.fileURL)

        for _ in 0..<3 { XCTAssertEqual(store.fetchAssets(), ["B"]) }
        XCTAssertEqual(try Data(contentsOf: store.fileURL), original)

        library.visible = ["A", "B"]
        XCTAssertEqual(store.fetchAssets(), ["A", "B"])

        library.status = .authorized
        library.visible = ["B"]
        XCTAssertEqual(store.fetchAssets(), ["B"])
        let onDisk = try JSONDecoder().decode([String].self, from: Data(contentsOf: store.fileURL))
        XCTAssertEqual(onDisk, ["B"])
    }

    /// 28.5 under every status: corrupt photos.json is an empty list, no crash,
    /// and fetchAssets never rewrites the file or requests permission.
    func test_corruptFileIsEmptyForEveryStatusAndNotRewritten() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let garbage = Data("{not json".utf8)
        for status: PHAuthorizationStatus in [.authorized, .limited, .denied, .restricted, .notDetermined] {
            let url = directory.appendingPathComponent(CapturedPhotoStore.fileName)
            try garbage.write(to: url)
            let library = StubLibrary(status: status, visible: ["A"])
            let store = CapturedPhotoStore(directory: directory, library: library)
            XCTAssertEqual(store.capturedAssetIDs, [], "status \(status.rawValue)")
            XCTAssertEqual(store.fetchAssets(), [], "status \(status.rawValue)")
            XCTAssertEqual(try Data(contentsOf: url), garbage, "status \(status.rawValue)")
            XCTAssertEqual(library.requestedReadAuthorization, 0)
        }
    }

    /// Recording a new photo while limited keeps previously hidden IDs.
    func test_recordWhileLimitedKeepsHiddenIDs() {
        let library = StubLibrary(status: .limited, visible: ["B"])
        let store = seededStore(library, ids: ["A", "B"])
        store.recordCapturedAsset("C")
        XCTAssertEqual(store.capturedAssetIDs, ["C", "A", "B"])
        XCTAssertEqual(CapturedPhotoStore(directory: directory, library: library).capturedAssetIDs, ["C", "A", "B"])
    }

    /// FR-15.3 / 28.3: read access is .readWrite, saving stays .addOnly, and the
    /// fetch path itself never prompts.
    func test_accessLevelsStaySeparatedAndFetchNeverPrompts() {
        XCTAssertEqual(SystemPhotoLibraryReadAccess.accessLevel, PHAccessLevel.readWrite)
        XCTAssertEqual(PhotoSaver.accessLevel, PHAccessLevel.addOnly)
        let library = StubLibrary(status: .notDetermined)
        let store = seededStore(library, ids: ["A"])
        _ = store.fetchAssets()
        XCTAssertEqual(library.requestedReadAuthorization, 0)
        XCTAssertEqual(store.capturedAssetIDs, ["A"])
    }
}
