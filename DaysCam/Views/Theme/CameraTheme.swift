import SwiftUI

/// The 0.2 camera screen's fixed light visual language (PRD 0.2 FR-14).
///
/// Every color here is an Asset Catalog entry with only a "universal"
/// (light) appearance — no dark variant — so it never shifts with the
/// system's Light/Dark Mode setting even if some future screen forgets to
/// add `.preferredColorScheme(.light)` (FR-14.1). `CameraScreen` still adds
/// that modifier at its root, since it also has to force system controls
/// (alerts, action sheets) light, which Asset Catalog colors alone cannot do.
/// The `permission*` tokens below are the sole exception (PRD 0.2 FR-14.1,
/// human decision 2026-09-27): the permission-guidance overlay (S-5) is the
/// one screen that *does* follow the system appearance, so those three are
/// backed by Asset Catalog entries with both an Any and a Dark variant.
///
/// Pure tokens: no view code lives here, so `CameraScreen`/`CameraToolbar`
/// stay the only places that lay anything out (PRD 0.2 FR-14 table).
enum CameraTheme {
    /// The camera screen's background (`#F7F3EE`).
    static let background = Color("camBackground")
    /// Primary text/icon color (`#2A2622`).
    static let ink = Color("ink")
    /// Secondary text/icon color: `ink` at 62% (PRD 0.2 FR-14 table).
    static let inkSecondary = ink.opacity(0.62)
    /// Tertiary text/icon color: `ink` at 38%.
    static let inkTertiary = ink.opacity(0.38)
    /// Necessary底色 for a segmented control track and similar chrome
    /// (`ink` at 7%) — every other button stays without a background
    /// (FR-14.2).
    static let fill = Color("fill")
    /// The shutter's inner circle, and other "on" accents (`#FFC27A`).
    static let accent = Color("accent")
    /// Selected/active state — the toolbar icons a tool being on turns this
    /// color (`#C9772A`).
    static let active = Color("active")
    /// Toggles and checkboxes when on (`#F0A64A`, PRD 0.2 FR-14 table) — a
    /// distinct token from `accent`, which is the shutter's own color
    /// (`#FFC27A`) and not what on-state controls elsewhere use (#114).
    static let accentControl = Color("accentControl")

    /// The shutter's outer ring (`#EADFD3`), stated directly since it is
    /// used in exactly one place and does not need an Asset Catalog entry.
    static let shutterRing = Color(red: 0xEA / 255, green: 0xDF / 255, blue: 0xD3 / 255)

    /// The save-confirmation toast's background (`#1E1C1A` at 90%, design
    /// token `.toast`), stated directly since it is used in exactly one
    /// place and does not need an Asset Catalog entry.
    static let toastBackground = Color(red: 0x1E / 255, green: 0x1C / 255, blue: 0x1A / 255).opacity(0.9)

    /// `PermissionGuidanceView`'s background: light `#F7F3EE` (same as
    /// `background`), dark `#000000` at 85% — the one screen that follows
    /// the system appearance instead of staying fixed-light (PRD 0.2
    /// FR-14.1's sole exception, human decision 2026-09-27).
    static let permissionBackground = Color("permissionBackground")
    /// `PermissionGuidanceView`'s primary text/icon color: light `#2A2622`
    /// (same as `ink`), dark `#FFFFFF`.
    static let permissionInk = Color("permissionInk")
    /// `PermissionGuidanceView`'s secondary text/icon color: light `ink` at
    /// 62% (same as `inkSecondary`), dark white at 70%.
    static let permissionInkSecondary = Color("permissionInkSecondary")

    /// Bold, rounded system font for buttons and segmented-control labels
    /// (PRD 0.2 FR-14 table).
    static func toolFont(_ style: Font.TextStyle = .subheadline) -> Font {
        .system(style, design: .rounded).weight(.bold)
    }

    /// The bouncy spring every toolbar/panel animation in 0.2 uses.
    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.8)
}
