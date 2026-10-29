import SwiftUI

/// The record editor (PRD 2.0 FR-21): the shared rules form (name, start
/// date, day-count rules) plus the 相簿 row. One page for adding and editing.
/// Adding shows a checkmark that creates the record and opens it; editing
/// saves as it goes and the back button leaves.
struct RecordEditorView: View {
    @ObservedObject var model: RecordListModel
    let profileID: UUID
    /// Called with the record's id after the checkmark created it.
    var onCreated: (UUID) -> Void = { _ in }

    var body: some View {
        if let profile = model.profile(id: profileID) {
            RecordEditorContent(model: model, profile: profile, onCreated: onCreated)
        } else {
            // The record vanished (deleted); the stack pops itself.
            Color.clear.onAppear { model.path = [] }
        }
    }
}

private struct RecordEditorContent: View {
    @ObservedObject var model: RecordListModel
    let profile: CameraProfile
    var onCreated: (UUID) -> Void
    @StateObject private var rulesModel: RulesTabModel

    init(model: RecordListModel, profile: CameraProfile, onCreated: @escaping (UUID) -> Void) {
        self.model = model
        self.profile = profile
        self.onCreated = onCreated
        _rulesModel = StateObject(wrappedValue: model.rulesModel(for: profile))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                RulesTabView(model: rulesModel,
                             appliesOuterPadding: false,
                             focusesNameOnAppear: model.isDraft(profile.id))
                albumRow
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
        }
        .background(CameraTheme.background.ignoresSafeArea())
        .navigationTitle(model.isDraft(profile.id) ? "新增紀錄" : profile.name)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("recordEditor")
        .toolbar {
            if model.isDraft(profile.id) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if let id = model.confirmNewRecord() { onCreated(id) }
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel("建立")
                    .accessibilityIdentifier("createRecordButton")
                }
            }
        }
    }

    @ViewBuilder
    private var albumRow: some View {
        let state = model.albumRowState(for: profile)
        VStack(spacing: 0) {
            switch state {
            case let .available(title):
                NavigationLink {
                    AlbumPickerView(model: model.albumPickerModel(for: profile.id))
                } label: {
                    albumRowLabel(title: title, showsChevron: true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("albumRow")
            case .needsPermission:
                albumRowLabel(title: "需要相簿權限", showsChevron: false)
                    .foregroundColor(CameraTheme.inkTertiary)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("albumRow")
            }
        }
        .background(
            RoundedRectangle(cornerRadius: RulesTabView.blockCornerRadius, style: .continuous)
                .fill(CameraTheme.fill)
        )
    }

    private func albumRowLabel(title: String, showsChevron: Bool) -> some View {
        HStack(spacing: 10) {
            Text("相簿")
                .font(CameraTheme.toolFont(.subheadline))
                .foregroundColor(CameraTheme.ink)
            Spacer(minLength: 8)
            Text(title)
                .font(.subheadline)
                .lineLimit(1)
                .foregroundColor(CameraTheme.inkSecondary)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(CameraTheme.inkTertiary)
            }
        }
        .padding(.horizontal, RulesTabView.rowHorizontalPadding)
        .frame(minHeight: RulesTabView.rowMinHeight)
        .contentShape(Rectangle())
    }
}
