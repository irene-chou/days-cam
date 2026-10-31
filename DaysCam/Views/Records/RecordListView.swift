import SwiftUI

/// The home screen of 2.0: the 紀錄 list (PRD 2.0 FR-16, D-7 screen 1).
///
/// A large title, `plus` at the top right, then one plain row per record: no
/// thumbnail, no style preview, no frame. Tapping a row pushes that record's
/// photo wall (#618); the camera opens from the wall.
struct RecordListView: View {
    @ObservedObject var model: RecordListModel
    /// The font path and style editors the export page edits through.
    let styleCenter: StyleEditingCenter
    /// Builds the camera for a record each time it opens (#621).
    let makeCameraModel: @MainActor (UUID) -> CameraScreenModel
    /// Debug UI tests: enter the first record at launch, skipping the list.
    var opensFirstRecordAtLaunch = false

    @State private var didOpenAtLaunch = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack(path: $model.path) {
            VStack(spacing: 0) {
                list
                Text("每個紀錄對應「照片」App 裡的一個相簿")
                    .font(.system(size: 12.5))
                    .foregroundColor(CameraTheme.inkTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
            .background(CameraTheme.background.ignoresSafeArea())
            .navigationTitle("紀錄")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.addRecord()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("新增紀錄")
                    .accessibilityIdentifier("addRecordButton")
                }
            }
            .navigationDestination(for: RecordRoute.self) { route in
                switch route {
                case let .wall(id):
                    // Keyed by record: back from the camera on another record
                    // swaps the wall in place (#655), which must build that
                    // record's own model rather than keep the old one.
                    PhotoWallView(profileID: id, listModel: model, styleCenter: styleCenter,
                                  makeCameraModel: makeCameraModel)
                        .id(id)
                case let .editor(id):
                    RecordEditorView(model: model, profileID: id)
                }
            }
        }
        .tint(CameraTheme.active)
        .preferredColorScheme(.light)
        .confirmationDialog("刪除這個紀錄？\(RecordListModel.deletionMessage)",
                            isPresented: deletionBinding,
                            titleVisibility: .visible,
                            presenting: model.deletionCandidate) { candidate in
            Button("刪除「\(candidate.name)」", role: .destructive) { model.confirmDeletion() }
            Button("取消", role: .cancel) { model.cancelDeletion() }
        }
        .alert("無法完成", isPresented: errorBinding) {
            Button("好") { model.lastError = nil }
        } message: {
            if let error = model.lastError as? ProfileStoreError {
                Text(error.displayMessage)
            }
        }
        // A photo that failed to save after its camera closed (#621).
        .alert("無法完成拍照", isPresented: captureFailureBinding, presenting: model.captureFailure) { error in
            if error.showsSettingsAction {
                Button("前往設定") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
            }
            Button("好", role: .cancel) { model.dismissCaptureFailure() }
        } message: { error in
            Text(error.message)
        }
        .alert("設定檔讀取失敗，已重設。", isPresented: corruptionAlertBinding) {
            Button("好") { model.dismissCorruptionRecoveredAlert() }
        }
        .onAppear {
            model.startObservingLibrary()
            model.reloadLibrary()
            openFirstRecordIfRequested()
        }
        // PRD 0.3 FR-5.15: settle the fonts on the device at launch, the last
        // opened record's first, so the export page has them.
        .task { await styleCenter.prepareFontsAtLaunch() }
        // FR-16.11: downloads do not continue in the background.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { styleCenter.sceneDidEnterBackground() }
        }
    }

    // MARK: - Pieces

    private var list: some View {
        List {
            ForEach(model.rows) { row in
                Button {
                    model.openWall(id: row.id)
                } label: {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.name)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(CameraTheme.ink)
                                .lineLimit(1)
                            Text(row.subtitle)
                                .font(.system(size: 13).monospacedDigit())
                                .foregroundColor(CameraTheme.inkSecondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(CameraTheme.inkTertiary)
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(row.name)，\(row.subtitle)")
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("recordRow")
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if model.canDelete {
                        Button(role: .destructive) {
                            model.requestDeletion(of: row.id)
                        } label: {
                            Text("刪除")
                        }
                        .accessibilityIdentifier("recordDeleteButton")
                    }
                    Button {
                        model.edit(id: row.id)
                    } label: {
                        Text("編輯")
                    }
                    .tint(CameraTheme.active)
                    .accessibilityIdentifier("recordEditButton")
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("recordList")
    }

    // MARK: - Opening a record

    private func openFirstRecordIfRequested() {
        guard opensFirstRecordAtLaunch, !didOpenAtLaunch, let first = model.rows.first else { return }
        didOpenAtLaunch = true
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { model.openWall(id: first.id) }
    }

    private var deletionBinding: Binding<Bool> {
        Binding(get: { model.deletionCandidate != nil }, set: { if !$0 { model.cancelDeletion() } })
    }

    private var captureFailureBinding: Binding<Bool> {
        Binding(get: { model.captureFailure != nil },
                set: { if !$0 { model.dismissCaptureFailure() } })
    }

    private var corruptionAlertBinding: Binding<Bool> {
        Binding(get: { model.showsCorruptionRecoveredAlert },
                set: { if !$0 { model.dismissCorruptionRecoveredAlert() } })
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.lastError != nil }, set: { if !$0 { model.lastError = nil } })
    }
}
