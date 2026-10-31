import SwiftUI

/// The camera's record switcher (PRD 2.0 FR-20.8, #655): the selected
/// record's name and a `chevron.down`, centered in the top bar. It keeps
/// the 1.x profile chip's look (0.2 FR-7.11, FR-14.2): no background, no
/// border, no subtitle. Tapping it opens `RecordSwitcherMenu`.
struct RecordSwitcherCapsule: View {
    @ObservedObject var model: CameraScreenModel

    /// Whether the viewfinder renders behind the top bar (issue #121).
    var isOnPhoto: Bool = false

    var body: some View {
        Button(action: model.toggleRecordMenu) {
            HStack(spacing: 4) {
                Text(model.selectedRecordName)
                    .font(CameraTheme.toolFont(.subheadline))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(isOnPhoto ? CameraTheme.inkOnPhoto : CameraTheme.ink)
            .legibleOverPhoto(isOnPhoto)
            .padding(.horizontal, 6)
            .padding(.vertical, 7)
        }
        .accessibilityLabel("切換紀錄")
        .accessibilityValue(model.selectedRecordName)
        .accessibilityIdentifier("cameraRecordSwitcher")
    }
}

/// The switcher's menu (D9): a white card under the capsule listing every
/// record with today's count, the selected one checked. Picking a row
/// changes where later photos go (`CameraScreenModel.selectRecord`).
struct RecordSwitcherMenu: View {
    @ObservedObject var model: CameraScreenModel

    /// Width of the card (D9: 60% of the screen), capped so long names
    /// still leave room for the count on a wide phone.
    static func width(forScreenWidth screenWidth: CGFloat) -> CGFloat {
        min(screenWidth * 0.6, 280)
    }

    var body: some View {
        let choices = model.recordChoices
        VStack(spacing: 0) {
            ForEach(Array(choices.enumerated()), id: \.element.id) { index, choice in
                row(choice)
                if index < choices.count - 1 {
                    Rectangle()
                        .fill(CameraTheme.fill)
                        .frame(height: 1)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.2), radius: 14, x: 0, y: 8)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cameraRecordMenu")
    }

    private func row(_ choice: CameraScreenModel.RecordChoice) -> some View {
        Button {
            model.selectRecord(choice.id)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(CameraTheme.active)
                    .opacity(choice.isSelected ? 1 : 0)
                Text(choice.name)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(CameraTheme.ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(choice.dayText)
                    .font(.system(.caption, design: .rounded).monospacedDigit())
                    .foregroundColor(CameraTheme.inkSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(choice.name)，\(choice.dayText)")
        .accessibilityAddTraits(choice.isSelected ? .isSelected : [])
        .accessibilityIdentifier("cameraRecordMenuRow")
    }
}
