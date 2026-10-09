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

    /// The round button's text for the current zoom: "2×" on a preset, the real
    /// zoom ("1.7×") between presets.
    static func collapsedText(requested: CGFloat, presets: [ZoomPreset]) -> String {
        guard let index = selectedIndex(requested: requested, presets: presets) else {
            return ViewfinderZoomModel.indicatorText(for: requested)
        }
        return text(for: presets[index], isSelected: true, requested: requested)
    }

    /// The round button's VoiceOver label: "焦段，目前 2 倍" (1.7 between presets).
    static func collapsedAccessibilityLabel(requested: CGFloat) -> String {
        "焦段，目前 \(plain(requested.rounded(toPlaces: 1))) 倍"
    }

    /// The VoiceOver label: "焦段 2 倍".
    static func accessibilityLabel(for preset: ZoomPreset) -> String {
        "焦段 \(plain(preset.displayFactor)) 倍"
    }

    /// Fewer than two presets leave nothing to choose, so no control at all.
    static func isShown(presets: [ZoomPreset]) -> Bool { presets.count > 1 }

    private static func plain(_ factor: CGFloat) -> String {
        String(format: "%g", Double(factor))
    }
}

private extension CGFloat {
    func rounded(toPlaces places: Int) -> CGFloat {
        let scale = CGFloat(pow(10.0, Double(places)))
        return (self * scale).rounded() / scale
    }
}

/// Whether the quick-zoom capsule is open (issue #302). Kept apart from
/// `ViewfinderZoomModel` so a pinch, which only changes the zoom, never
/// touches it. Opens on a tap of the round button and closes on a pick, a tap
/// elsewhere, or after `autoCollapseDelay` without being touched.
@MainActor
final class ZoomPresetExpansion: ObservableObject {
    @Published private(set) var isExpanded = false

    let autoCollapseDelay: Duration
    private var collapseTask: Task<Void, Never>?

    init(autoCollapseDelay: Duration = .seconds(3)) {
        self.autoCollapseDelay = autoCollapseDelay
    }

    deinit { collapseTask?.cancel() }

    /// The round button was tapped: opens (or closes) the capsule.
    func toggle() {
        isExpanded ? collapse() : expand()
    }

    func expand() {
        isExpanded = true
        scheduleCollapse()
    }

    func collapse() {
        collapseTask?.cancel()
        collapseTask = nil
        if isExpanded { isExpanded = false }
    }

    private func scheduleCollapse() {
        collapseTask?.cancel()
        collapseTask = Task { [weak self, delay = autoCollapseDelay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.collapse()
        }
    }
}

/// The quick-zoom control in the picture's bottom-right corner (issues #279,
/// #302): a 32pt round button showing the current zoom, which opens upward
/// into the vertical capsule of presets, largest on top. Hidden while the
/// panel is open. Observes the zoom model itself, so a pinch redraws only
/// this control (issue #280).
struct ZoomPresetBar: View {
    @ObservedObject var zoom: ViewfinderZoomModel
    @ObservedObject var expansion: ZoomPresetExpansion
    let presets: [ZoomPreset]
    let isVisible: Bool
    /// The picture's rectangle in screen coordinates.
    let pictureFrame: CGRect

    private static let buttonSize: CGFloat = 32
    private static let barWidth: CGFloat = 40
    private static let tapSize: CGFloat = 44
    static let cornerInset: CGFloat = 12

    var body: some View {
        let selected = ZoomPresetBarLogic.selectedIndex(requested: zoom.requestedFactor, presets: presets)
        let shown = isVisible && ZoomPresetBarLogic.isShown(presets: presets)
        ZStack {
            // Out of the tree while hidden, so it is gone for VoiceOver and
            // takes no touches either.
            if shown {
                ZStack(alignment: .bottomTrailing) {
                    if expansion.isExpanded {
                        capsule(selected: selected)
                            .transition(.opacity.combined(with: .scale(scale: 0.6, anchor: .bottom)))
                    } else {
                        roundButton
                            .transition(.opacity)
                    }
                }
                .padding(.trailing, Self.cornerInset + Self.buttonSize / 2 - Self.barWidth / 2)
                .padding(.bottom, Self.cornerInset)
                .frame(width: pictureFrame.width, height: pictureFrame.height, alignment: .bottomTrailing)
                .position(x: pictureFrame.midX, y: pictureFrame.midY)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: shown)
        .animation(.easeInOut(duration: 0.2), value: expansion.isExpanded)
        .onChange(of: shown) { _, nowShown in
            if !nowShown { expansion.collapse() }
        }
    }

    private var roundButton: some View {
        Button {
            expansion.toggle()
        } label: {
            Text(ZoomPresetBarLogic.collapsedText(requested: zoom.requestedFactor, presets: presets))
                .font(.system(size: 13, weight: .bold).monospacedDigit())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .foregroundColor(.white)
                .frame(width: Self.buttonSize, height: Self.buttonSize)
                .background(Circle().fill(Color.black.opacity(0.45)))
                .frame(width: Self.barWidth, height: Self.tapSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The 44pt hit area is centred on the 32pt circle, whose edge keeps
        // the 12pt corner inset.
        .padding(.bottom, -(Self.tapSize - Self.buttonSize) / 2)
        .accessibilityLabel(ZoomPresetBarLogic.collapsedAccessibilityLabel(requested: zoom.requestedFactor))
        .accessibilityHint("點兩下展開")
        .accessibilityIdentifier("zoomRoundButton")
    }

    private func capsule(selected: Int?) -> some View {
        VStack(spacing: 4) {
            ForEach(Array(presets.enumerated().reversed()), id: \.element.id) { index, preset in
                button(for: preset, isSelected: index == selected)
            }
        }
        .padding(.vertical, 4)
        .frame(width: Self.barWidth)
        .background(.black.opacity(0.35), in: Capsule())
    }

    private func button(for preset: ZoomPreset, isSelected: Bool) -> some View {
        Button {
            zoom.selectPreset(preset)
            expansion.collapse()
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
