import Foundation

/// One of PRD §7.3's capture-time failures (baking or saving), ready for
/// `CameraScreen` to alert on.
///
/// `id` exists for the same reason `ToastState.id` does: `CameraScreenModel`
/// clears `captureError` between failures, so two back-to-back failures with
/// identical text would otherwise compare equal — giving `.alert` nothing
/// to react to on the second one.
struct CaptureAlertError: Identifiable, Equatable {
    let id = UUID()
    /// The message shown in the alert body.
    let message: String
    /// Whether the alert should offer a "前往設定" button
    /// (`UIApplication.openSettingsURLString`) alongside the dismiss button
    /// — true for the photo-library-permission failure (PRD §2.3), false
    /// for every other capture-time failure.
    let showsSettingsAction: Bool
}
