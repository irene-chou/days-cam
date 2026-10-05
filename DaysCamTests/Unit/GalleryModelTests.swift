import Combine
import Photos
import UIKit
import XCTest
@testable import DaysCam

/// TASK-29 acceptance 29.1～29.5 (plus FR-15.5 title text and FR-15.4's
/// reload), against a fake photo library.
@MainActor
final class GalleryModelTests: XCTestCase {
    private final class FakeLibrary: GalleryLibrary {
        var status: PHAuthorizationStatus
        var items: [GalleryPhoto]
        var deleteSucceeds = true
        private(set) var requestCount = 0
        private(set) var deletedIDs: [String] = []

        init(status: PHAuthorizationStatus = .authorized, count: Int = 6) {
            self.status = status
            items = (1...max(count, 1)).prefix(count).map {
                // Newest first: photo "p1" is the newest.
                GalleryPhoto(id: "p\($0)", creationDate: Date(timeIntervalSince1970: 1_768_000_000 - Double($0) * 3600))
            }
        }

        func readStatus() -> PHAuthorizationStatus { status }
        func requestReadAccess() async -> PHAuthorizationStatus {
            requestCount += 1
            return status
        }
        func latestVisiblePhotoIDs(limit: Int) -> [String] { items.prefix(limit).map(\.id) }
        func photos() -> [GalleryPhoto] { items }
        /// When set, `deletePhoto` suspends until `releaseDelete()`.
        var holdDelete = false
        private var deleteGate: CheckedContinuation<Void, Never>?
        func releaseDelete() { deleteGate?.resume(); deleteGate = nil }
        func deletePhoto(id: String) async -> Bool {
            deletedIDs.append(id)
            if holdDelete { await withCheckedContinuation { deleteGate = $0 } }
            guard deleteSucceeds else { return false }
            items.removeAll { $0.id == id }
            return true
        }
        func image(id: String, targetSize: CGSize) async -> UIImage? { nil }
        private var changeContinuation: AsyncStream<Void>.Continuation?
        private(set) var isObserving = false
        func changes() -> AsyncStream<Void> {
            AsyncStream { continuation in
                changeContinuation = continuation
                isObserving = true
                continuation.onTermination = { [weak self] _ in
                    Task { @MainActor in self?.isObserving = false }
                }
            }
        }
        func notifyChange() { changeContinuation?.yield() }
    }

    private func makeModel(_ library: FakeLibrary) -> GalleryModel {
        GalleryModel(library: library, timeZone: TimeZone(identifier: "Asia/Taipei") ?? .current)
    }

    /// 29.1
    func testOpensOnNewestPhotoWithPosition() async {
        let model = makeModel(FakeLibrary(count: 6))
        await model.requestAccessAndLoad()
        XCTAssertEqual(model.phase, .photos)
        XCTAssertEqual(model.currentPhoto?.id, "p1")
        XCTAssertEqual(model.subtitleText, "1 / 6")
    }

    /// 29.2
    func testDeletingThirdShowsFormerFourth() async {
        let model = makeModel(FakeLibrary(count: 6))
        await model.requestAccessAndLoad()
        model.selectedIndex = 2
        await model.deleteCurrent()
        XCTAssertEqual(model.currentPhoto?.id, "p4")
        XCTAssertEqual(model.subtitleText, "3 / 5")
    }

    /// 29.3
    func testDeletingLastShowsPrevious() async {
        let model = makeModel(FakeLibrary(count: 5))
        await model.requestAccessAndLoad()
        model.selectedIndex = 4
        await model.deleteCurrent()
        XCTAssertEqual(model.currentPhoto?.id, "p4")
        XCTAssertEqual(model.subtitleText, "4 / 4")
    }

    /// 29.4
    func testDeletingEverythingShowsEmptyState() async {
        let model = makeModel(FakeLibrary(count: 2))
        await model.requestAccessAndLoad()
        await model.deleteCurrent()
        await model.deleteCurrent()
        XCTAssertEqual(model.phase, .empty)
        XCTAssertNil(model.subtitleText)
        XCTAssertNil(model.currentPhoto)
    }

