import Photos
import SwiftUI
import XCTest
@testable import DaysCam

/// TASK-74 (74.1, 74.2, 74.5): the gallery settings sheet.
final class GallerySettingsSheetTests: XCTestCase {
    private final class StubLibrary: PhotoLibraryAccessing {
        let status: PHAuthorizationStatus
        init(status: PHAuthorizationStatus) { self.status = status }
        func authorizationStatus(for level: PHAccessLevel) -> PHAuthorizationStatus { status }
        func requestAuthorization(for level: PHAccessLevel, handler: @escaping (PHAuthorizationStatus) -> Void) {
            handler(status)
        }
        func performChanges(_ changes: @escaping () -> String?,
                            completion: @escaping (Bool, String?, Error?) -> Void) { XCTFail("never writes") }
        func saveToAlbum(_ image: UIImage, albumIdentifier: String?, albumTitle: String,
                         completion: @escaping (AlbumWriteResult) -> Void) { XCTFail("never writes") }
    }

    // 74.4: a store rebuilt on the same defaults gives the sheet's switch the saved state.
    func testSwitchReadsPersistedStateAfterReopen() {
        let suite = "GallerySettingsSheetTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = StubLibrary(status: .authorized)

        let first = AlbumSettingsStore(defaults: defaults, library: library)
        let firstSwitch = first.galleryBinding { _ in }
        XCTAssertFalse(firstSwitch.wrappedValue)
        let enabled = expectation(description: "enabled")
        first.requestEnabling { _ in enabled.fulfill() }
        wait(for: [enabled], timeout: 2)
        XCTAssertTrue(firstSwitch.wrappedValue)

        let reopened = AlbumSettingsStore(defaults: defaults, library: library)
        let reopenedSwitch = reopened.galleryBinding { _ in }
        XCTAssertTrue(reopenedSwitch.wrappedValue, "74.4 on persists")

        reopenedSwitch.wrappedValue = false
        let reopenedAgain = AlbumSettingsStore(defaults: defaults, library: library)
        XCTAssertFalse(reopenedAgain.galleryBinding { _ in }.wrappedValue, "74.4 off persists")
    }

    func testFooterStatesScopeAndRecentItems() {
        XCTAssertTrue(GallerySettingsSheet.footerText.contains("之後拍的照片"), "74.2")
        XCTAssertTrue(GallerySettingsSheet.footerText.contains("最近項目"), "74.2")
    }

    func testNoticeShownInSheetIsNotAlertedOrKeptAfterClosing() {
        let notice = GalleryAlbumNotice.needsFullAccess
        XCTAssertNil(GalleryAlbumNotice.alertNotice(notice, isSheetShowing: true), "no alert while the sheet shows it")
        XCTAssertEqual(GalleryAlbumNotice.alertNotice(notice, isSheetShowing: false), notice, "alert outside the sheet")
        XCTAssertNil(GalleryAlbumNotice.afterSheetDismissed(notice), "closing clears it: no alert, none on reopen")
    }
}
