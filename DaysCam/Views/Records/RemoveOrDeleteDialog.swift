import SwiftUI

extension View {
    /// The choice behind 刪除… (PRD 2.0 FR-18.6, FR-17.14, D8): take the
    /// photo(s) out of the record, or delete them from 「照片」. Shared by the
    /// viewer's ⋯ menu and the wall's selection bar. Removing asks nothing
    /// more; deleting goes on to the system's confirmation.
    ///
    /// - Parameters:
    ///   - title: the dialog's title, e.g. `RemoveOrDeleteDialog.title(recordName:)`.
    ///   - recordName: the record the photos leave.
    func removeOrDeleteDialog(isPresented: Binding<Bool>,
                              title: String,
                              recordName: String,
                              onRemove: @escaping () -> Void,
                              onDelete: @escaping () -> Void) -> some View {
        confirmationDialog(title, isPresented: isPresented, titleVisibility: .visible) {
            Button("從「\(recordName)」移除", action: onRemove)
                .accessibilityIdentifier("removeFromRecordButton")
            Button("刪除照片", role: .destructive, action: onDelete)
                .accessibilityIdentifier("deletePhotoButton")
            Button("取消", role: .cancel) {}
        }
    }
}

/// Wording of the remove-or-delete dialog.
enum RemoveOrDeleteDialog {
    /// "要從「<紀錄名>」移除這張照片，還是從「照片」App 刪除？"
    static func title(recordName: String) -> String {
        "要從「\(recordName)」移除這張照片，還是從「照片」App 刪除？"
    }
}
