import SwiftUI

/// The 天數規則 (rules) tab of the overlay panel (PRD 0.2 FR-13, D-4).
///
/// Stands alone on purpose, like `StyleTabView`: the panel shell and its
/// first-layer segmented control (樣式｜格式｜位置｜天數規則) are `ui-shell`'s
/// (TASK-22), which had not landed when this was written. Once it does,
/// `ui-shell` drops this view into the panel body for the 天數規則 segment,
/// passing in a `RulesTabModel` built from the active profile.
///
/// Three rows, no second layer (FR-13.1): 名稱｜起始日｜起算. The counting-rule
/// choice is a pair of plain buttons rather than a native segmented control —
/// during the D-4 design review a real `Picker(.segmented)` clipped the
/// longer "當天算第 1 天" label at narrow widths, which is exactly what
/// acceptance 25.6 now guards against.
struct RulesTabView: View {
    @ObservedObject var model: RulesTabModel
    @FocusState private var isNameFieldFocused: Bool

    /// Minimum height of each of the three rows, content vertically
    /// centered (#156, the human's 2026-10-01 call). Replaces the earlier
    /// per-row 12pt top/bottom padding, which made rows 46-58pt tall
    /// depending on their content (name field, native date picker, capsule
    /// buttons) and the whole page ~182pt.
    static let rowMinHeight: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            nameRow
            if model.showsCountingFields {
                Divider()
                startDateRow
                Divider()
                countingRuleRow
            } else {
                Text(RulesTabModel.hiddenHintMessage)
                    .font(.footnote)
                    .foregroundColor(CameraTheme.inkSecondary)
                    .padding(.top, 10)
            }
        }
        // This tab's own `.tabbody` outer inset — the generic D-4 value
        // (`.tabbody{padding:12px 14px}`, #106 R2, the human's 2026-09-27
        // call: each tab owns its own `.tabbody` padding rather than a
        // generic one shared by all four — `ui-shell` is dropping the panel
        // container's own generic inset in #105 to avoid stacking both).
        // Was a flat `.padding(.horizontal, 16)` with no vertical inset.
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .onChange(of: isNameFieldFocused) { _, isFocused in
            if !isFocused {
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

    // MARK: - 名稱 (FR-13.2, A-5)

    private var nameRow: some View {
        HStack {
            Text("名稱").foregroundColor(CameraTheme.inkSecondary)
            // `.rr{gap:10px}` (#106) — was 12.
            Spacer(minLength: 10)
            TextField("名稱", text: Binding(
                get: { model.nameDraft },
                set: { model.setName($0) }
            ))
            .multilineTextAlignment(.trailing)
            .focused($isNameFieldFocused)
            .submitLabel(.done)
            .onSubmit { model.endEditingName() }
            .accessibilityLabel("名稱")
        }
        // 44pt minimum tap height (Apple's recommendation; #116, #156).
        .frame(minHeight: Self.rowMinHeight)
    }

    // MARK: - 起始日 (FR-13.3)

    private var startDateRow: some View {
        HStack {
            Text("起始日").foregroundColor(CameraTheme.inkSecondary)
            Spacer(minLength: 10)
            DatePicker("起始日", selection: Binding(
                get: { model.startDateAsDate },
                set: { model.setStartDate($0) }
            ), in: ...model.startDateUpperBound, displayedComponents: .date)
            .labelsHidden()
            .datePickerStyle(.compact)
        }
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

private func previewProfile(name: String = "小寶", showDayCount: Bool = true) -> CameraProfile {
    CameraProfile(name: name,
                 startDate: DateComponents(year: 2026, month: 1, day: 1),
                 showDayCount: showDayCount)
}

@MainActor
private func previewModel(name: String = "小寶", showDayCount: Bool = true) -> RulesTabModel {
    RulesTabModel(profile: previewProfile(name: name, showDayCount: showDayCount),
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

#Preview("天數關閉：只留名稱 · iPhone SE 寬度 (375pt)") {
    RulesTabView(model: previewModel(showDayCount: false))
        .frame(width: 375)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
}
