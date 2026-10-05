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
        func deletePhoto(id: String) async -> Bool {
            deletedIDs.append(id)
            guard deleteSucceeds else { return false }
            items.removeAll { $0.id == id }
            return true
        }
        func image(id: String, targetSize: CGSize) async -> UIImage? { nil }
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
}
