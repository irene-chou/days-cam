import SwiftUI

/// PRD S-3: the profile editing screen — name, start date and counting rule
/// (the "logic layer", FR-3.5). All state and validation live in
/// `ProfileEditModel`; this view only lays it out.
struct ProfileEditView: View {
    @ObservedObject var model: ProfileEditModel
    @Environment(\.dismiss) private var dismiss
    @State private var saveErrorMessage: String?

    var body: some View {
        Form {
            Section {
                TextField("名稱", text: Binding(get: { model.profile.name },
                                              set: { model.setName($0) }))
                    .textInputAutocapitalization(.never)
            } footer: {
                Text("\(model.profile.name.count)/\(CameraProfile.maximumNameLength)")
            }

            if model.showsCountingFields {
                Section {
                    DatePicker("起始日",
                               selection: Binding(get: { model.startDateAsDate },
                                                  set: { model.setStartDate($0) }),
                               in: ...model.startDateUpperBound,
                               displayedComponents: .date)
                    Picker("起算規則", selection: Binding(get: { model.profile.countingRule },
                                                      set: { model.profile.countingRule = $0 })) {
                        ForEach(CountingRule.allCases, id: \.self) { rule in
                            Text(displayName(for: rule)).tag(rule)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            Section {
                HStack {
                    Text("今天會顯示為：")
                    Spacer()
                    Text(model.todayPreviewText)
                        .foregroundColor(.secondary)
                }
            }

            if let error = model.validationError {
                Section {
                    Text(message(for: error))
                        .foregroundColor(.red)
                        .font(.footnote)
                }
            }
        }
        .navigationTitle(model.mode == .create ? "新增設定檔" : "編輯設定檔")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("儲存") {
                    do {
                        try model.save()
                        dismiss()
                    } catch {
                        saveErrorMessage = "儲存失敗，請再試一次。"
                    }
                }
                .disabled(!model.canSave)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
        }
        .alert("無法儲存", isPresented: Binding(get: { saveErrorMessage != nil },
                                             set: { if !$0 { saveErrorMessage = nil } })) {
            Button("好") { saveErrorMessage = nil }
        } message: {
            if let saveErrorMessage {
                Text(saveErrorMessage)
            }
        }
    }

    private func displayName(for rule: CountingRule) -> String {
        switch rule {
        case .dayOne: return "當天算第 1 天"
        case .dayZero: return "當天算第 0 天"
        }
    }

    private func message(for error: CameraProfileValidationError) -> String {
        switch error {
        case .nameEmpty:
            return "名稱不能空白"
        case let .nameTooLong(length):
            return "名稱過長（\(length) 字），上限 \(CameraProfile.maximumNameLength) 字"
        case .startDateMissingComponents, .startDateHasExtraComponents, .startDateNotARealDate:
            return "起始日不正確"
        case .displaySwitchesAllOff:
            return "至少需要顯示天數或日期其中一項"
        case .unitPairNotOnSameTrack:
            return "天數單位組合不正確"
        case .ageWordingRequiresYearUnit:
            return "歲的措辭只能在最大單位為年時使用"
        }
    }
}
