import SwiftUI

/// What the quick-zoom bar shows for the current zoom (issue #279).
enum ZoomPresetBarLogic {
    /// Within this of a preset counts as being exactly on it.
    static let exactTolerance: CGFloat = 0.05

    /// The preset nearest `requested`, compared by ratio (0.5 to 1 is as far as
    /// 1 to 2); nil without presets.
    static func selectedIndex(requested: CGFloat, presets: [ZoomPreset]) -> Int? {
        guard requested > 0 else { return presets.isEmpty ? nil : 0 }
        return presets.indices.min {
            abs(log(presets[$0].displayFactor / requested)) < abs(log(presets[$1].displayFactor / requested))
        }
    }

    /// The button's text. The selected one carries ×, and shows the real zoom
    /// ("1.7×") when `requested` is off its preset; the others are bare
    /// ("2", ".5").
    static func text(for preset: ZoomPreset, isSelected: Bool, requested: CGFloat) -> String {
        if isSelected {
            if abs(requested - preset.displayFactor) < exactTolerance {
                return "\(plain(preset.displayFactor))×"
            }
            return ViewfinderZoomModel.indicatorText(for: requested)
        }
        let plainText = plain(preset.displayFactor)
        return preset.displayFactor < 1 ? String(plainText.dropFirst()) : plainText
    }

    /// The VoiceOver label: "焦段 2 倍".
    static func accessibilityLabel(for preset: ZoomPreset) -> String {
        "焦段 \(plain(preset.displayFactor)) 倍"
    }

    private static func plain(_ factor: CGFloat) -> String {
        String(format: "%g", Double(factor))
    }
}

/// The vertical quick-zoom capsule on the viewfinder's right edge: one round
/// button per preset, largest on top (issue #279). Hidden while the panel is
/// open. Observes the zoom model itself, so a pinch redraws only this bar
/// (issue #280).
struct ZoomPresetBar: View {
    @ObservedObject var zoom: ViewfinderZoomModel
    let presets: [ZoomPreset]
    let isVisible: Bool
    /// The picture's rectangle in screen coordinates.
    let pictureFrame: CGRect

    private static let buttonSize: CGFloat = 32
    private static let barWidth: CGFloat = 40
    private static let tapSize: CGFloat = 44

    var body: some View {
        let selected = ZoomPresetBarLogic.selectedIndex(requested: zoom.requestedFactor, presets: presets)
        ZStack {
            // Out of the tree while hidden, so it is gone for VoiceOver and
            // takes no touches either.
            if isVisible {
                VStack(spacing: 4) {
                    ForEach(Array(presets.enumerated().reversed()), id: \.element.id) { index, preset in
                        button(for: preset, isSelected: index == selected)
                    }
                }
                .padding(.vertical, 4)
                .frame(width: Self.barWidth)
                .background(.black.opacity(0.35), in: Capsule())
                .position(x: pictureFrame.maxX - 8 - Self.barWidth / 2, y: pictureFrame.midY)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isVisible)
    }

    private func button(for preset: ZoomPreset, isSelected: Bool) -> some View {
        Button {
            zoom.selectPreset(preset)
        } label: {
            Text(ZoomPresetBarLogic.text(for: preset, isSelected: isSelected, requested: zoom.requestedFactor))
                .font(.system(size: 13, weight: isSelected ? .bold : .regular).monospacedDigit())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .foregroundColor(.white)
                .frame(width: Self.buttonSize, height: Self.buttonSize)
                .background(Circle().fill(isSelected ? Color.black.opacity(0.75) : Color.clear))
                .frame(width: Self.tapSize, height: Self.tapSize)
                .contentShape(Rectangle())
                .padding(.horizontal, -(Self.tapSize - Self.barWidth) / 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(ZoomPresetBarLogic.accessibilityLabel(for: preset))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("zoomPreset-\(ZoomPresetBarLogic.accessibilityLabel(for: preset))")
    }
}
