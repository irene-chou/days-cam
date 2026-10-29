import SwiftUI

@main
struct DaysCamApp: App {
    /// One `CameraService` and one `ProfileStore` for the app's lifetime.
    /// `CameraScreen` calls `onAppear`/`onDisappear` on its model, which
    /// start/stop the camera session as the 紀錄 list presents and dismisses
    /// it. Neither service is ever rebuilt, so a switched camera, a granted
    /// permission or a profile change survives opening and closing the camera.
    @StateObject private var cameraScreenModel: CameraScreenModel
    @StateObject private var recordListModel: RecordListModel

    init() {
        let profileStore = Self.makeProfileStore()
        _cameraScreenModel = StateObject(wrappedValue: Self.makeCameraScreenModel(profileStore: profileStore))
        _recordListModel = StateObject(wrappedValue: RecordListModel(
            store: profileStore,
            library: Self.makeRecordAlbumLibrary(for: profileStore)))
    }

    var body: some Scene {
        WindowGroup {
            RecordListView(model: recordListModel,
                           cameraModel: cameraScreenModel,
                           opensFirstRecordAtLaunch: Self.opensFirstRecordAtLaunch)
        }
    }

    /// Debug UI tests pass `-UITestOpenFirstRecord` to enter the first
    /// record's photo wall at launch instead of stopping on the list (#617,
    /// #618); they tap `wallCameraButton` to reach the camera. Debug builds
    /// only.
    private static var opensFirstRecordAtLaunch: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-UITestOpenFirstRecord")
        #else
        return false
        #endif
    }

    /// The photo library behind the list. Debug UI tests with
    /// `-UITestRecordPhotos <n>` get an in-memory one holding an album
    /// "測試相簿" with all `n` photos; `-UITestBindAlbum` also binds every
    /// record to it.
    private static func makeRecordAlbumLibrary(for profileStore: ProfileStore) -> any RecordAlbumLibrary {
        #if DEBUG
        if let fake = FakeRecordAlbumLibrary.forUITests() {
            let album = FakeRecordAlbumLibrary.Album(id: "uitest-album", title: "測試相簿",
                                                     assetIDs: fake.assets.map(\.id))
            let library = FakeRecordAlbumLibrary(status: fake.status, assets: fake.assets, albums: [album])
            if ProcessInfo.processInfo.arguments.contains("-UITestBindAlbum") {
                for var profile in profileStore.profiles {
                    profile.albumIdentifier = album.id
                    _ = try? profileStore.update(profile)
                }
            }
            return library
        }
        // Entering a record asks for photo access; an empty in-memory library
        // keeps that system alert out of the tests that only want the camera.
        if ProcessInfo.processInfo.arguments.contains("-UITestOpenFirstRecord") {
            return FakeRecordAlbumLibrary()
        }
        #endif
        return SystemRecordAlbumLibrary()
    }

    /// Builds the one `ProfileStore` shared by the list and the camera.
    ///
    /// `ProfileStore.load()` runs here, before the first frame: a fresh
    /// install seeds one default profile, an existing install applies
    /// `lastUsedProfileID` (falling back to the first profile when it no
    /// longer exists). The app lands on the 紀錄 list (PRD 2.0 FR-16).
    private static func makeProfileStore() -> ProfileStore {
        let profileStore = ProfileStore(directory: uiTestProfileDirectory)
        profileStore.load()
        applyUITestFilmDate(to: profileStore)
        return profileStore
    }

    /// Builds the camera screen's model over `profileStore`.
    private static func makeCameraScreenModel(profileStore: ProfileStore) -> CameraScreenModel {
        CameraScreenModel(cameraService: CameraService(),
                          profileStore: profileStore,
                          fontLibrary: uiTestFontLibrary ?? FontLibrary(),
                          captureRotationAngleOverride: uiTestCaptureRotationAngle)
    }

    /// UI tests pass `-UITestCaptureRotationAngle <0|90|180|270>` to pretend
    /// the phone is held that way (#572). Debug builds only.
    private static var uiTestCaptureRotationAngle: CGFloat? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-UITestCaptureRotationAngle"),
              arguments.indices.contains(flag + 1),
              let angle = Double(arguments[flag + 1]) else { return nil }
        return CGFloat(angle)
        #else
        return nil
        #endif
    }

    /// UI tests pass `-UITestFilmDate <corner>` (a `FilmDateCorner` raw value)
    /// to turn the film date on in that corner for every saved profile, the
    /// stand-in for the panel switch of TASK-152 (TASK-153). Debug builds only.
    private static func applyUITestFilmDate(to profileStore: ProfileStore) {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-UITestFilmDate"),
              arguments.indices.contains(flag + 1),
              let corner = FilmDateCorner(rawValue: arguments[flag + 1]) else { return }
        for var profile in profileStore.profiles {
            profile.showFilmDate = true
            profile.filmDateCorner = corner
            _ = try? profileStore.update(profile)
        }
        #endif
    }

    /// Debug builds only: a stand-in font library for UI tests (TASK-150).
    private static var uiTestFontLibrary: (any FontShellControlling)? {
        #if DEBUG
        return UITestFontLibrary.fromLaunchArguments(ProcessInfo.processInfo.arguments)
        #else
        return nil
        #endif
    }

    /// UI tests pass `-UITestFreshProfiles <name>` to start from an empty
    /// profile directory instead of the app's saved one (TASK-70). The same
    /// name reaches the same directory, so a test can relaunch and find its
    /// profile; different names stay apart. Debug builds only.
    private static var uiTestProfileDirectory: URL? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-UITestFreshProfiles"),
              arguments.indices.contains(flag + 1) else { return nil }
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("DaysCamUITest-\(arguments[flag + 1])", isDirectory: true)
        #else
        return nil
        #endif
    }
}
