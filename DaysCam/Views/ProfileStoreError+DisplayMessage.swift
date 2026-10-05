import Foundation

/// User-facing text for a `ProfileStoreError`, per PRD FR-1.6–FR-1.8.
///
/// Lives in `Views/` rather than alongside `ProfileStoreError` in
/// `Services/ProfileStore.swift` (core-dev's file) because these are display
/// strings, not persistence-layer concerns — the same split the old profile editor
/// already used for `CameraProfileValidationError` before this file existed.
extension ProfileStoreError {
    var displayMessage: String {
        switch self {
        case let .limitReached(limit):
            // FR-1.7. Reachable in practice only if two screens raced past the
            // "新增" disabled state; the UI is expected to prevent this normally.
            return "已達上限 \(limit) 個設定檔"
        case .lastProfile:
            // FR-1.8, same defensive-backstop situation as above.
            return "至少需要保留一個設定檔"
        case .profileNotFound:
            return "找不到這個設定檔，請重新整理後再試一次"
        case let .invalidProfile(validationError):
            return validationError.displayMessage
        case .writeFailed:
            return "儲存失敗，請再試一次"
        }
    }
}

/// User-facing text for a `CameraProfileValidationError`, per PRD FR-1.6,
/// FR-2.4, FR-2.8 and FR-2.9.
extension CameraProfileValidationError {
    var displayMessage: String {
        switch self {
        case .nameEmpty:
            return "名稱不能空白"
        case let .nameTooLong(length):
            return "名稱過長（\(length) 字），上限 \(CameraProfile.maximumNameLength) 字"
        case .startDateMissingComponents, .startDateHasExtraComponents, .startDateNotARealDate:
            return "起始日不正確"
        case .displaySwitchesAllOff:
            return "至少需要顯示天數或日期其中一項"
        case .displayUnitsEmpty:
            return "至少要勾選一個天數單位"
        case .ageWordingRequiresYearUnit:
            return "歲的措辭只能在勾選年時使用"
        // TASK-17: 0.2 style and position invariants (PRD 0.2 §4.1). The 0.1 UI
        // cannot produce these; wording to be reviewed with the 0.2 panels.
        case .sizeScaleOutOfRange:
            return "字級超出範圍"
        case .customPositionOutOfRange:
            return "位置超出範圍"
        case .colorNotStorable:
            return "顏色不正確"
        }
    }
}

/// Convenience for surfacing any thrown error with FR-1.6–FR-1.8 wording when
/// it is a `ProfileStoreError`, and a generic fallback otherwise (e.g. an
/// error a test's spy closure throws that is not `ProfileStoreError`).
extension Error {
    var profileStoreDisplayMessage: String {
        (self as? ProfileStoreError)?.displayMessage ?? "請再試一次。"
    }
}
