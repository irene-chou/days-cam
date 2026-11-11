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
/// 文字內容 (天數、日期、名稱, 位置, 寫法); the 戳記 card (底片日期 and its
/// corner) moved to its own layer page, `FilmDateDetailView` (#718). The
/// day-count units and 「年」改成「歲」 moved to the record edit page (#721).
/// With the day count off the 寫法 row is not shown. #567: with a
/// `positionTabModel` the card has a 位置 row that opens the nine-point
/// grid in place.
/// `ContentTabView` hosts this view as its whole page.
struct FormatTabView: View {
    @ObservedObject var model: FormatTabModel

    /// Whether this view adds its own `.tabbody` inset (12 vertical, 14
    /// horizontal). `ContentTabView` turns it off and applies the same inset
    /// once around both sub-tabs.
    var appliesOuterPadding: Bool = true

    /// The text's position, shown as the 文字內容 card's last row (#567).
    /// `nil` leaves the row out.
    var positionTabModel: PositionTabModel?

    /// Minimum height of every content row (display toggles, 位置, 寫法), the same 44pt tap target the rules
    /// tab uses (#116, Z.8).
    static let rowMinHeight: CGFloat = 44
    /// Card background (#558). Kept here rather than in `CameraTheme`, which
    /// has no card token yet.
    private static let cardBackground = Color.white
    /// Hairline between rows inside a card.
    private static let rowSeparator = CameraTheme.ink.opacity(0.1)

    var body: some View {
        // One card for the words on the photo (#558): heading over a white
        // card whose rows all put the words on the left and the control on
        // the right.
        VStack(alignment: .leading, spacing: 0) {
            heading("文字內容")
            contentCard
        }
        // This tab's own `.tabbody` outer inset (`.tabbody{padding:12px 14px}`,
        // #106 R2): each tab owns its own padding rather than a generic one.
        .padding(.vertical, appliesOuterPadding ? 12 : 0)
        .padding(.horizontal, appliesOuterPadding ? 14 : 0)
    }

    // MARK: - Cards

    /// A card's heading (13pt, secondary ink).
    private func heading(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13))
            .foregroundColor(CameraTheme.inkSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
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

    // MARK: - 文字內容 (FR-11.1)

    private var contentCard: some View {
        // Any switch may be turned off, all three included: the overlay is
        // then empty (#713).
        card(identifier: "contentCard") {
            switchRow("天數", isOn: model.displaySettings.profile.showDayCount) {
                model.displaySettings.setShowDayCount($0)
            }
            rowDivider
            switchRow("日期", isOn: model.displaySettings.profile.showDate) {
                model.displaySettings.setShowDate($0)
            }
            rowDivider
            switchRow("名稱", isOn: model.displaySettings.profile.showName) {
                model.displaySettings.setShowName($0)
            }
            if let positionTabModel {
                rowDivider
                PositionRows(model: positionTabModel)
            }
            // Hidden while the day count is off: the wording has nothing to
            // format then (was the 天數單位 card's collapse, FR-11.5).
            if model.displaySettings.profile.showDayCount {
                rowDivider
                DayCountFormatRows(model: model.displaySettings)
            }
        }
    }

    /// Words on the left, switch on the right, so every switch in the tab
    /// ends on the card's inner edge (#558).
    private func switchRow(_ label: String,
                           isOn: Bool,
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
        }
        .frame(minHeight: Self.rowMinHeight)
    }
}

// MARK: - 位置 (#567)

/// The 文字內容 card's 位置 row: the position's name and a chevron, opening
/// the nine-point grid and the drag hint right under it. Its own view so it
/// observes `PositionTabModel`, which also follows drags on the viewfinder.
private struct PositionRows: View {
    @ObservedObject var model: PositionTabModel

    /// Fixed here, unlike the 位置 tab's box: the card scrolls, so it no
    /// longer has to fit the panel's height. 88pt is what the tab worked out
    /// to on iPhone SE (`PositionTabModel.gridBoxSide(forAvailableHeight: 104)`).
    static let gridSide: CGFloat = 88

