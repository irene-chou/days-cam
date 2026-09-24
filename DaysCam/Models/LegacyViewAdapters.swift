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
