import SwiftUI

/// The 設定檔 editing form: name, date and counting rule (PRD 0.2
/// FR-13, reshaped by #226 R-8／R-9 for 0.4, TASK-155 for 1.0).
///
/// Stands alone on purpose, like `StyleTabView`: the container that shows it
/// (today the panel's 內容 tab, from TASK-44 the profile edit page) builds a
/// `RulesTabModel` from the active profile and drops this view in.
///
/// Three rows in an iOS grouped-list block (名稱｜日期｜起算), each with its
/// label above its value, then a 天數預覽 block. The counting-rule choice is
/// a hand-drawn segmented control rather than a native `Picker(.segmented)` —
/// the native one clipped the longer "當天算第 1 天" label at narrow widths
/// (25.6).
struct RulesTabView: View {
    @ObservedObject var model: RulesTabModel
    @FocusState private var isNameFieldFocused: Bool
    @State private var nameSelection: TextSelection?
    @State private var didSelectName = false

    /// Whether this view adds its own `.tabbody` inset (12 vertical, 14
    /// horizontal). `ContentTabView` turns it off and applies the same inset
    /// once around both sub-tabs (TASK-38).
    var appliesOuterPadding: Bool = true

    /// When `true`, the name field takes focus with its text selected as the
    /// view appears (#226 R-7: a freshly created profile).
    var focusesNameOnAppear: Bool = false

    /// Minimum height of a row; also the height of the edit page's action rows.
    static let rowMinHeight: CGFloat = 48
    /// Corner radius of the grouped block.
    static let blockCornerRadius: CGFloat = 12
    /// Horizontal inset of row content inside the grouped block.
    static let rowHorizontalPadding: CGFloat = 16
    /// Vertical inset of each row inside the grouped block.
    static let rowVerticalPadding: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 0) {
                nameRow
                rowDivider
                startDateRow
                rowDivider
                countingRuleRow
            }
            .background(
                RoundedRectangle(cornerRadius: Self.blockCornerRadius, style: .continuous)
                    .fill(CameraTheme.fill)
            )
            dayPreviewBlock
                .padding(.top, 16)
        }
        .padding(.vertical, appliesOuterPadding ? 12 : 0)
        .padding(.horizontal, appliesOuterPadding ? 14 : 0)
        .onAppear {
            guard focusesNameOnAppear else { return }
            // Focus first, then select once the field is first responder:
            // a selection set before that is dropped by the text field.
            DispatchQueue.main.async {
                isNameFieldFocused = true
            }
        }
        .onChange(of: isNameFieldFocused) { _, isFocused in
            if isFocused {
                selectNameOnFirstFocus()
            } else {
                model.endEditingName()
            }
        }
        .alert("無法儲存", isPresented: Binding(get: { model.lastError != nil },
                                             set: { if !$0 { model.lastError = nil } })) {
            Button("好") { model.lastError = nil }
        } message: {
            Text("請再試一次。")
        }
    }

    private func selectNameOnFirstFocus() {
        guard focusesNameOnAppear, !didSelectName else { return }
        didSelectName = true
        DispatchQueue.main.async {
            let name = model.nameDraft
            nameSelection = TextSelection(range: name.startIndex..<name.endIndex)
        }
    }

    private var rowDivider: some View {
        Divider().padding(.leading, Self.rowHorizontalPadding)
    }

    /// Small gray label above a row's value.
    private func rowLabel(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundColor(CameraTheme.inkSecondary)
    }

    // MARK: - 名稱 (FR-13.2, A-5)

    private var nameRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            rowLabel("名稱")
            TextField(model.namePlaceholder, text: Binding(
                get: { model.nameDraft },
                set: { model.setName($0) }
            ), selection: $nameSelection)
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(CameraTheme.ink)
            .multilineTextAlignment(.leading)
            .focused($isNameFieldFocused)
            .submitLabel(.done)
            .onSubmit { model.endEditingName() }
            .accessibilityLabel("名稱")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Self.rowHorizontalPadding)
        .padding(.vertical, Self.rowVerticalPadding)
    }

    // MARK: - 日期 (FR-13.3)

    /// Any date, past or future (TASK-94 #393, human 2026-10-10): a future
    /// start date reads 還有 N 天 (#250) until the day arrives. The old
    /// upper bound of today (0.1 §7.2 UI layer) is gone.
    private var startDateRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            rowLabel("日期")
            HStack {
                DatePicker("日期", selection: Binding(
                    get: { model.startDateAsDate },
                    set: { model.setStartDate($0) }
                ), displayedComponents: .date)
                .labelsHidden()
                .accessibilityIdentifier("startDatePicker")
                .datePickerStyle(.compact)
                Spacer(minLength: 10)
                Text(model.todayShortText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(CameraTheme.inkSecondary)
                    .lineLimit(1)
                    .accessibilityIdentifier("rulesDateShortText")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Self.rowHorizontalPadding)
        .padding(.vertical, Self.rowVerticalPadding)
    }

    // MARK: - 起算 (FR-13.4)

    private var countingRuleRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            rowLabel("起算")
            HStack(spacing: 0) {
                countingRuleButton(.dayOne, label: RulesTabModel.countingRuleDayOneLabel)
                countingRuleButton(.dayZero, label: RulesTabModel.countingRuleDayZeroLabel)
            }
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(CameraTheme.fill)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Self.rowHorizontalPadding)
        .padding(.vertical, Self.rowVerticalPadding)
    }

    private func countingRuleButton(_ rule: CountingRule, label: String) -> some View {
        let isSelected = model.profile.countingRule == rule
        return Button {
            model.setCountingRule(rule)
        } label: {
            // Two equal cells filling the row, one line each, never clipped:
            // at 375pt a cell is ~150pt wide against ~90pt of text (25.6).
            Text(label)
                .font(.footnote.weight(isSelected ? .semibold : .regular))
                .lineLimit(1)
                .foregroundColor(isSelected ? CameraTheme.ink : CameraTheme.inkSecondary)
                .frame(maxWidth: .infinity, minHeight: 32)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(.systemBackground))
                            .shadow(color: .black.opacity(0.12), radius: 1.5, y: 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - 天數預覽 (FR-13.7, TASK-155)

    /// 「天數預覽」: today's row, then (for a future date) the day before, the
    /// day of and the day after. Not interactive; one VoiceOver element.
    private var dayPreviewBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(RulesTabModel.dayPreviewTitle)
                .font(.footnote)
                .foregroundColor(CameraTheme.inkSecondary)
                .padding(.horizontal, Self.rowHorizontalPadding)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(model.dayPreviewRows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        HStack(spacing: 4) {
                            Text(row.dateLabel)
                            if row.isStartDay { Text(RulesTabModel.timelineStartDayMarker) }
                        }
                        .font(.subheadline.weight(row.isEmphasized ? .bold : .regular))
                        .foregroundColor(row.isEmphasized ? CameraTheme.ink : CameraTheme.inkSecondary)
                        .frame(minWidth: 72, alignment: .leading)
                        Text(row.text)
                            .font(.subheadline.weight(row.isToday ? .bold : .regular))
                            .foregroundColor(CameraTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, Self.rowHorizontalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Self.blockCornerRadius, style: .continuous)
                    .fill(CameraTheme.fill.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Self.blockCornerRadius, style: .continuous)
                    .strokeBorder(CameraTheme.ink.opacity(0.1), lineWidth: 1)
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.dayPreviewSpokenText)
        .accessibilityIdentifier("rulesDayPreview")
    }
}