    func testNoPhotosAtStartShowsEmptyState() async {
        let library = FakeLibrary(count: 1)
        library.items = []
        let model = makeModel(library)
        await model.requestAccessAndLoad()
        XCTAssertEqual(model.phase, .empty)
    }

    /// 29.5
    func testDeniedAndRestrictedShowPermissionState() async {
        for status in [PHAuthorizationStatus.denied, .restricted] {
            let model = makeModel(FakeLibrary(status: status))
            await model.requestAccessAndLoad()
            XCTAssertEqual(model.phase, .denied, "\(status)")
            XCTAssertTrue(model.photos.isEmpty)
        }
    }

    /// FR-15.3: limited access is usable.
    func testLimitedAccessShowsPhotos() async {
        let model = makeModel(FakeLibrary(status: .limited))
        await model.requestAccessAndLoad()
        XCTAssertEqual(model.phase, .photos)
    }

    /// A cancelled system confirmation changes nothing.
    func testCancelledDeletionKeepsPhoto() async {
        let library = FakeLibrary(count: 3)
        library.deleteSucceeds = false
        let model = makeModel(library)
        await model.requestAccessAndLoad()
        await model.deleteCurrent()
        XCTAssertEqual(model.photos.count, 3)
        XCTAssertEqual(model.currentPhoto?.id, "p1")
        XCTAssertFalse(model.isDeleting)
    }

    /// FR-15.4 / 29.10: a photo deleted elsewhere vanishes on reload and the
    /// selection follows the same photo.
    func testReloadDropsExternallyDeletedPhotoAndKeepsSelection() async {
        let library = FakeLibrary(count: 4)
        let model = makeModel(library)
        await model.requestAccessAndLoad()
        model.selectedIndex = 2 // p3
        library.items.removeAll { $0.id == "p1" }
        model.reload()
        XCTAssertEqual(model.currentPhoto?.id, "p3")
        XCTAssertEqual(model.subtitleText, "2 / 3")
    }

    /// FR-15.5: "yyyy/MM/dd HH:mm" in the device time zone.
    func testTitleIsCaptureDateTime() async {
        let library = FakeLibrary(count: 1)
        // 2026-01-10 14:32 in Asia/Taipei (UTC+8) = 06:32 UTC.
        library.items = [GalleryPhoto(id: "p1", creationDate: Date(timeIntervalSince1970: 1_768_026_720))]
        let model = makeModel(library)
        await model.requestAccessAndLoad()
        XCTAssertEqual(model.titleText, "2026/01/10 14:32")
    }

    func testTitleFallsBackWhenNoPhotoOrDate() async {
        let library = FakeLibrary(count: 1)
        library.items = [GalleryPhoto(id: "p1", creationDate: nil)]
        let model = makeModel(library)
        XCTAssertEqual(model.titleText, "照片")
        await model.requestAccessAndLoad()
        XCTAssertEqual(model.titleText, "照片")
    }

    // MARK: - Live refresh (#192)

