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

    /// Reorder drag state (TASK-58): which row is lifted, how far the
    /// finger has moved, and where the row would land.
    @State private var draggingID: UUID?
    @State private var dragTranslation: CGFloat = 0
    /// True from the release until the dragged row has settled (TASK-102,
    /// #411): a sequenced long-press-then-drag can deliver one more
    /// `onChanged` with the finger's full translation *after* `onEnded`,
    /// which used to overwrite the residual and park the row one slot past
    /// its new place for a frame — the "fly-away".
    @State private var isReleasing = false
    @State private var dragTarget = 0
    /// Each realized row's top edge in the list's space; the row pitch (row
    /// plus the list's own spacing) is read from these, not guessed.
    @State private var rowOrigins: [Int: CGFloat] = [:]
    @State private var suppressTap = false

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
            // No close key (TASK-101, #410): the sheet is dismissed by
            // swiping it down or tapping outside it; `onClose` still runs
            // from the sheet's `onDismiss` in `CameraScreen`.
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
            ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                profileRow(row)
                    .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .named(Self.listSpace)).minY }) {
                        // Not while dragging: the lift/slide offsets would skew the pitch.
                        if draggingID == nil { rowOrigins[index] = $0 }
                    }
                    // Long-press lifts the row, then dragging moves it (no ≡
                    // handle, no editMode: #226 R-5). System drag & drop and
                    // `onMove` never delivered a drop here (TASK-58).
                    .offset(y: reorderOffset(forRowAt: index, id: row.id))
                    .scaleEffect(draggingID == row.id ? 1.03 : 1)
                    .shadow(color: .black.opacity(draggingID == row.id ? 0.18 : 0), radius: 8, y: 3)
                    .zIndex(draggingID == row.id ? 1 : 0)
                    .simultaneousGesture(reorderGesture(row: row, index: index))
                    // List-row traits last: wrapping modifiers above would
                    // otherwise hide them from the list (insets, separator).
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    // A full swipe asks to delete straight away (TASK-104,
                    // #413); the confirmation dialog stays either way.
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if model.canDelete {
                            Button(role: .destructive) {
                                model.requestDeletion(of: row.id)
                            } label: {
                                Text("刪除")
                            }
                        }
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDisabled(draggingID != nil)
        .coordinateSpace(name: Self.listSpace)
    }

    // MARK: - Reorder (TASK-58)

    private static let listSpace = "profileList"

    /// Distance between two neighboring rows' tops, 0 until two are laid out.
    private var rowHeight: CGFloat {
        guard let low = rowOrigins.keys.min(), let high = rowOrigins.keys.max(), high > low,
              let top = rowOrigins[low], let bottom = rowOrigins[high] else { return 0 }
        return (bottom - top) / CGFloat(high - low)
    }

    /// Vertical shift of the row at `index` while a drag is in progress: the
    /// dragged row follows the finger, the rows it passes slide one slot.
    private func reorderOffset(forRowAt index: Int, id: UUID) -> CGFloat {
        guard let draggingID, let from = model.rows.firstIndex(where: { $0.id == draggingID }) else { return 0 }
        if id == draggingID { return dragTranslation }
        if from < dragTarget, index > from, index <= dragTarget { return -rowHeight }
        if from > dragTarget, index < from, index >= dragTarget { return rowHeight }
        return 0
    }

    private func reorderGesture(row: ProfileManagerModel.Row, index: Int) -> some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged { value in
                guard case .second(true, let drag) = value, !isReleasing else { return }
                if draggingID == nil {
                    // Start from this row's own slot without animating a stale
                    // `dragTarget` left over from the previous drag (TASK-76).
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        dragTarget = index
                        draggingID = row.id
                    }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
                dragTranslation = drag?.translation.height ?? 0
                let target = ProfileManagerModel.dragTargetIndex(from: index, translation: dragTranslation,
                                                                 rowHeight: rowHeight, count: model.rows.count)
                // Animate only the neighbors' slide. A value-bound `.animation`
                // on the row also animated the List's row move at release (TASK-76).
                if target != dragTarget {
                    withAnimation(.easeOut(duration: 0.15)) { dragTarget = target }
                }
            }
            .onEnded { value in
                guard case .second(true, _) = value, draggingID == row.id else { return }
                let target = dragTarget
                // Reorder and re-base the offsets with animations disabled:
                // the rows jump to their new slots while the dragged row
                // keeps its on-screen position (the finger's distance from
                // the new slot) and neighbors need no offset. Only that
                // residual then eases to 0, stepped by hand: any ambient
                // animation (`withAnimation`) during the reorder would also
                // animate the List's own row move from the old slots, the
                // jump TASK-76 fixes.
                let residual = ProfileManagerModel.releaseResidual(translation: dragTranslation, from: index,
                                                                   to: target, rowHeight: rowHeight)
                isReleasing = true
                var instant = Transaction()
                instant.disablesAnimations = true
                withTransaction(instant) {
                    model.move(id: row.id, toFinalIndex: target)
                    dragTranslation = residual
                }
                Task { @MainActor in
                    let steps = 9
                    for step in 1...steps {
                        try? await Task.sleep(nanoseconds: 16_000_000)
                        let progress = Double(step) / Double(steps)
                        let remaining = CGFloat((1 - progress) * (1 - progress)) // ease-out
                        withTransaction(instant) { dragTranslation = residual * remaining }
                    }
                    withAnimation(.easeOut(duration: 0.15)) { draggingID = nil }
                    isReleasing = false
                }
                // The release that ends a long press must not also count as a tap.
                suppressTap = true
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    suppressTap = false
                }
            }
    }

    private func profileRow(_ row: ProfileManagerModel.Row) -> some View {
        HStack(spacing: 0) {
            // A tap gesture rather than a `Button` (TASK-103, #412): with the
            // reorder gesture on the row, a `Button` fired on release even
            // after a horizontal drag, which selected the profile and closed
            // the sheet instead of revealing the swipe action.
            Group {
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
            .onTapGesture {
                guard !suppressTap else { return }
                model.select(id: row.id)
                onClose()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(row.name)，\(row.subtitle)")
            .accessibilityIdentifier("profileRow")
            .accessibilityAddTraits(row.isCurrent ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction {
                guard !suppressTap else { return }
                model.select(id: row.id)
                onClose()
            }

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
