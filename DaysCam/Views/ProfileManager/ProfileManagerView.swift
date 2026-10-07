import SwiftUI

/// The 設定檔 sheet (#226 R-1～R-7): a `NavigationStack` whose root is the
/// profile list and whose pushed page edits one profile
/// (`ProfileEditorView`). Rows are name + subtitle with a trailing `›`;
/// reordering is long-press drag and deleting is a swipe action, so no
/// handle or `⋯` menu is drawn. All state lives in `ProfileManagerModel`.
struct ProfileManagerView: View {
    @ObservedObject var model: ProfileManagerModel
    /// Closes the sheet — the checkmark key (FR-14.3).
    var onClose: () -> Void = {}

    var body: some View {
        NavigationStack(path: $model.path) {
            VStack(spacing: 0) {
                list
                addButton
                hint
            }
            .background(Color.white.opacity(0.97))
            .navigationTitle("設定檔")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { CloseButton(action: onClose) } }
            .navigationDestination(for: UUID.self) { id in
                ProfileEditorView(manager: model, profileID: id, onClose: onClose)
            }
        }
        .confirmationDialog("刪除後無法復原，已拍的照片不受影響。",
                            isPresented: deletionBinding,
                            titleVisibility: .visible,
                            presenting: model.deletionCandidate) { candidate in
            Button("刪除「\(candidate.name)」", role: .destructive) { model.confirmDeletion() }
            Button("取消", role: .cancel) { model.cancelDeletion() }
        }
        .alert("無法完成", isPresented: errorBinding) {
            Button("好") { model.lastError = nil }
        } message: {
            if let error = model.lastError {
                Text(error.profileStoreDisplayMessage)
            }
        }
    }

    // MARK: - Pieces

    private var list: some View {
        List {
            ForEach(model.rows) { row in
                profileRow(row)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    // Long-press lifts the row; no ≡ handle and no editMode
                    // (`onMove` only works in edit mode, #226 R-5).
                    .draggable(row.id.uuidString)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if model.canDelete {
                            Button(role: .destructive) {
                                model.requestDeletion(of: row.id)
                            } label: {
                                Text("刪除")
                            }
                        }
                    }
            }
            .onInsert(of: [.plainText]) { index, providers in
                guard let provider = providers.first else { return }
                _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                    guard let text = object as? String, let id = UUID(uuidString: text) else { return }
                    Task { @MainActor in model.move(id: id, toIndex: index) }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func profileRow(_ row: ProfileManagerModel.Row) -> some View {
        HStack(spacing: 0) {
            Button {
                model.select(id: row.id)
                onClose()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(CameraTheme.active)
                        .opacity(row.isCurrent ? 1 : 0)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.name)
                            .font(CameraTheme.toolFont(.subheadline))
                            .foregroundColor(CameraTheme.ink)
                            .lineLimit(1)
                        Text(row.subtitle)
                            .font(.caption)
                            .foregroundColor(CameraTheme.inkSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(row.name)，\(row.subtitle)")
            .accessibilityAddTraits(row.isCurrent ? .isSelected : [])

            Button {
                model.edit(id: row.id)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(CameraTheme.inkTertiary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("編輯\(row.name)")
        }
    }

    private var addButton: some View {
        Button {
            model.addProfile()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                Text(model.addTitle)
            }
            .font(CameraTheme.toolFont(.subheadline).weight(.semibold))
            .foregroundColor(model.canAdd ? CameraTheme.active : CameraTheme.inkTertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .disabled(!model.canAdd)
        .padding(.horizontal, 12)
    }

    private var hint: some View {
        Text("長按拖曳可排序，向左滑可刪除")
            .font(.caption)
            .foregroundColor(CameraTheme.inkTertiary)
            .padding(.bottom, 14)
    }

    // MARK: - Bindings

    private var deletionBinding: Binding<Bool> {
        Binding(get: { model.deletionCandidate != nil },
                set: { isPresented in if !isPresented { model.cancelDeletion() } })
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.lastError != nil },
                set: { isPresented in if !isPresented { model.lastError = nil } })
    }
}

#Preview("設定檔") {
    ProfileManagerView(model: ProfileManagerModel(store: previewStore()))
        .frame(height: 580)
}

#Preview("設定檔（20 個）") {
    ProfileManagerView(model: ProfileManagerModel(store: previewStore(count: 20)))
        .frame(height: 580)
}

/// A store in a throwaway directory so previews never touch real profiles.
@MainActor
private func previewStore(count: Int = 4) -> ProfileStore {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ProfileManagerPreview-\(UUID().uuidString)", isDirectory: true)
    let store = ProfileStore(directory: directory)
    store.load()
    var start = DateComponents()
    start.year = 2026
    start.month = 1
    start.day = 1
    let names = ["小寶", "毛毛", "阿公", "只看日期"]
    while store.profiles.count < count {
        let index = store.profiles.count - 1
        let name = index < names.count ? names[index] : "設定檔 \(store.profiles.count)"
        _ = try? store.add(CameraProfile(name: name, startDate: start,
                                         showDayCount: name != "只看日期", showDate: name == "只看日期"))
    }
    if let first = store.profiles.first { store.select(id: first.id) }
    return store
}

/// The checkmark key that closes the whole sheet (list and edit page alike).
struct CloseButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "checkmark")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(CameraTheme.active)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("完成")
    }
}
