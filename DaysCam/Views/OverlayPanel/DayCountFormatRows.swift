import SwiftUI

// MARK: - 寫法 (#583)

/// The 寫法 row of the record editor (#747, moved from the 文字內容 card): the
/// current wording and a chevron, opening the four wordings right under it.
/// It also decides the wall badges, the viewer title and the camera HUD
/// (FR-17.5), so it is always shown.
struct DayCountFormatRows: View {
    let format: DayCountFormat
    /// Whether day is the only checked unit, the one case the wording shows.
    let isApplied: Bool
    let onSelect: (DayCountFormat) -> Void

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

    var body: some View {
        let current = format
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
                .frame(minHeight: RulesTabView.rowMinHeight)
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
            onSelect(format)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isApplied ? CameraTheme.active : CameraTheme.inkTertiary)
                    .opacity(isSelected ? 1 : 0)
                    .frame(width: 18)
                // At the largest text sizes the name and example no longer
                // fit side by side: stack them instead of running off screen.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        optionName(name, isSelected: isSelected, ink: ink)
                        Spacer(minLength: 8)
                        optionExample(example)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        optionName(name, isSelected: isSelected, ink: ink)
                        optionExample(example)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(minHeight: RulesTabView.rowMinHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name)，\(example)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
        .accessibilityIdentifier("dayCountFormat_\(format.rawValue)")
    }

    private func optionName(_ name: String, isSelected: Bool, ink: Color) -> some View {
        Text(name)
            .font(.subheadline.weight(isSelected ? .semibold : .regular))
            .foregroundColor(ink)
    }

    private func optionExample(_ example: String) -> some View {
        Text(example)
            .font(.subheadline.monospacedDigit())
            .foregroundColor(isApplied ? CameraTheme.inkSecondary : CameraTheme.inkTertiary)
            .multilineTextAlignment(.trailing)
    }
}
