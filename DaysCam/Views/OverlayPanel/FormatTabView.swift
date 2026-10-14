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
/// sections now sit on one page. TASK-141 (#485): 顯示內容 (天數、日期、
/// 名稱) on top, then a divider and 天數單位 (units, 年改成歲) — what goes on
/// the photo first, then how the day count reads. With the day count off
/// the 天數單位 section is not shown; the switches above it stay put.
/// `ContentTabView` hosts this view as its whole page.
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
    /// Height reserved under the unit row and under the display-content row
    /// for the refusal hint (TASK-108): always laid out, normally invisible,
    /// so showing the hint never moves the rows below it (108.2).
    static let hintRowHeight: CGFloat = 20

    /// The unit whose checkbox is bouncing right now (TASK-108).
    @State private var bouncingUnit: DisplayUnit?
    /// The content switch bouncing right now (TASK-108).
    @State private var bouncingSwitch: DisplaySettingsModel.Rejection.ContentSwitch?
    /// The tab's content width and the 名稱 switch's trailing x in it, so
    /// 年改成歲 can end on the same right edge (TASK-141 #485): the switch
    /// row is spread `space-around`, so its last switch sits half a gap in
    /// from the edge, and that gap depends on the width.
    @State private var contentWidth: CGFloat = 0
    @State private var nameSwitchMaxX: CGFloat = 0
    private static let coordinateSpace = "formatTab"
    /// Trailing inset that puts 年改成歲's right edge under 名稱's.
    private var switchTrailingInset: CGFloat {
        guard contentWidth > 0, nameSwitchMaxX > 0 else { return 0 }
        return max(0, contentWidth - nameSwitchMaxX)
    }
    /// The refusal whose hint is showing under the unit row, if any (the
    /// model owns the hint's lifetime; see `DisplaySettingsModel.visibleHint`).
    private var unitHint: DisplaySettingsModel.Rejection? {
        guard let hint = model.displaySettings.visibleHint else { return nil }
        if case .lastUnit = hint.kind { return hint }
        return nil
    }
    /// The refusal whose hint is showing under the display-content row, if any.
    private var contentHint: DisplaySettingsModel.Rejection? {
        guard let hint = model.displaySettings.visibleHint else { return nil }
        if case .lastContentSwitch = hint.kind { return hint }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeading("顯示內容")
            displayContentSection
            // Collapsed, not dimmed, while the day count is off (TASK-141
            // #485, replacing FR-11.5's "look as usual"): the switch that
            // brings it back sits right above, so nothing jumps under the
            // finger. The checked units are kept in the profile meanwhile.
            if model.displaySettings.profile.showDayCount {
                Divider()
                    .padding(.vertical, 8)
                    .accessibilityIdentifier("formatDivider")
                sectionHeading("天數單位")
                dayCountFormatSection
            }
        }
        .coordinateSpace(name: Self.coordinateSpace)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { contentWidth = $0 }
        // This tab's own `.tabbody` outer inset (`.tabbody{padding:12px 14px}`,
        // #106 R2): each tab owns its own padding rather than a generic one.
        .padding(.vertical, appliesOuterPadding ? 12 : 0)
        .padding(.horizontal, appliesOuterPadding ? 14 : 0)
        // A refused change (the last unit, the last of 天數／日期) bounces
        // the control, taps the haptic engine and shows a hint until the
        // next tap here (TASK-108 #422, TASK-141 #485; FR-11.2／FR-11.3). On
        // the simulator the haptic is simply absent (108.6).
        .onChange(of: model.displaySettings.lastRejection) { _, rejection in
            guard let rejection else { return }
            react(to: rejection)
        }
        .sensoryFeedback(.warning, trigger: model.displaySettings.lastRejection)
        // Switching to another tab (or closing the panel) ends the hint
        // too (141.4).
        .onDisappear { model.displaySettings.dismissHint() }
        .alert("無法儲存", isPresented: Binding(get: { model.displaySettings.lastError != nil },
                                             set: { if !$0 { model.displaySettings.lastError = nil } })) {
            Button("好") { model.displaySettings.lastError = nil }
        } message: {
            Text("請再試一次。")
        }
    }

    /// Bounce, hint and VoiceOver announcement for one refusal (TASK-108).
    private func react(to rejection: DisplaySettingsModel.Rejection) {
        let bounce = Animation.spring(response: 0.3, dampingFraction: 0.35)
        switch rejection.kind {
        case .lastUnit(let unit):
            withAnimation(bounce) { bouncingUnit = unit }
        case .lastContentSwitch(let contentSwitch):
            withAnimation(bounce) { bouncingSwitch = contentSwitch }
        }
        UIAccessibility.post(notification: .announcement, argument: rejection.hint)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.easeOut(duration: 0.15)) {
                bouncingUnit = nil
                bouncingSwitch = nil
            }
        }
    }

    /// The reserved hint line under a row: its text is only visible while
    /// `rejection` is set, and the line keeps its height either way (108.2).
    private func hintRow(_ rejection: DisplaySettingsModel.Rejection?, identifier: String) -> some View {
        Text(rejection?.hint ?? " ")
            .font(.system(size: 13))
            .foregroundColor(CameraTheme.active)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: Self.hintRowHeight)
            .padding(.leading, 8)
            .opacity(rejection == nil ? 0 : 1)
            .animation(.easeOut(duration: rejection == nil ? 0.3 : 0.2), value: rejection?.serial)
            .accessibilityHidden(rejection == nil)
            .accessibilityIdentifier(identifier)
    }

    /// Small heading above the 顯示內容 and 天數單位 sections (13pt, secondary ink).
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
            // The two toggles spread evenly across the full row, CSS
            // `space-around` exactly (`.swrow{justify-content:space-around}`,
            // #106 R3 — was a fixed 28pt gap): two consecutive plain
            // `Spacer`s between items occupy exactly double the width of the
            // lone `Spacer` at each edge (`HStack` gives every flexible
            // child an equal share of the leftover space, so N instances
            // together always claim N times what one does) — precisely
            // `space-around`'s "full gap between items, half a gap at each
            // edge" rhythm, not an approximation.
            // Three switches again — 天數｜日期｜名稱 (TASK-107, #426 brings
            // the day-count switch back; FR-11.1). None is ever disabled:
            // the last of 天數／日期 refuses to turn off in the model, so
            // the switch springs back (107.3; TASK-108 adds the feedback).
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                displayToggle(label: "天數",
                             isOn: model.displaySettings.profile.showDayCount,
                             isDisabled: false) {
                    model.displaySettings.setShowDayCount($0)
                }
                Spacer(minLength: 0)
                Spacer(minLength: 0)
                displayToggle(label: "日期",
                             isOn: model.displaySettings.profile.showDate,
                             isDisabled: false) {
                    model.displaySettings.setShowDate($0)
                }
                Spacer(minLength: 0)
                Spacer(minLength: 0)
                displayToggle(label: "名稱",
                             isOn: model.displaySettings.profile.showName,
                             isDisabled: false) {
                    model.displaySettings.setShowName($0)
                }
                .onGeometryChange(for: CGFloat.self,
                                  of: { $0.frame(in: .named(Self.coordinateSpace)).maxX }) { nameSwitchMaxX = $0 }
                Spacer(minLength: 0)
            }
            .frame(minHeight: Self.rowMinHeight)
            hintRow(contentHint, identifier: "contentSwitchHint")
            filmDateRow
            if model.displaySettings.profile.showFilmDate {
                filmDateCornerRow
            }
        }
    }

    // MARK: - 底片日期 (#521)

    /// The 底片日期 switch on its own row, right edge under 名稱's.
    private var filmDateRow: some View {
        HStack {
            Spacer(minLength: 0)
            displayToggleBody(label: "底片日期",
                              isOn: model.displaySettings.profile.showFilmDate,
                              isDisabled: false) {
                model.displaySettings.setShowFilmDate($0)
            }
        }
        .padding(.trailing, switchTrailingInset)
        .frame(minHeight: Self.rowMinHeight)
    }

    /// 位置 with a 2x2 corner picker; collapsed while the switch is off.
    private var filmDateCornerRow: some View {
        let corners: [[FilmDateCorner]] = [[.topLeading, .topTrailing], [.bottomLeading, .bottomTrailing]]
        return HStack(spacing: 8) {
            Text("位置").font(.subheadline).foregroundColor(CameraTheme.ink)
            Spacer(minLength: 0)
            VStack(spacing: 0) {
                ForEach(corners, id: \.first) { row in
                    HStack(spacing: 0) {
                        ForEach(row, id: \.self) { cornerButton($0) }
                    }
                }
            }
        }
        .padding(.trailing, switchTrailingInset)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("filmDateCorners")
    }

    private func cornerButton(_ corner: FilmDateCorner) -> some View {
        let isSelected = model.displaySettings.profile.filmDateCorner == corner
        let name = Self.cornerName(corner)
        return Button {
            model.displaySettings.setFilmDateCorner(corner)
        } label: {
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? CameraTheme.active : CameraTheme.inkTertiary.opacity(0.25))
                .frame(width: 28, height: 28)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("底片日期位置，\(name)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier("filmDateCorner_\(corner.rawValue)")
    }

    private static func cornerName(_ corner: FilmDateCorner) -> String {
        switch corner {
        case .topLeading: return "左上"
        case .topTrailing: return "右上"
        case .bottomLeading: return "左下"
        case .bottomTrailing: return "右下"
        }
    }

    private func displayToggle(label: String,
                               isOn: Bool,
                               isDisabled: Bool,
                               onChange: @escaping (Bool) -> Void) -> some View {
        let isBouncing = (label == "天數" && bouncingSwitch == .dayCount) || (label == "日期" && bouncingSwitch == .date)
        return displayToggleBody(label: label, isOn: isOn, isDisabled: isDisabled, onChange: onChange)
            .scaleEffect(isBouncing ? 1.12 : 1)
    }

    private func displayToggleBody(label: String,
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

    // MARK: - 天數單位 (FR-11.3–FR-11.5)

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
            hintRow(unitHint, identifier: "unitHint")
            HStack {
                Spacer(minLength: 0)
                ageWordingToggle
            }
            // Right edge aligned with the 名稱 switch above (TASK-141).
            .padding(.trailing, switchTrailingInset)
            .frame(minHeight: Self.rowMinHeight)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dayCountUnits")
    }

    private func unitCheckbox(_ unit: DisplayUnit) -> some View {
        let isChecked = model.displaySettings.profile.displayUnits.contains(unit)
        // The last checked unit looks exactly like the others (TASK-108,
        // #422): tapping it is refused by the model and answered with a
        // bounce, a haptic and a hint, instead of a dimmed, dead checkbox.
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
                    .scaleEffect(bouncingUnit == unit ? 1.3 : 1)
                Text(unitName(unit)).font(.subheadline).foregroundColor(CameraTheme.ink)
            }
            .frame(minHeight: Self.rowMinHeight)
            .contentShape(Rectangle())
        }
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
                // Always enabled, never dimmed, whatever is checked: it
                // renames the year checkbox instead (TASK-139 #486).
        }
        // One element, like the display switches, so VoiceOver reads the
        // label with the switch and a tap anywhere on the row is the switch.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("年改成歲")
    }

    /// The checkbox label; the year reads 歲 while `useAgeWording` is on,
    /// checked or not (TASK-139 #486).
    private func unitName(_ unit: DisplayUnit) -> String {
        switch unit {
        case .year: return model.displaySettings.profile.useAgeWording ? "歲" : "年"
        case .month: return "月"
        case .week: return "週"
        case .day: return "天"
        }
    }
}

// MARK: - Preview

@MainActor
private func previewModel(displayUnits: Set<DisplayUnit> = [.day]) -> FormatTabModel {
    let profile = CameraProfile(name: "小寶",
                               startDate: DateComponents(year: 2026, month: 1, day: 1),
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
