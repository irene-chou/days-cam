import SwiftUI

/// PRD S-4: the display settings bottom sheet — display content, day-count
/// format, position and theme (the "visual layer", FR-3.5). All state and
/// validation live in `DisplaySettingsModel`; this view only lays it out.
///
/// Deliberately excludes start date and counting rule (PRD S-3 / TASK-06).
struct DisplaySettingsSheet: View {
    @ObservedObject var model: DisplaySettingsModel

    var body: some View {
        NavigationStack {
            Form {
                displayContentSection
                dayCountFormatSection
                positionSection
                themeSection
            }
            .navigationTitle("顯示設定")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .alert("無法儲存", isPresented: Binding(get: { model.lastError != nil },
                                             set: { if !$0 { model.lastError = nil } })) {
            Button("好") { model.lastError = nil }
        } message: {
            Text("請再試一次。")
        }
    }

    // MARK: - 顯示內容 (FR-2.1–FR-2.4)

    private var displayContentSection: some View {
        Section {
            Toggle("顯示天數", isOn: Binding(get: { model.profile.showDayCount },
                                          set: { model.setShowDayCount($0) }))
                .disabled(model.isShowDayCountToggleDisabled)
            Toggle("顯示日期", isOn: Binding(get: { model.profile.showDate },
                                          set: { model.setShowDate($0) }))
                .disabled(model.isShowDateToggleDisabled)
            Toggle("顯示名稱", isOn: Binding(get: { model.profile.showName },
                                          set: { model.setShowName($0) }))
        } header: {
            Text("顯示內容")
        } footer: {
            if model.isShowDayCountToggleDisabled || model.isShowDateToggleDisabled {
                Text(DisplaySettingsModel.mustShowAtLeastOneMessage)
            }
        }
    }

    // MARK: - 天數格式 (FR-2.7–FR-2.10)

    private var dayCountFormatSection: some View {
        Section {
            Picker("最大單位", selection: Binding(get: { model.profile.largestUnit },
                                              set: { model.setLargestUnit($0) })) {
                ForEach(DisplayUnit.allCases, id: \.self) { unit in
                    Text(displayName(for: unit)).tag(unit)
                }
            }
            Picker("最小單位", selection: Binding(get: { model.profile.smallestUnit },
                                              set: { model.setSmallestUnit($0) })) {
                ForEach(model.availableSmallestUnits, id: \.self) { unit in
                    Text(displayName(for: unit)).tag(unit)
                }
            }
            Toggle("歲措辭", isOn: Binding(get: { model.profile.useAgeWording },
                                        set: { model.setUseAgeWording($0) }))
                .disabled(model.isAgeWordingToggleDisabled)
        } header: {
            Text("天數格式")
        }
        .disabled(model.isDayCountFormatSectionDisabled)
    }

    // MARK: - 位置 (FR-4.1–FR-4.5)

    private var positionSection: some View {
        Section {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                ForEach(OverlayPosition.allCases, id: \.self) { position in
                    positionButton(position)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("位置")
        }
    }

    private func positionButton(_ position: OverlayPosition) -> some View {
        // TEMP(TASK-17): adapter until TASK-21/24 replaces this view layer
        let isSelected = model.profile.position == .anchor(position)
        return Button {
            model.setPosition(position)
        } label: {
            Text(displayName(for: position))
                .font(.footnote)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.2) : Color(.secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
        .foregroundColor(.primary)
    }

    // MARK: - 主題 (FR-4.6–FR-4.9)

    private var themeSection: some View {
        Section {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                ForEach(OverlayTheme.all) { theme in
                    themeSwatch(theme)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("主題")
        }
    }

    private func themeSwatch(_ theme: OverlayTheme) -> some View {
        // TEMP(TASK-17): adapter until TASK-21/24 replaces this view layer
        let isSelected = ThemeID(nearestTo: model.profile.style) == theme.id
        return Button {
            model.setThemeID(theme.id)
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(.tertiarySystemBackground))
                    OverlayTextView(text: "16",
                                    style: theme.style,
                                    placement: .anchor(.middleCenter),
                                    frameSize: CGSize(width: 72, height: 44))
                }
                .frame(width: 72, height: 44)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                )
                Text(theme.displayName)
                    .font(.caption2)
                    .foregroundColor(.primary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Display names

    private func displayName(for unit: DisplayUnit) -> String {
        switch unit {
        case .year: return "年"
        case .month: return "月"
        case .week: return "週"
        case .day: return "天"
        }
    }

    private func displayName(for position: OverlayPosition) -> String {
        switch position {
        case .topLeading: return "左上"
        case .topCenter: return "中上"
        case .topTrailing: return "右上"
        case .middleLeading: return "左中"
        case .middleCenter: return "正中"
        case .middleTrailing: return "右中"
        case .bottomLeading: return "左下"
        case .bottomCenter: return "中下"
        case .bottomTrailing: return "右下"
        }
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            DisplaySettingsSheet(model: DisplaySettingsModel(
                profile: CameraProfile(name: "小寶", startDate: DateComponents(year: 2026, month: 1, day: 1)),
                updateProfile: { _ in }
            ))
        }
}
