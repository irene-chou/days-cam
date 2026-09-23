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
            return "無法存入相簿，請到「設定 → DaysCam → 照片」開啟「加入照片」權限。這張照片尚未儲存。"
        case let .saveFailed(description):
            return "儲存失敗：\(description)。請確認裝置儲存空間後再試一次。"
        }
    }

    /// Whether the alert showing this message should offer a "前往設定"
    /// button — true only for the permission failure; a full library or a
    /// transient write error has nothing in Settings to fix.
    var showsSettingsAction: Bool {
        self == .permissionDenied
    }
}
