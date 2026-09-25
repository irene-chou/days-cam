import SwiftUI

/// The 格式 (format) tab of the overlay panel (PRD 0.2 FR-11, D-4).
///
/// Stands alone on purpose, like `StyleTabView`/`RulesTabView`: the panel
/// shell and its first-layer segmented control are `ui-shell`'s (TASK-22),
/// which had not landed when this was written. Once it does, `ui-shell`
/// drops this view into the panel body for the 格式 segment, passing in a
/// `FormatTabModel` wrapping the active profile's `DisplaySettingsModel`.
///
/// Second layer is plain text (顯示內容｜天數格式), unlike the style tab's
/// icon-only row (FR-8.5).
struct FormatTabView: View {
    @ObservedObject var model: FormatTabModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            subTabRow
            content
        }
        .padding(.horizontal, 16)
        .alert("無法儲存", isPresented: Binding(get: { model.displaySettings.lastError != nil },
                                             set: { if !$0 { model.displaySettings.lastError = nil } })) {
            Button("好") { model.displaySettings.lastError = nil }
        } message: {
            Text("請再試一次。")
        }
    }

    // MARK: - 第二層：顯示內容｜天數格式 (FR-8.5, 24.1)

    private var subTabRow: some View {
        HStack(spacing: 20) {
            ForEach(FormatTabModel.SubTab.allCases, id: \.self) { subTab in
                let isSelected = model.selectedSubTab == subTab
                Button {
                    model.selectedSubTab = subTab
                } label: {
                    Text(subTab.title)
                        .font(CameraTheme.toolFont(.subheadline))
                        .foregroundColor(isSelected ? CameraTheme.active : CameraTheme.inkSecondary)
                }
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.selectedSubTab {
        case .displayContent: displayContentSection
        case .dayCountFormat: dayCountFormatSection
        }
    }

    // MARK: - 顯示內容 (FR-11.1, FR-11.2)

    private var displayContentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 28) {
                displayToggle(label: "天數",
                             isOn: model.displaySettings.profile.showDayCount,
                             isDisabled: model.displaySettings.isShowDayCountToggleDisabled) {
                    model.displaySettings.setShowDayCount($0)
                }
                displayToggle(label: "日期",
                             isOn: model.displaySettings.profile.showDate,
                             isDisabled: model.displaySettings.isShowDateToggleDisabled) {
                    model.displaySettings.setShowDate($0)
                }
                displayToggle(label: "名稱",
                             isOn: model.displaySettings.profile.showName,
                             isDisabled: false) {
                    model.displaySettings.setShowName($0)
                }
                Spacer(minLength: 0)
            }
            if model.displaySettings.isShowDayCountToggleDisabled || model.displaySettings.isShowDateToggleDisabled {
                Text(DisplaySettingsModel.mustShowAtLeastOneMessage)
                    .font(.footnote)
                    .foregroundColor(CameraTheme.inkSecondary)
            }
        }
    }

    private func displayToggle(label: String,
                               isOn: Bool,
                               isDisabled: Bool,
                               onChange: @escaping (Bool) -> Void) -> some View {
        VStack(spacing: 4) {
            Text(label).font(.footnote).foregroundColor(CameraTheme.ink)
            Toggle("", isOn: Binding(get: { isOn }, set: onChange))
                .labelsHidden()
                .disabled(isDisabled)
        }
        .opacity(isDisabled ? 0.4 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }

    // MARK: - 天數格式 (FR-11.3, FR-11.4, FR-11.5)

    private var dayCountFormatSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ForEach(DisplayUnit.allCases, id: \.self) { unit in
                    unitCheckbox(unit)
                }
                Spacer(minLength: 0)
            }
            HStack {
                Spacer(minLength: 0)
                ageWordingToggle
            }
            if model.displaySettings.isDayCountFormatSectionDisabled {
                Text(FormatTabModel.dayCountFormatHiddenHintMessage)
                    .font(.footnote)
                    .foregroundColor(CameraTheme.inkSecondary)
            }
        }
        .opacity(model.displaySettings.isDayCountFormatSectionDisabled ? 0.4 : 1)
        .disabled(model.displaySettings.isDayCountFormatSectionDisabled)
    }

    private func unitCheckbox(_ unit: DisplayUnit) -> some View {
        let isChecked = model.displaySettings.profile.displayUnits.contains(unit)
        let isDisabled = model.displaySettings.isUnitToggleDisabled(unit)
        return Button {
            model.displaySettings.toggleUnit(unit)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                    .foregroundColor(isChecked ? CameraTheme.active : CameraTheme.inkTertiary)
                Text(unitName(unit)).font(.footnote).foregroundColor(CameraTheme.ink)
            }
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
        .accessibilityAddTraits(isChecked ? [.isSelected] : [])
    }

    private var ageWordingToggle: some View {
        HStack(spacing: 6) {
            Text("年改成歲").font(.footnote).foregroundColor(CameraTheme.ink)
            Toggle("", isOn: Binding(get: { model.displaySettings.profile.useAgeWording },
                                     set: { model.displaySettings.setUseAgeWording($0) }))
                .labelsHidden()
                .disabled(model.displaySettings.isAgeWordingToggleDisabled)
        }
        .opacity(model.displaySettings.isAgeWordingToggleDisabled ? 0.4 : 1)
    }

    private func unitName(_ unit: DisplayUnit) -> String {
        switch unit {
        case .year: return "年"
        case .month: return "月"
        case .week: return "週"
        case .day: return "天"
        }
    }
}

// MARK: - Preview

@MainActor
private func previewModel(displayUnits: Set<DisplayUnit> = [.day], showDayCount: Bool = true) -> FormatTabModel {
    let profile = CameraProfile(name: "小寶",
                               startDate: DateComponents(year: 2026, month: 1, day: 1),
                               showDayCount: showDayCount,
                               displayUnits: displayUnits)
    let displaySettings = DisplaySettingsModel(profile: profile) { _ in }
    return FormatTabModel(displaySettings: displaySettings)
}

#Preview("顯示內容 · iPhone SE 寬度 (375pt)") {
    FormatTabView(model: previewModel())
        .frame(width: 375)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
}

#Preview("天數格式（只勾天） · iPhone SE 寬度 (375pt)") {
    let model = previewModel()
    model.selectedSubTab = .dayCountFormat
    return FormatTabView(model: model)
        .frame(width: 375)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
}

#Preview("天數格式（勾年月週天） · iPhone SE 寬度 (375pt)") {
    let model = previewModel(displayUnits: [.year, .month, .week, .day])
    model.selectedSubTab = .dayCountFormat
    return FormatTabView(model: model)
        .frame(width: 375)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
}

#Preview("天數關閉 · iPhone SE 寬度 (375pt)") {
    let model = previewModel(showDayCount: false)
    model.selectedSubTab = .dayCountFormat
    return FormatTabView(model: model)
        .frame(width: 375)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
}
