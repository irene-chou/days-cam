import SwiftUI

extension View {
    /// The choice behind 刪除… (PRD 2.0 FR-18.6, FR-17.14, D8): take the
    /// photo(s) out of the record, or delete them from 「照片」. Shared by the
    /// viewer's ⋯ menu and the wall's selection bar. Removing asks nothing
    /// more; deleting goes on to the system's confirmation.
    ///
    /// - Parameters:
    ///   - title: the dialog's title, e.g. `RemoveOrDeleteDialog.title(recordName:count:)`.
    ///   - recordName: the record the photos leave.
    ///   - count: how many photos the delete button names.
    func removeOrDeleteDialog(isPresented: Binding<Bool>,
                              title: String,
                              recordName: String,
                              count: Int = 1,
                              onRemove: @escaping () -> Void,
                              onDelete: @escaping () -> Void) -> some View {
        confirmationDialog(title, isPresented: isPresented, titleVisibility: .visible) {
            Button("從「\(recordName)」移除", action: onRemove)
                .accessibilityIdentifier("removeFromRecordButton")
            Button(RemoveOrDeleteDialog.deleteTitle(count: count), role: .destructive, action: onDelete)
                .accessibilityIdentifier("deletePhotoButton")
            Button("取消", role: .cancel) {}
        }
    }
}

/// Wording of the remove-or-delete dialog.
enum RemoveOrDeleteDialog {
    /// "要從「<紀錄名>」移除這張照片，還是從「照片」App 刪除？", or "這 N 張照片"
    /// for more than one.
    static func title(recordName: String, count: Int = 1) -> String {
        let photos = count == 1 ? "這張照片" : "這 \(count) 張照片"
        return "要從「\(recordName)」移除\(photos)，還是從「照片」App 刪除？"
    }

    /// "刪除照片", or "刪除 N 張照片" for more than one.
    static func deleteTitle(count: Int) -> String {
        count == 1 ? "刪除照片" : "刪除 \(count) 張照片"
    }
}
