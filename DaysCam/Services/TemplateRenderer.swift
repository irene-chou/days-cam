import Foundation

/// Builds the overlay string for a profile as of a given capture moment.
///
/// `capturedAt` is the moment the photo was taken. MVP always passes the
/// shutter instant; a future import feature can pass a moment obtained
/// elsewhere without this type changing. Never read the system clock in here:
/// `capturedAt` is the only time source (PRD FR-2.18, §6.5.3).
struct TemplateRenderer {
    init() {}

    /// Renders the overlay text for `profile` as of `capturedAt`.
    ///
    /// Assembly order is name, then date, then day count (PRD FR-2.5).
    func render(profile: CameraProfile,
                capturedAt: Date,
                calendar: Calendar = .current) -> String {
        #warning("TemplateRenderer.render is a stage-A placeholder; TASK-04 must replace it")
        return ""
    }
}
