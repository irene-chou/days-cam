import SwiftUI

extension FilmDateCorner {
    /// The corner's name in the picker and in the layer list's summary.
    var displayName: String {
        switch self {
        case .topLeading: return "左上"
        case .topTrailing: return "右上"
        case .bottomLeading: return "左下"
        case .bottomTrailing: return "右下"
        }
    }
}

/// The 底片日期 layer's page (#718): the corner picker the 戳記 card used to
/// hold (#521, #558, its look unchanged) and the line saying the stamp's
/// wording is fixed. The layer's switch lives on the layer list.
struct FilmDateDetailView: View {
    @ObservedObject var model: FormatTabModel

    /// The film date stamp's own orange, for the corner icons.
    private static let stampColor = Color(red: FilmDateStamp.Metrics.red,
                                          green: FilmDateStamp.Metrics.green,
                                          blue: FilmDateStamp.Metrics.blue)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 0) {
                cornerRow
            }
            .padding(.horizontal, 12)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("stampCard")
            Text("底片日期的字樣固定，不受「樣式」分頁和文字位置影響。")
                .font(.system(size: 12))
                .foregroundColor(CameraTheme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
                .padding(.top, 5)
                .accessibilityIdentifier("stampNote")
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
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
        let name = corner.displayName
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
            .frame(maxWidth: .infinity, minHeight: FormatTabView.rowMinHeight)
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
}

#Preview("底片日期 · iPhone SE 寬度 (375pt)") {
    let profile = CameraProfile(name: "小寶", startDate: DateComponents(year: 2026, month: 1, day: 1),
                                showFilmDate: true)
    return FilmDateDetailView(model: FormatTabModel(displaySettings: DisplaySettingsModel(profile: profile) { _ in }))
        .frame(width: 375)
        .background(CameraTheme.background)
}
