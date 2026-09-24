import Foundation

// TEMP(TASK-17): adapter until TASK-21/24 replaces this view layer.
//
// The 0.1 view layer (camera screen, display settings sheet) and the 0.1
// renderer still speak `ThemeID` and `OverlayPosition`. These two helpers
// translate the 0.2 model back so that those screens keep their 0.1 behavior
// until they are rewritten. Delete this file once nothing calls them.

extension ThemeID {
    /// TEMP(TASK-17): adapter until TASK-21/24 replaces this view layer.
    ///
    /// The 0.1 theme whose migrated style (PRD 0.2 §4.3) equals `style`, or
    /// `classicWhite` for a style no 0.1 theme maps to. Every style the 0.1 UI
    /// can produce maps back exactly, so the round trip is lossless there.
    init(nearestTo style: OverlayStyle) {
        self = ThemeID.allCases.first { OverlayStyle(legacyTheme: $0) == style } ?? .classicWhite
    }
}

extension OverlayPlacement {
    /// TEMP(TASK-17): adapter until TASK-21/24 replaces this view layer.
    ///
    /// The grid anchor for `.anchor`; `.bottomTrailing` for `.custom`, which the
    /// 0.1 renderer cannot draw. The 0.1 UI never produces `.custom`.
    var legacyAnchor: OverlayPosition {
        if case let .anchor(position) = self {
            return position
        }
        return .bottomTrailing
    }
}

extension ThemeID {
    /// TEMP(TASK-18): adapter until TASK-21/24 replaces this view layer.
    ///
    /// The 0.1 picker label, used only by the 0.1 display settings sheet.
    var displayName: String {
        switch self {
        case .classicWhite: return "經典白"
        case .retroOrange: return "復古橘"
        case .filmStrip: return "底片邊條"
        case .minimalDark: return "極簡黑"
        case .softPink: return "柔粉"
        }
    }
}

/// TEMP(TASK-18): adapter until TASK-21/24 replaces this view layer.
///
/// Lets the 0.1 theme picker and camera screen keep addressing the five 0.1
/// themes by `ThemeID`. Each is now `OverlayTheme(style:)` of the migrated
/// style (PRD 0.2 §4.3), so it draws exactly what a migrated profile draws.
extension OverlayTheme: Identifiable {
    /// TEMP(TASK-18): the 0.1 theme this style maps back to.
    var id: ThemeID { ThemeID(nearestTo: style) }

    /// TEMP(TASK-18): the 0.1 picker label.
    var displayName: String { id.displayName }

    /// TEMP(TASK-18): the five 0.1 themes, in 0.1 picker order.
    static var all: [OverlayTheme] {
        ThemeID.allCases.map(theme(for:))
    }

    /// TEMP(TASK-18): the theme a 0.1 `ThemeID` migrates to.
    static func theme(for id: ThemeID) -> OverlayTheme {
        OverlayTheme(style: OverlayStyle(legacyTheme: id))
    }
}
