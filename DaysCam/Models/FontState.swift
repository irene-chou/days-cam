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
/// Implemented by TASK-33's `FontLibrary`; read by the rendering layer and by
/// the UI (TASK-34, TASK-35). The renderer asks once per draw and turns the
/// answer into a `ResolvedOverlayFont`, so it never holds on to a provider.
///
/// Not actor-isolated on purpose: the baking path runs off the main thread.
/// Resolve on the thread that owns the provider (the main actor, for the
/// camera screen) and hand the resolved font to the background work.
protocol FontAvailabilityProviding {
    /// The current state of `fontID`. `pingFang` is always `.available`;
    /// the renderer does not even ask for it.
    func state(for fontID: OverlayFontID) -> FontState
}

/// TEMP(TASK-32 → TASK-34/35): the availability every rendering call falls
/// back to until its caller passes the real `FontLibrary`.
///
/// Only PingFang is available, so every other font resolves to PingFang —
/// exactly what a 0.3 install shows before any font has been downloaded.
struct PingFangOnlyFontAvailability: FontAvailabilityProviding {
    /// Creates the provider.
    init() {}

    /// `.available` for `pingFang`, `.notDownloaded` for everything else.
    func state(for fontID: OverlayFontID) -> FontState {
        fontID == .pingFang ? .available : .notDownloaded
    }
}
