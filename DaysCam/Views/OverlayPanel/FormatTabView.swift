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
        // No gap of its own between `subTabRow` and `content` (#106): the
        // design's `.subA{padding:6px 4px 4px}` + `.pane{...}` (no margin)
        // puts the whole visual gap inside `subTabRow`'s own bottom padding
        // instead — see that view's `.padding(.top:.bottom:)`.
        VStack(alignment: .leading, spacing: 0) {
            subTabRow
            content
        }
        // This tab's own `.tabbody` outer inset — the generic D-4 value
        // (`.tabbody{padding:12px 14px}`, #106 R2, the human's 2026-09-27
        // call: each tab owns its own `.tabbody` padding rather than a
        // generic one shared by all four — `ui-shell` is dropping the panel
        // container's own generic inset in #105 to avoid stacking both).
        // Was a flat `.padding(.horizontal, 16)` with no vertical inset.
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .alert("無法儲存", isPresented: Binding(get: { model.displaySettings.lastError != nil },
                                             set: { if !$0 { model.displaySettings.lastError = nil } })) {
            Button("好") { model.displaySettings.lastError = nil }
        } message: {
            Text("請再試一次。")
        }
    }

    // MARK: - 第二層：顯示內容｜天數格式 (FR-8.5, 24.1)

    private var subTabRow: some View {
        // 16pt gap, left-aligned, unselected uses the tertiary/t3 shade
        // (design A, `D4-format-position-rules.html`'s `.subA{gap:16px}` —
        // #106, was 14pt gap with the same shade).
        HStack(spacing: 16) {
            ForEach(FormatTabModel.SubTab.allCases, id: \.self) { subTab in
                let isSelected = model.selectedSubTab == subTab
                Button {
                    model.selectedSubTab = subTab
                } label: {
                    Text(subTab.title)
                        .font(CameraTheme.toolFont(.subheadline))
                        .foregroundColor(isSelected ? CameraTheme.active : CameraTheme.inkTertiary)
                }
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        // `.subA{padding:6px 4px 4px}` — the 4px horizontal half is folded
        // into the body's own `.tabbody` padding already (#106).
        .padding(.top, 6)
        .padding(.bottom, 4)
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
        // `.cbrow`/`.swrow`-style gap between the toggle row and the hint
        // text below it: the design leaves it at the default block-flow
        // margin (0), not restated as a token anywhere in D-4 — 6pt here is
        // this view's own judgment call, not a design value (#106, "待人類
        // 決定" if 0 reads too tight in a screenshot).
        VStack(alignment: .leading, spacing: 6) {
            // The three toggles spread evenly across the full row, CSS
            // `space-around` exactly (`.swrow{justify-content:space-around}`,
            // #106 R3 — was a fixed 28pt gap): two consecutive plain
            // `Spacer`s between items occupy exactly double the width of the
            // lone `Spacer` at each edge (`HStack` gives every flexible
            // child an equal share of the leftover space, so N instances
            // together always claim N times what one does) — precisely
            // `space-around`'s "full gap between items, half a gap at each
            // edge" rhythm, not an approximation.
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                displayToggle(label: "天數",
                             isOn: model.displaySettings.profile.showDayCount,
                             isDisabled: model.displaySettings.isShowDayCountToggleDisabled) {
                    model.displaySettings.setShowDayCount($0)
                }
                Spacer(minLength: 0)
                Spacer(minLength: 0)
                displayToggle(label: "日期",
                             isOn: model.displaySettings.profile.showDate,
                             isDisabled: model.displaySettings.isShowDateToggleDisabled) {
                    model.displaySettings.setShowDate($0)
                }
                Spacer(minLength: 0)
                Spacer(minLength: 0)
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
        // Label beside the switch, not above it (`.swr{display:flex;
        // align-items:center;gap:6px}`, #106 — was a `VStack` with the
        // label stacked on top and a 4pt gap).
        HStack(spacing: 6) {
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
        // `.cbrow{padding:4px 0 2px}` + `.frow2{padding:2px 10px 0}` leave
        // only ~4pt of gap between the two rows via block-flow (#106, was
        // 12 — no design token names this gap directly, so 4 is this view's
        // own reading of those two paddings, not a restated design value).
        VStack(alignment: .leading, spacing: 4) {
            // Evenly spread, CSS `space-around` exactly
            // (`.cbrow{justify-content:space-around}`, #106 R3 — was a fixed
            // 14pt gap): see `displayContentSection` above for why two
            // consecutive `Spacer`s between items, one at each edge, is
            // `space-around` exactly rather than an approximation.
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                ForEach(Array(DisplayUnit.allCases.enumerated()), id: \.offset) { index, unit in
                    if index > 0 {
                        Spacer(minLength: 0)
                        Spacer(minLength: 0)
                    }
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
            // `.cb{gap:6px}` (#106) — was 4.
            HStack(spacing: 6) {
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