    /// Polls (yielding to the main actor) until `condition` holds.
    private func waitUntil(_ message: String = "", file: StaticString = #filePath, line: UInt = #line,
                           _ condition: () -> Bool) async {
        for _ in 0..<400 where !condition() { try? await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertTrue(condition(), message, file: file, line: line)
    }

    func testLiveChangeAddingPhotoUpdatesListKeepsCurrent() async {
        let library = FakeLibrary(count: 3)
        let model = makeModel(library)
        await model.requestAccessAndLoad()
        model.selectedIndex = 1 // p2
        await waitUntil { library.isObserving }
        library.items.insert(GalleryPhoto(id: "new", creationDate: nil), at: 0)
        library.notifyChange()
        await waitUntil { model.photos.count == 4 }
        XCTAssertEqual(model.currentPhoto?.id, "p2")
        XCTAssertEqual(model.subtitleText, "3 / 4")
        model.stopObservingLibraryChanges()
    }

    func testLiveChangeRemovingCurrentPicksSameIndexThenPrevious() async {
        let library = FakeLibrary(count: 5)
        let model = makeModel(library)
        await model.requestAccessAndLoad()
        model.selectedIndex = 2
        await waitUntil { library.isObserving }
        library.items.removeAll { $0.id == "p3" }
        library.notifyChange()
        await waitUntil { model.photos.count == 4 }
        XCTAssertEqual(model.currentPhoto?.id, "p4")
        XCTAssertEqual(model.subtitleText, "3 / 4")
        model.selectedIndex = 3
        library.items.removeAll { $0.id == "p5" }
        library.notifyChange()
        await waitUntil { model.photos.count == 3 }
        XCTAssertEqual(model.currentPhoto?.id, "p4")
        XCTAssertEqual(model.subtitleText, "3 / 3")
        model.stopObservingLibraryChanges()
    }

    func testLiveChangeRemovingAllShowsEmptyAndAddingRestores() async {
        let library = FakeLibrary(count: 2)
        let model = makeModel(library)
        await model.requestAccessAndLoad()
        await waitUntil { library.isObserving }
        library.items = []
        library.notifyChange()
        await waitUntil { model.phase == .empty }
        library.items = [GalleryPhoto(id: "x", creationDate: nil)]
        library.notifyChange()
        await waitUntil { model.phase == .photos }
        XCTAssertEqual(model.subtitleText, "1 / 1")
        model.stopObservingLibraryChanges()
    }

    func testStoppingObserverUnregisters() async {
        let library = FakeLibrary(count: 3)
        let model = makeModel(library)
        await model.requestAccessAndLoad()
        await waitUntil { library.isObserving }
        model.stopObservingLibraryChanges()
        await waitUntil { !library.isObserving }
    }

    func testObserverDoesNotStartWhenDenied() async {
        let library = FakeLibrary(status: .denied)
        let model = makeModel(library)
        await model.requestAccessAndLoad()
        XCTAssertFalse(library.isObserving)
    }

    /// Denied while open, then the user grants access in Settings.
    func testObservationStartsAfterDeniedBecomesAuthorized() async {
        let library = FakeLibrary(status: .denied)
        let model = makeModel(library)
        await model.requestAccessAndLoad()
        XCTAssertFalse(library.isObserving)
        library.status = .authorized
        await model.requestAccessAndLoad()
        XCTAssertEqual(model.phase, .photos)
        await waitUntil { library.isObserving }
        model.stopObservingLibraryChanges()
    }

    func testUnrelatedChangeDoesNotRepublishPhotos() async {
        let library = FakeLibrary(count: 3)
        let model = makeModel(library)
        await model.requestAccessAndLoad()
        await waitUntil { library.isObserving }
        var publishCount = 0
        let sink = model.$photos.dropFirst().sink { _ in publishCount += 1 }
        library.notifyChange() // same contents
        library.notifyChange()
        // A later real change proves the earlier notifications were processed.
        library.items.removeLast()
        library.notifyChange()
        await waitUntil { model.photos.count == 2 }
        XCTAssertEqual(publishCount, 1)
        sink.cancel()
        model.stopObservingLibraryChanges()
    }

    /// A change notification arriving while a delete is in flight.
    func testChangeDuringDeleteStaysConsistent() async {
        let library = FakeLibrary(count: 4)
        let model = makeModel(library)
        await model.requestAccessAndLoad()
        model.selectedIndex = 1 // p2
        await waitUntil { library.isObserving }
        library.holdDelete = true
        let deletion = Task { await model.deleteCurrent() }
        await waitUntil { library.deletedIDs == ["p2"] }
        library.items.removeAll { $0.id == "p2" } // library applies it
        library.notifyChange()
        await waitUntil { model.photos.count == 3 }
        library.releaseDelete()
        await deletion.value
        XCTAssertEqual(model.photos.map(\.id), ["p1", "p3", "p4"])
        XCTAssertEqual(model.currentPhoto?.id, "p3")
        XCTAssertEqual(model.subtitleText, "2 / 3")
        XCTAssertFalse(model.isDeleting)
        model.stopObservingLibraryChanges()
    }
}
