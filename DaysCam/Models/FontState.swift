import Foundation

/// Why a font download or check failed (PRD 0.3 §4.4).
enum FontFailureReason: Equatable, Hashable, Sendable {
    /// The device had no network connection (FR-16.10's own message).
    case noNetwork
    /// Anything else: a server error, a checksum mismatch, a timed-out match.
    case other
}

/// Whether an overlay font can be drawn right now (PRD 0.3 §4.4).
///
/// Runtime only, never persisted. Only `.available` lets the renderer draw a
/// font; every other state resolves to PingFang in the viewfinder and the
/// photo alike (FR-5.14, FR-16.14).
enum FontState: Equatable, Hashable, Sendable {
    /// Can be drawn now: PingFang, a registered open-source font, or a system
    /// font whose match has completed.
    case available
    /// Not on the device.
    case notDownloaded
    /// On the device, but registering or matching has not finished since launch.
    case preparing
    /// Downloading; `progress` runs from 0 to 1.
    case downloading(progress: Double)
    /// The download or verification failed.
    case failed(FontFailureReason)

    /// Whether the renderer may draw the font itself.
    var isAvailable: Bool { self == .available }
}

/// Read-only answer to "can this font be drawn right now" (PRD 0.3 §4.4).
///
/// Implemented by TASK-33's `FontLibrary`; read by
/// `OverlayMetrics.resolvedFont(for:availability:)` and by the UI (TASK-34,
/// TASK-35).
///
/// Main actor only. The rendering layer never sees a provider: the caller
/// resolves once on the main actor and passes the `Sendable`
/// `ResolvedOverlayFont` on, including to the background baking work.
@MainActor
protocol FontAvailabilityProviding {
    /// The current state of `fontID`. `pingFang` is always `.available`;
    /// resolution does not even ask for it.
    func state(for fontID: OverlayFontID) -> FontState
    /// Availability of an exact catalog face.
    func state(for fontID: OverlayFontID, weightID: String?) -> FontState
}

extension FontAvailabilityProviding {
    /// Legacy providers only know the default face; other faces stay unavailable.
    func state(for fontID: OverlayFontID, weightID: String?) -> FontState {
        let entry = FontCatalog.entry(for: fontID)
        let weight = entry.weight(for: weightID)
        if entry.source == .builtIn { return .available }
        return weight.id == entry.defaultWeight.id ? state(for: fontID) : .notDownloaded
    }
}
