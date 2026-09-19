import SwiftUI

/// PRD S-2: the profile list — select, create, edit and delete profiles
/// (FR-1.1–FR-1.10). All state and validation live in `ProfileListModel`;
/// this view only lays it out.
struct ProfileListView: View {
    @ObservedObject var model: ProfileListModel

    var body: some View {
        List {
            ForEach(model.profiles) { profile in
                Button {
                    model.beginEditing(profile)
                } label: {
                    HStack {
                        Text(profile.name)
                            .foregroundColor(.primary)
                        Spacer()
                        if profile.id == model.selectedProfileID {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        model.requestDeletion(of: profile)
                    } label: {
                        Label("刪除", systemImage: "trash")
                    }
                    .disabled(!model.canDeleteProfiles)
                }
            }
        }
        .navigationTitle("設定檔")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.beginCreatingProfile()
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(model.isAtProfileLimit)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if model.isAtProfileLimit {
                statusMessage(model.profileLimitMessage)
            } else if !model.canDeleteProfiles {
                statusMessage(model.lastProfileMessage)
            }
        }
        .sheet(item: editorBinding) { presentation in
            NavigationStack {
                ProfileEditView(model: model.makeEditModel(for: presentation))
            }
        }
        .alert("刪除設定檔？", isPresented: deletionAlertBinding) {
            Button("取消", role: .cancel) { model.cancelDeletion() }
            Button("刪除", role: .destructive) { model.confirmDeletion() }
        } message: {
            if let candidate = model.deletionCandidate {
                Text("「\(candidate.name)」將被永久刪除。")
            }
        }
    }

    private func statusMessage(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(.bar)
    }

    /// `model.presentedEditor` as a `Binding` for `.sheet(item:)`: dismissing
    /// the sheet (swipe-down, tapping outside) must also clear the model's
    /// state, not just the SwiftUI-owned presentation flag.
    private var editorBinding: Binding<ProfileListModel.EditorPresentation?> {
        Binding(get: { model.presentedEditor },
                set: { newValue in if newValue == nil { model.dismissEditor() } })
    }

    private var deletionAlertBinding: Binding<Bool> {
        Binding(get: { model.deletionCandidate != nil },
                set: { isPresented in if !isPresented { model.cancelDeletion() } })
    }
}
