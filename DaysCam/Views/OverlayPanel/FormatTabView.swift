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
/// sections now sit on one page. #558: one card per thing on the photo —
/// 文字內容 (天數、日期、名稱), 天數單位 (units, 「年」改成「歲」) and 戳記
/// (底片日期 and its corner). With the day count off the 天數單位 card is
/// not shown; the switches above it stay put.
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
    /// Height of a card's heading line. The refusal hint shows at its
    /// trailing end (#558), so the line keeps this height whether or not the
    /// hint is up and showing it never moves a row (108.2).
    static let headingHeight: CGFloat = 20

    /// Card background (#558). Kept here rather than in `CameraTheme`, which
    /// has no card token yet.
    private static let cardBackground = Color.white
    /// Hairline between rows inside a card.
    private static let rowSeparator = CameraTheme.ink.opacity(0.1)
    /// The film date stamp's own orange, for the corner icons.
    private static let stampColor = Color(red: FilmDateStamp.Metrics.red,
                                          green: FilmDateStamp.Metrics.green,
                                          blue: FilmDateStamp.Metrics.blue)

    /// The unit whose checkbox is bouncing right now (TASK-108).
    @State private var bouncingUnit: DisplayUnit?
    /// The content switch bouncing right now (TASK-108).
    @State private var bouncingSwitch: DisplaySettingsModel.Rejection.ContentSwitch?
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
        // One card per thing on the photo (#558): 文字內容, 天數單位 and
        // 戳記, each a heading over a white card whose rows all put the words
        // on the left and the control on the right.
        VStack(alignment: .leading, spacing: 0) {
            heading("文字內容", hint: contentHint, hintIdentifier: "contentSwitchHint", topPadding: 0)
            contentCard
            // Collapsed, heading and all, while the day count is off
            // (TASK-141 #485): the switch that brings it back sits above, so
            // nothing jumps under the finger. The checked units are kept in
            // the profile meanwhile.
            if model.displaySettings.profile.showDayCount {
                VStack(alignment: .leading, spacing: 0) {
                    heading("天數單位", hint: unitHint, hintIdentifier: "unitHint")
                    dayCountUnitsCard
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("dayCountUnits")
            }
            heading("戳記")
            stampCard
            Text("底片日期的字樣固定，不受「樣式」「位置」分頁影響。")
                .font(.system(size: 12))
                .foregroundColor(CameraTheme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
                .padding(.top, 5)
                .accessibilityIdentifier("stampNote")
        }
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

    // MARK: - Cards

    /// A card's heading (13pt, secondary ink) with room for a refusal hint
    /// at its trailing end. The line is always `headingHeight` tall, so the
    /// hint coming and going never moves a row (108.2).
    private func heading(_ title: String,
                         hint: DisplaySettingsModel.Rejection? = nil,
                         hintIdentifier: String? = nil,
                         topPadding: CGFloat = 12) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(CameraTheme.inkSecondary)
            Spacer(minLength: 0)
            if let hintIdentifier {
                Text(hint?.hint ?? " ")
                    .font(.system(size: 13))
                    .foregroundColor(CameraTheme.active)
                    .lineLimit(1)
                    .opacity(hint == nil ? 0 : 1)
                    .animation(.easeOut(duration: hint == nil ? 0.3 : 0.2), value: hint?.serial)
                    .accessibilityHidden(hint == nil)
                    .accessibilityIdentifier(hintIdentifier)
            }
        }
        .frame(height: Self.headingHeight)
        .padding(.horizontal, 4)
        .padding(.top, topPadding)
        .padding(.bottom, 5)
    }

    /// White rounded card holding `rows`, separated by hairlines.
    private func card<Content: View>(identifier: String,
                                     @ViewBuilder rows: () -> Content) -> some View {
        VStack(spacing: 0) {
            rows()
        }
        .padding(.horizontal, 12)
        .background(Self.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    /// The 1pt line between two rows of a card.
    private var rowDivider: some View {
        Rectangle().fill(Self.rowSeparator).frame(height: 1)
    }

    // MARK: - 文字內容 (FR-11.1, FR-11.2)

    private var contentCard: some View {
        // None is ever disabled: the last of 天數／日期 refuses to turn off
        // in the model, so the switch springs back (107.3; TASK-108 adds
        // the feedback).
        card(identifier: "contentCard") {
            switchRow("天數", isOn: model.displaySettings.profile.showDayCount,
                      isBouncing: bouncingSwitch == .dayCount) {
                model.displaySettings.setShowDayCount($0)
            }
            rowDivider
            switchRow("日期", isOn: model.displaySettings.profile.showDate,
                      isBouncing: bouncingSwitch == .date) {
                model.displaySettings.setShowDate($0)
            }
            rowDivider
            switchRow("名稱", isOn: model.displaySettings.profile.showName) {
                model.displaySettings.setShowName($0)
            }
        }
    }

    /// Words on the left, switch on the right, so every switch in the tab
    /// ends on the card's inner edge (#558).
    private func switchRow(_ label: String,
                           isOn: Bool,
                           isBouncing: Bool = false,
                           onChange: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 8) {
            // The switch carries the label for VoiceOver, so the visible
            // words are left out of the tree rather than read twice.
            Text(label)
                .font(.subheadline)
                .foregroundColor(CameraTheme.ink)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            // #F0A64A, not the system default green (PRD FR-14, #114).
            Toggle(label, isOn: Binding(get: { isOn }, set: onChange))
                .tint(CameraTheme.accentControl)
                .labelsHidden()
                .scaleEffect(isBouncing ? 1.12 : 1)
        }
        .frame(minHeight: Self.rowMinHeight)
    }

    // MARK: - 天數單位 (FR-11.3–FR-11.5)

    private var dayCountUnitsCard: some View {
        card(identifier: "dayCountUnitsCard") {
            // Four equal columns, each checkbox centered in its own.
            HStack(spacing: 0) {
                ForEach(DisplayUnit.allCases, id: \.self) { unit in
                    unitCheckbox(unit).frame(maxWidth: .infinity)
                }
            }
            .frame(minHeight: Self.rowMinHeight)
            rowDivider
            // Always enabled, never dimmed, whatever is checked: it renames
            // the year checkbox instead (TASK-139 #486).
            switchRow("「年」改成「歲」", isOn: model.displaySettings.profile.useAgeWording) {
                model.displaySettings.setUseAgeWording($0)
            }
        }
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

    // MARK: - 戳記 (#521, #558)

    private var stampCard: some View {
        card(identifier: "stampCard") {
            switchRow("底片日期", isOn: model.displaySettings.profile.showFilmDate) {
                model.displaySettings.setShowFilmDate($0)
            }
            // Collapsed while off; the chosen corner stays in the profile.
            if model.displaySettings.profile.showFilmDate {
                rowDivider
                cornerRow
            }
        }
    }

    /// The four corners in one row, each a tiny photo with the stamp drawn
    /// in that corner.
    private var cornerRow: some View {
        HStack(spacing: 6) {
            ForEach([FilmDateCorner.topLeading, .topTrailing, .bottomLeading, .bottomTrailing], id: \.self) {
                cornerButton($0)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 10)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("filmDateCorners")
    }

    private func cornerButton(_ corner: FilmDateCorner) -> some View {
        let isSelected = model.displaySettings.profile.filmDateCorner == corner
        let name = Self.cornerName(corner)
        return Button {
            model.displaySettings.setFilmDateCorner(corner)
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: Self.alignment(of: corner)) {
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(CameraTheme.ink.opacity(0.35), lineWidth: 1)
                    // Lies the way the stamp does on the photo: across where
                    // the corner draws it unturned, upright where turned.
                    let upright = corner.rotation != 0
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Self.stampColor)
                        .frame(width: upright ? 4 : 11, height: upright ? 11 : 4)
                        .padding(3)
                }
                .frame(width: 34, height: 26)
                Text(name)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(CameraTheme.ink)
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: Self.rowMinHeight)
            .background(isSelected ? CameraTheme.active.opacity(0.08) : .clear,
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10).strokeBorder(CameraTheme.active, lineWidth: 1.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("底片日期位置，\(name)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
        .accessibilityIdentifier("filmDateCorner_\(corner.rawValue)")
    }

    private static func alignment(of corner: FilmDateCorner) -> Alignment {
        switch corner {
        case .topLeading: return .topLeading
        case .topTrailing: return .topTrailing
        case .bottomLeading: return .bottomLeading
        case .bottomTrailing: return .bottomTrailing
        }
    }

    private static func cornerName(_ corner: FilmDateCorner) -> String {
        switch corner {
        case .topLeading: return "左上"
        case .topTrailing: return "右上"
        case .bottomLeading: return "左下"
        case .bottomTrailing: return "右下"
        }
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
