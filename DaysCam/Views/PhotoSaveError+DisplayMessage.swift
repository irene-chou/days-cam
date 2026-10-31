import Foundation

/// User-facing text for a `PhotoSaveError`, per PRD §2.3/§7.3.
///
/// Lives in `Views/` rather than alongside `PhotoSaveError` in
/// `Services/PhotoSaver.swift` (core-dev's file) because these are display
/// strings, not persistence-layer concerns — same split as
/// `ProfileStoreError+DisplayMessage.swift`.
extension PhotoSaveError {
    var displayMessage: String {
        switch self {
        case .permissionDenied:
            // `.restricted` is folded into this same case by `PhotoSaver`
            // (PRD §2.3, PR #33) — one message covers both.
            return "新照片沒有存起來。請到「設定」›「DaysCam」›「照片」允許取用後再試一次。"
        case let .saveFailed(description):
            return "儲存失敗：\(description)。請確認裝置儲存空間後再試一次。"
        }
    }

    /// Camera wording (FR-20.4): the permission failure asks for another shot;
    /// the shared `displayMessage` is for export and other callers.
    var cameraDisplayMessage: String {
        switch self {
        case .permissionDenied:
            return "這張照片沒有存起來。請到「設定」›「DaysCam」›「照片」允許取用後再拍一次。"
        case .saveFailed:
            return displayMessage
        }
    }

    /// Whether the alert showing this message should offer a "前往設定"
    /// button — true only for the permission failure; a full library or a
    /// transient write error has nothing in Settings to fix.
    var showsSettingsAction: Bool {
        self == .permissionDenied
    }
}
