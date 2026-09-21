import SwiftUI

@main
struct DaysCamApp: App {
    /// One `CameraService` for the app's lifetime. `CameraScreen` starts and
    /// stops its session on appear/disappear; it is never rebuilt, so a
    /// switched camera or a granted permission survives navigating away and
    /// back.
    @StateObject private var cameraScreenModel = CameraScreenModel(cameraService: CameraService())

    var body: some Scene {
        WindowGroup {
            CameraScreen(model: cameraScreenModel)
        }
    }
}
