import SwiftUI

@main
struct DaysCamApp: App {
    /// One `CameraService` and one `ProfileStore` for the app's lifetime.
    /// `CameraScreen` calls `onAppear`/`onDisappear` on its model, which in
    /// turn starts/stops the camera session — though in this single-screen
    /// app `onDisappear` effectively never fires in practice (see its own
    /// doc comment). Neither service is ever rebuilt regardless, so a
    /// switched camera, a granted permission or a profile change survives
    /// any future navigating away and back.
    @StateObject private var cameraScreenModel = Self.makeCameraScreenModel()

    var body: some Scene {
        WindowGroup {
            CameraScreen(model: cameraScreenModel)
        }
    }

    /// Builds the screen-level model for launch.
    ///
    /// `ProfileStore.load()` runs here, before the first frame: a fresh
    /// install seeds one default profile, an existing install applies
    /// `lastUsedProfileID` (falling back to the first profile when it no
    /// longer exists). The app always lands directly on the camera screen —
    /// there is no first-launch form to route to instead (PRD §2.2, TASK-12).
    private static func makeCameraScreenModel() -> CameraScreenModel {
        let profileStore = ProfileStore(directory: uiTestProfileDirectory)
        profileStore.load()
        applyUITestFilmDate(to: profileStore)
        return CameraScreenModel(cameraService: CameraService(),
                                 profileStore: profileStore,
                                 fontLibrary: uiTestFontLibrary ?? FontLibrary())
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