    /// Not remembered: the row opens closed every time the tab shows.
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Text("位置")
                        .font(.subheadline)
                        .foregroundColor(CameraTheme.ink)
                    Spacer(minLength: 0)
                    Text(model.positionName)
                        .font(.subheadline)
                        .foregroundColor(CameraTheme.inkSecondary)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(CameraTheme.inkSecondary)
                }
                .frame(minHeight: FormatTabView.rowMinHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            // "位置" alone is the 位置 tab's label, so the name rides in the
            // label too (and keeps the two apart in UI tests).
            .accessibilityLabel("位置，\(model.positionName)")
            .accessibilityValue(isExpanded ? "已展開" : "已收起")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("positionRow")

            if isExpanded {
                HStack(alignment: .center, spacing: 14) {
                    PositionGridView(model: model, side: Self.gridSide)
                    Text(PositionTabModel.dragHintMessage)
                        .font(.caption)
                        .foregroundColor(CameraTheme.inkSecondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.bottom, 12)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("positionExpanded")
            }
        }
        // A failed position save is reported by `OverlayPanelView`
        // (`PositionSaveErrorHost`), since a drag on 樣式 writes it too (#568).
    }
}

// MARK: - 寫法 (#583)

/// The 文字內容 card's 寫法 row: the current wording and a chevron, opening
/// the four wordings right under it. Built like `PositionRows`.
private struct DayCountFormatRows: View {
    @ObservedObject var model: DisplaySettingsModel

    /// Not remembered: the row opens closed every time the tab shows.
    @State private var isExpanded = false

    /// The panel's name for a wording.
    static func formatName(_ format: DayCountFormat) -> String {
        switch format {
        case .ordinal: return "第 N 天"
        case .plain: return "N 天"
        case .dayN: return "Day N"
        case .dDay: return "D-Day"
        }
    }

    /// A fixed example, so the panel never reads the clock.
    static func formatExample(_ format: DayCountFormat) -> String {
        switch format {
        case .ordinal: return "第 12 天"
        case .plain: return "12 天"
        case .dayN: return "Day 12"
        case .dDay: return "D+12 ／ D-7"
        }
    }

    static let otherUnitsNote = "勾了週、月或年時，天數照中文單位寫法印，例如「1 週又 5 天」。只勾「天」時才套用寫法。"

    /// The wording only shows on the overlay while day is the only unit.
    private var isApplied: Bool { model.profile.displayUnits == [.day] }

    var body: some View {
        let current = model.profile.dayCountFormat
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Text("寫法")
                        .font(.subheadline)
                        .foregroundColor(CameraTheme.ink)
                    Spacer(minLength: 0)
                    Text(Self.formatName(current))
                        .font(.subheadline)
                        .foregroundColor(isApplied ? CameraTheme.inkSecondary : CameraTheme.inkTertiary)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(CameraTheme.inkSecondary)
                }
                .frame(minHeight: FormatTabView.rowMinHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("寫法，\(Self.formatName(current))")
            .accessibilityValue(isExpanded ? "已展開" : "已收起")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("dayCountFormatRow")

            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(DayCountFormat.allCases, id: \.self) { format in
                        option(format, isSelected: format == current)
                    }
                    if !isApplied {
                        Text(Self.otherUnitsNote)
                            .font(.caption)
                            .foregroundColor(CameraTheme.inkSecondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                            .accessibilityIdentifier("dayCountFormatNote")
                    }
                }
                .padding(.bottom, 8)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("dayCountFormatExpanded")
            }
        }
    }

    private func option(_ format: DayCountFormat, isSelected: Bool) -> some View {
        let name = Self.formatName(format)
        let example = Self.formatExample(format)
        let ink = isApplied ? CameraTheme.ink : CameraTheme.inkTertiary
        return Button {
            model.setDayCountFormat(format)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isApplied ? CameraTheme.active : CameraTheme.inkTertiary)
                    .opacity(isSelected ? 1 : 0)
                    .frame(width: 18)
                Text(name)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .foregroundColor(ink)
                Spacer(minLength: 8)
                Text(example)
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(isApplied ? CameraTheme.inkSecondary : CameraTheme.inkTertiary)
                    .multilineTextAlignment(.trailing)
            }
            .frame(minHeight: FormatTabView.rowMinHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name)，\(example)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
        .accessibilityIdentifier("dayCountFormat_\(format.rawValue)")
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

#Preview("含位置列 · iPhone SE 寬度 (375pt)") {
    let profile = CameraProfile(name: "小寶", startDate: DateComponents(year: 2026, month: 1, day: 1))
    return FormatTabView(model: previewModel(),
                         positionTabModel: PositionTabModel(profile: profile) { _ in })
        .frame(width: 375)
        .background(Color(.systemBackground))
}

#Preview("勾年月週天 · iPhone SE 寬度 (375pt)") {
    FormatTabView(model: previewModel(displayUnits: [.year, .month, .week, .day]))
        .frame(width: 375)
        .background(Color(.systemBackground))
}
