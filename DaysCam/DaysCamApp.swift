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
            #if DEBUG
            LimitedAlbumSpikeView()
            #else
            CameraScreen(model: cameraScreenModel)
            #endif
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
        let profileStore = ProfileStore()
        profileStore.load()
        return CameraScreenModel(cameraService: CameraService(),
                                 profileStore: profileStore,
                                 fontLibrary: FontLibrary())
    }
}
