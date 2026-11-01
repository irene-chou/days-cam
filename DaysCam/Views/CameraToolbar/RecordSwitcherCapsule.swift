import SwiftUI

/// The camera's record switcher (PRD 2.0 FR-20.8, #655): the selected
/// record's name and a `chevron.down`, centered in the top bar. It keeps
/// the 1.x profile chip's look (0.2 FR-7.11, FR-14.2): no background, no
/// border, no subtitle. Tapping it opens `RecordSwitcherMenu`; disabled
/// during a timer countdown.
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
        .disabled(model.isRecordSwitcherDisabled)
        .opacity(model.isRecordSwitcherDisabled ? 0.4 : 1)
        .accessibilityLabel("切換紀錄")
        .accessibilityValue(model.selectedRecordName)
        .accessibilityIdentifier("cameraRecordSwitcher")
    }
}

/// The switcher's menu (D9): a white card under the capsule listing every
/// record with today's count, the selected one checked. Picking a row
/// changes where later photos go (`CameraScreenModel.selectRecord`).
///
/// Up to 20 records may not fit: the card is never taller than `maxHeight`
/// and scrolls vertically past that, opening on the selected record.
struct RecordSwitcherMenu: View {
    @ObservedObject var model: CameraScreenModel

    /// The tallest the card may be: the room below the top bar
    /// (`CameraScreenLayoutMetrics.recordMenuMaxHeight`).
    var maxHeight: CGFloat = .infinity

    /// Width of the card (D9: 60% of the screen), capped so long names
    /// still leave room for the count on a wide phone.
    static func width(forScreenWidth screenWidth: CGFloat) -> CGFloat {
        min(screenWidth * 0.6, 280)
    }

    /// The rows' own height, measured, so the card hugs them when they fit.
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        let choices = model.recordChoices
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                rows(choices)
                    .onGeometryChange(for: CGFloat.self, of: \.size.height) { contentHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            // Measured after the first layout, so the selected record is
            // scrolled to once the card has its height.
            .onChange(of: contentHeight) { _, _ in
                if let selected = choices.first(where: \.isSelected) {
                    proxy.scrollTo(selected.id, anchor: .center)
                }
            }
        }
        .frame(height: min(contentHeight, maxHeight))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.2), radius: 14, x: 0, y: 8)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cameraRecordMenu")
    }

    private func rows(_ choices: [CameraScreenModel.RecordChoice]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(choices.enumerated()), id: \.element.id) { index, choice in
                row(choice)
                    .id(choice.id)
                if index < choices.count - 1 {
                    Rectangle()
                        .fill(CameraTheme.fill)
                        .frame(height: 1)
                }
            }
        }
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