// MARK: - Preview

private func previewProfile(name: String = "小寶", unitsAndDate: Bool = false) -> CameraProfile {
    CameraProfile(name: name,
                 startDate: DateComponents(year: 2026, month: 1, day: 1),
                 showDate: unitsAndDate,
                 displayUnits: unitsAndDate ? [.year, .month] : [.day])
}

@MainActor
private func previewModel(name: String = "小寶", unitsAndDate: Bool = false) -> RulesTabModel {
    RulesTabModel(profile: previewProfile(name: name, unitsAndDate: unitsAndDate),
                 calculator: DayCountCalculator(now: { DateFixtureForPreview.fakeToday })) { _ in }
}

/// A fixed "today" so the preview's start-date upper bound and rendered
/// count are stable, matching the shared test scenario
/// (`DAYSCAM_FAKE_TODAY=2026-01-10`) documented in TASKS-0.2.
private enum DateFixtureForPreview {
    static let fakeToday: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 10
        components.hour = 8
        return Calendar(identifier: .gregorian).date(from: components) ?? Date()
    }()
}

#Preview("三列完整 · iPhone SE 寬度 (375pt)") {
    RulesTabView(model: previewModel())
        .frame(width: 375)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
}

#Preview("第 0 天 · iPhone SE 寬度 (375pt)") {
    let model = previewModel()
    model.setCountingRule(.dayZero)
    return RulesTabView(model: model)
        .frame(width: 375)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
}

#Preview("名稱聚焦全選 · iPhone SE 寬度 (375pt)") {
    RulesTabView(model: previewModel(), focusesNameOnAppear: true)
        .frame(width: 375)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
}

#Preview("單位勾年月、日期開：預覽仍印名稱＋天數 · iPhone SE 寬度 (375pt)") {
    RulesTabView(model: previewModel(unitsAndDate: true))
        .frame(width: 375)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
}
