import SwiftUI

/// The 設定檔 editing form: name, start date and counting rule (PRD 0.2
/// FR-13, reshaped by #226 R-8／R-9 for 0.4).
///
/// Stands alone on purpose, like `StyleTabView`: the container that shows it
/// (today the panel's 內容 tab, from TASK-44 the profile edit page) builds a
/// `RulesTabModel` from the active profile and drops this view in.
///
/// Three rows in an iOS grouped-list block (名稱｜起始日｜起算), then one
/// preview sentence. The counting-rule choice is a pair of plain buttons
/// rather than a native segmented control — a real `Picker(.segmented)`
/// clipped the longer "當天算第 1 天" label at narrow widths (25.6).
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

    /// Minimum height of each of the three rows, content vertically centered.
    static let rowMinHeight: CGFloat = 48
    /// Corner radius of the grouped block.
    static let blockCornerRadius: CGFloat = 12
    /// Horizontal inset of row content inside the grouped block.
    static let rowHorizontalPadding: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 0) {
                nameRow
                rowDivider
                nameOnPhotoRow
                rowDivider
                startDateRow
                rowDivider
                countingRuleRow
            }
            .background(
                RoundedRectangle(cornerRadius: Self.blockCornerRadius, style: .continuous)
                    .fill(CameraTheme.fill)
            )
            previewSentence
                .padding(.top, 12)
                .padding(.horizontal, Self.rowHorizontalPadding)
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

    /// 「今天會顯示為 」＋ bold `overlayPreviewText` (the actual overlay,
    /// TASK-109); wraps, at most 3 lines.
    private var previewSentence: some View {
        (Text("今天會顯示為 ").foregroundColor(CameraTheme.inkSecondary)
            + Text(model.overlayPreviewText).bold().foregroundColor(CameraTheme.ink))
            .font(.subheadline)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("rulesPreviewSentence")
    }

    // MARK: - 名稱 (FR-13.2, A-5)

    private var nameRow: some View {
        HStack {
            Text("名稱").foregroundColor(CameraTheme.inkSecondary)
            // `.rr{gap:10px}` (#106) — was 12.
            Spacer(minLength: 10)
            TextField("名稱", text: Binding(
                get: { model.nameDraft },
                set: { model.setName($0) }
            ), selection: $nameSelection)
            .multilineTextAlignment(.trailing)
            .focused($isNameFieldFocused)
            .submitLabel(.done)
            .onSubmit { model.endEditingName() }
            .accessibilityLabel("名稱")
        }
        .padding(.horizontal, Self.rowHorizontalPadding)
        .frame(minHeight: Self.rowMinHeight)
    }

    // MARK: - 寫在照片上 (FR-13.1, TASK-109)

    /// Indent of the 寫在照片上 row's label, one level under 名稱, so it reads
    /// as "the name → whether it goes onto the photo" (D-7 proposal 4).
    static let subRowIndent: CGFloat = 16

    /// The 名稱 switch of the content tab, repeated right under the name
    /// (TASK-109, #423): the two are the same `showName` and stay in sync.
    private var nameOnPhotoRow: some View {
        HStack {
            Text("寫在照片上").foregroundColor(CameraTheme.inkSecondary)
                .padding(.leading, Self.subRowIndent)
            Spacer(minLength: 10)
            Toggle("", isOn: Binding(get: { model.profile.showName },
                                     set: { model.setShowName($0) }))
                .tint(CameraTheme.accentControl)
                .labelsHidden()
        }
        .padding(.horizontal, Self.rowHorizontalPadding)
        .frame(minHeight: Self.rowMinHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("寫在照片上")
        .accessibilityIdentifier("nameOnPhotoToggle")
    }

    // MARK: - 起始日 (FR-13.3)

    /// Any date, past or future (TASK-94 #393, human 2026-10-10): a future
    /// start date reads 還有 N 天 (#250) until the day arrives. The old
    /// upper bound of today (0.1 §7.2 UI layer) is gone.

    private var startDateRow: some View {
        HStack {
            Text("起始日").foregroundColor(CameraTheme.inkSecondary)
            Spacer(minLength: 10)
            DatePicker("起始日", selection: Binding(
                get: { model.startDateAsDate },
                set: { model.setStartDate($0) }
            ), displayedComponents: .date)
            .labelsHidden()
            .accessibilityIdentifier("startDatePicker")
            .datePickerStyle(.compact)
        }
        .padding(.horizontal, Self.rowHorizontalPadding)
        .frame(minHeight: Self.rowMinHeight)
    }

    // MARK: - 起算 (FR-13.4)

    private var countingRuleRow: some View {
        HStack {
            Text("起算").foregroundColor(CameraTheme.inkSecondary)
            Spacer(minLength: 10)
            HStack(spacing: 8) {
                countingRuleButton(.dayOne, label: RulesTabModel.countingRuleDayOneLabel)
                countingRuleButton(.dayZero, label: RulesTabModel.countingRuleDayZeroLabel)
            }
        }
        .padding(.horizontal, Self.rowHorizontalPadding)
        .frame(minHeight: Self.rowMinHeight)
    }

    private func countingRuleButton(_ rule: CountingRule, label: String) -> some View {
        let isSelected = model.profile.countingRule == rule
        return Button {
            model.setCountingRule(rule)
        } label: {
            // `.fixedSize` keeps the full label on screen — never truncated
            // or clipped — which is exactly what a native segmented control
            // failed to do at narrow widths in the D-4 review (25.6).
            Text(label)
                .font(.footnote.weight(isSelected ? .semibold : .regular))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(isSelected ? CameraTheme.active.opacity(0.18) : Color.clear)
                )
                // Unselected uses the same secondary/t2 shade as the font
                // chips (`StyleTabView.fontRow`) — this is a selectable
                // option chip, not the second-layer nav row (which uses the
                // dimmer tertiary/t3 shade instead).
                .foregroundColor(isSelected ? CameraTheme.active : CameraTheme.inkSecondary)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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

#Preview("單位勾年月、日期開：預覽句仍只顯示天數 · iPhone SE 寬度 (375pt)") {
    RulesTabView(model: previewModel(unitsAndDate: true))
        .frame(width: 375)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
}
