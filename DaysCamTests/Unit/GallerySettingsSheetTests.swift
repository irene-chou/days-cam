import Photos
import SwiftUI
import XCTest
@testable import DaysCam

/// TASK-74 (74.1, 74.2, 74.5): the gallery settings sheet.
@MainActor
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

    private func host(isOn: Bool, notice: GalleryAlbumNotice? = nil) -> UIWindow {
        var value = isOn
        let sheet = GallerySettingsSheet(isOn: Binding(get: { value }, set: { value = $0 }), notice: notice)
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
        window.frame = CGRect(x: 0, y: 0, width: 393, height: notice == nil ? 300 : 440)
        window.rootViewController = UIHostingController(rootView: sheet)
        window.makeKeyAndVisible()
        window.rootViewController?.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        return window
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

    /// Writes screenshots when `SHEET_SHOTS_DIR` is set (PR evidence only).
    func testWriteScreenshots() throws {
        guard let dir = ProcessInfo.processInfo.environment["SHEET_SHOTS_DIR"] else { return }
        for (name, isOn, notice) in [("on", true, nil), ("off", false, nil),
                                     ("denied", false, GalleryAlbumNotice.needsFullAccess)] as [(String, Bool, GalleryAlbumNotice?)] {
            let window = host(isOn: isOn, notice: notice)
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            try image.pngData()?.write(to: URL(fileURLWithPath: "\(dir)/sheet-\(name).png"))
        }
    }
}
