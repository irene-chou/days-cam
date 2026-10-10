import SwiftUI

/// The edit page pushed from the 設定檔 list (#226 R-8, R-10): the shared
/// `RulesTabView` form for one profile, then duplicate and delete. Title
/// follows the profile's live name; the back button returns to the list and
/// the checkmark closes the whole sheet.
struct ProfileEditorView: View {
    @ObservedObject var manager: ProfileManagerModel
    let profileID: UUID
    var onClose: () -> Void = {}

    var body: some View {
        if let profile = manager.profile(id: profileID) {
            ProfileEditorContent(manager: manager, profile: profile, onClose: onClose)
        } else {
            // The profile vanished (deleted); the stack pops itself.
            Color.clear.onAppear { manager.resetNavigation() }
        }
    }
}

private struct ProfileEditorContent: View {
    @ObservedObject var manager: ProfileManagerModel
    let profile: CameraProfile
    var onClose: () -> Void
    @StateObject private var rulesModel: RulesTabModel

    init(manager: ProfileManagerModel, profile: CameraProfile, onClose: @escaping () -> Void) {
        self.manager = manager
        self.profile = profile
        self.onClose = onClose
        _rulesModel = StateObject(wrappedValue: manager.rulesModel(for: profile))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                RulesTabView(model: rulesModel,
                             appliesOuterPadding: false,
                             focusesNameOnAppear: manager.focusesName(of: profile.id))
                actions
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
        }
        .background(Color.white.opacity(0.97))
        .navigationTitle(profile.name)
        .navigationBarTitleDisplayMode(.inline)
        // No close key (TASK-101, #410); the system back button returns to
        // the list and the sheet itself is swiped down or tapped away.
    }

    private var actions: some View {
        VStack(spacing: 0) {
            Button {
                manager.duplicate(id: profile.id)
                if manager.lastError == nil { manager.resetNavigation() }
            } label: {
                actionRow(manager.canDuplicate ? "複製這個設定檔" : manager.duplicateTitle, systemImage: "plus.square.on.square",
                          color: manager.canDuplicate ? CameraTheme.ink : CameraTheme.inkTertiary)
            }
            .disabled(!manager.canDuplicate)
            Divider().padding(.leading, RulesTabView.rowHorizontalPadding)
            Button {
                manager.requestDeletion(of: profile.id)
            } label: {
                actionRow(manager.canDelete ? "刪除設定檔" : manager.deleteTitle, systemImage: "trash",
                          color: manager.canDelete ? .red : CameraTheme.inkTertiary)
            }
            .disabled(!manager.canDelete)
        }
        .background(
            RoundedRectangle(cornerRadius: RulesTabView.blockCornerRadius, style: .continuous)
                .fill(CameraTheme.fill)
        )
    }

    private func actionRow(_ title: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
            Text(title)
            Spacer(minLength: 0)
        }
        .font(CameraTheme.toolFont(.subheadline))
        .foregroundColor(color)
        .padding(.horizontal, RulesTabView.rowHorizontalPadding)
        .frame(minHeight: RulesTabView.rowMinHeight)
        .contentShape(Rectangle())
    }
}
