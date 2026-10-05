import SwiftUI

/// PRD 0.2 FR-9 / design D-2: the management panel that rises from the
/// bottom. Each row is name + start date (no overlay preview), with a `⋯`
/// menu and the system reorder handle at the trailing edge. All state lives
/// in `ProfileManagerModel`.
struct ProfileManagerView: View {
    @ObservedObject var model: ProfileManagerModel
    /// Closes the panel — the checkmark key (FR-9.1, FR-14.3).
    var onClose: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            header
            list
            addButton
        }
        .background(Color.white.opacity(0.97))
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

    private var header: some View {
        HStack {
            Text("管理設定檔")
                .font(CameraTheme.toolFont(.headline))
                .foregroundColor(CameraTheme.ink)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "checkmark")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(CameraTheme.active)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("完成")
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.top, 14)
    }

    private var list: some View {
        List {
            ForEach(model.rows) { row in
                profileRow(row)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .deleteDisabled(true)
            }
            .onMove { model.move(fromOffsets: $0, toOffset: $1) }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        // Keeps the system reorder handle (`≡`) visible on every row (FR-9.4).
        .environment(\.editMode, .constant(.active))
    }

    private func profileRow(_ row: ProfileManagerModel.Row) -> some View {
        HStack(spacing: 8) {
            Button {
                model.select(id: row.id)
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
            .accessibilityAddTraits(row.isCurrent ? .isSelected : [])

            rowMenu(row)
        }
    }

    private func rowMenu(_ row: ProfileManagerModel.Row) -> some View {
        Menu {
            Button {
                model.duplicate(id: row.id)
            } label: {
                Label(model.duplicateTitle, systemImage: "plus.square.on.square")
            }
            .disabled(!model.canDuplicate)
            Button(role: .destructive) {
                model.requestDeletion(of: row.id)
            } label: {
                Label(model.deleteTitle, systemImage: "trash")
            }
            .disabled(!model.canDelete)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(CameraTheme.inkSecondary)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("更多")
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

#Preview("管理設定檔") {
    ProfileManagerView(model: ProfileManagerModel(store: previewStore()))
        .frame(height: 580)
}

#Preview("管理設定檔（20 個）") {
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
