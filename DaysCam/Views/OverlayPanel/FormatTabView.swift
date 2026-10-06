import SwiftUI

/// The 格式 (format) tab of the overlay panel (PRD 0.2 FR-11, D-4).
///
/// Stands alone on purpose, like `StyleTabView`/`RulesTabView`: the panel
/// shell and its first-layer segmented control are `ui-shell`'s (TASK-22),
/// which had not landed when this was written. Once it does, `ui-shell`
/// drops this view into the panel body for the 格式 segment, passing in a
/// `FormatTabModel` wrapping the active profile's `DisplaySettingsModel`.
///
/// TASK-38 (0.3): the old second layer (顯示內容｜天數格式) is gone — both
/// sections now sit on one page: 天數格式 on top, 顯示內容 below under a small heading.
/// `ContentTabView` hosts this view as its 格式 sub-tab.
struct FormatTabView: View {
    @ObservedObject var model: FormatTabModel

    /// Whether this view adds its own `.tabbody` inset (12 vertical, 14
    /// horizontal). `ContentTabView` turns it off and applies the same inset
    /// once around both sub-tabs.
    var appliesOuterPadding: Bool = true

    /// Minimum height of every content row (display toggles, unit
    /// checkboxes, age-wording toggle), the same 44pt tap target the rules
    /// tab uses (#116, Z.8).
    static let rowMinHeight: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            dayCountFormatSection
            sectionHeading("顯示內容")
                .padding(.top, 8)
            displayContentSection
        }
        // This tab's own `.tabbody` outer inset (`.tabbody{padding:12px 14px}`,
        // #106 R2): each tab owns its own padding rather than a generic one.
        .padding(.vertical, appliesOuterPadding ? 12 : 0)
        .padding(.horizontal, appliesOuterPadding ? 14 : 0)
        .alert("無法儲存", isPresented: Binding(get: { model.displaySettings.lastError != nil },
                                             set: { if !$0 { model.displaySettings.lastError = nil } })) {
            Button("好") { model.displaySettings.lastError = nil }
        } message: {
            Text("請再試一次。")
        }
    }

    /// Small heading above the 顯示內容 section (TASK-38 A: 13pt, secondary ink; 天數格式 has none).
    private func sectionHeading(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13))
            .foregroundColor(CameraTheme.inkSecondary)
            .padding(.bottom, 2)
    }

    // MARK: - 顯示內容 (FR-11.1, FR-11.2)

    private var displayContentSection: some View {
        // No gap between rows: each row is at least `rowMinHeight` tall with
        // its content vertically centered, matching the rules tab's rhythm
        // (#116, the human's 2026-09-30 call — replaces the earlier 12pt row
        // gap, which still left rows ~28pt tall and read as cramped).
        VStack(alignment: .leading, spacing: 0) {
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
            .frame(minHeight: Self.rowMinHeight)
            if model.displaySettings.isShowDayCountToggleDisabled || model.displaySettings.isShowDateToggleDisabled {
                Text(DisplaySettingsModel.mustShowAtLeastOneMessage)
                    .font(.footnote)
                    .foregroundColor(CameraTheme.inkSecondary)
                    .padding(.top, 4)
            }
        }
    }

    private func displayToggle(label: String,
                               isOn: Bool,
                               isDisabled: Bool,
                               onChange: @escaping (Bool) -> Void) -> some View {
        // Label beside the switch, not above it (`.swr{display:flex;
        // align-items:center;gap:6px}`, #106 — was a `VStack` with the
        // label stacked on top and a 4pt gap). Label size/gap: #116 方案②
        // (15pt `.subheadline`, 8pt gap — was `.footnote`/6pt, sized against
        // #106's own guess rather than the native 51×31 `Toggle` the human
        // decided to keep, #116's whole point).
        HStack(spacing: 8) {
            Text(label).font(.subheadline).foregroundColor(CameraTheme.ink)
            // #F0A64A, not the system default green (PRD FR-14, #114).
            Toggle("", isOn: Binding(get: { isOn }, set: onChange))
                .tint(CameraTheme.accentControl)
                .labelsHidden()
                .disabled(isDisabled)
        }
        .opacity(isDisabled ? 0.4 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }

    // MARK: - 天數格式 (FR-11.3, FR-11.4, FR-11.5)

    private var dayCountFormatSection: some View {
        // No gap between rows; each row is at least `rowMinHeight` tall and
        // vertically centered (#116, 2026-09-30) — see `displayContentSection`.
        VStack(alignment: .leading, spacing: 0) {
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
            .frame(minHeight: Self.rowMinHeight)
            HStack {
                Spacer(minLength: 0)
                ageWordingToggle
            }
            .frame(minHeight: Self.rowMinHeight)
            if model.displaySettings.isDayCountFormatSectionDisabled {
                Text(FormatTabModel.dayCountFormatHiddenHintMessage)
                    .font(.footnote)
                    .foregroundColor(CameraTheme.inkSecondary)
                    .padding(.top, 4)
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
            // Checkbox icon/label size and gap: #116 方案②（20pt icon, 15pt
            // `.subheadline` label, 8pt gap — was unset-size (inherited
            // ~17pt body), `.footnote`, 6pt gap, #106's own guess).
            HStack(spacing: 8) {
                // Checked uses #F0A64A, the switch/checkbox "on" token, not
                // `active` — that's a darker orange reserved for selection
                // highlights elsewhere (PRD FR-14, #114).
                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20))
                    .foregroundColor(isChecked ? CameraTheme.accentControl : CameraTheme.inkTertiary)
                Text(unitName(unit)).font(.subheadline).foregroundColor(CameraTheme.ink)
            }
            .frame(minHeight: Self.rowMinHeight)
            .contentShape(Rectangle())
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
        .accessibilityAddTraits(isChecked ? [.isSelected] : [])
    }

    private var ageWordingToggle: some View {
        // #116 方案②（15pt `.subheadline`, 8pt gap） — was `.footnote`/6pt.
        HStack(spacing: 8) {
            Text("年改成歲").font(.subheadline).foregroundColor(CameraTheme.ink)
            // #F0A64A, not the system default green (PRD FR-14, #114).
            Toggle("", isOn: Binding(get: { model.displaySettings.profile.useAgeWording },
                                     set: { model.displaySettings.setUseAgeWording($0) }))
                .tint(CameraTheme.accentControl)
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

#Preview("格式頁 · iPhone SE 寬度 (375pt)") {
    FormatTabView(model: previewModel())
        .frame(width: 375)
        .background(Color(.systemBackground))
}

#Preview("勾年月週天 · iPhone SE 寬度 (375pt)") {
    FormatTabView(model: previewModel(displayUnits: [.year, .month, .week, .day]))
        .frame(width: 375)
        .background(Color(.systemBackground))
}

#Preview("天數關閉 · iPhone SE 寬度 (375pt)") {
    FormatTabView(model: previewModel(showDayCount: false))
        .frame(width: 375)
        .background(Color(.systemBackground))
}
