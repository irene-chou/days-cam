import SwiftUI

/// Renders already-computed overlay text at one of the nine anchor points,
/// styled by a theme (PRD §3.4, FR-6.1–FR-6.4).
///
/// Deliberately takes a finished string rather than a `CameraProfile`: what to
/// print is decided by the caller (`TemplateRenderer`'s output), this view
/// only lays it out. Font size, margin and shrink-to-fit share
/// `OverlayMetrics` with the baking path (`OverlayRenderer`) so the
/// viewfinder and the saved photo agree (PRD FR-6.1, FR-4.7, FR-4.8).
///
/// Never intercepts touches (PRD FR-6.4), so it never blocks the shutter or
/// camera controls underneath it.
struct OverlayTextView: View {
    /// The text to draw. An empty string draws nothing.
    let text: String
    let theme: OverlayTheme
    let position: OverlayPosition
    /// The size of the frame the overlay is positioned within — the
    /// viewfinder's bounds live, the photo's pixel size when baking. Margin
    /// and base font size scale off its short edge (PRD FR-4.3, FR-4.7).
    let frameSize: CGSize

    var body: some View {
        if !text.isEmpty, frameSize.width > 0, frameSize.height > 0 {
            let shortEdge = min(frameSize.width, frameSize.height)
            let margin = OverlayMetrics.margin(forShortEdge: shortEdge)
            let baseFontSize = OverlayMetrics.baseFontSize(forShortEdge: shortEdge)
            let availableWidth = max(0, frameSize.width - margin * 2)
            let fontSize = OverlayMetrics.fittedFontSize(for: text,
                                                          theme: theme,
                                                          baseFontSize: baseFontSize,
                                                          availableWidth: availableWidth)
            let scale = OverlayMetrics.decorationScale(forFontSize: fontSize)

            decoratedText(fontSize: fontSize, scale: scale)
                .padding(margin)
                .frame(width: frameSize.width, height: frameSize.height, alignment: alignment)
                .allowsHitTesting(false)
        }
    }

    /// The SwiftUI alignment for `position` within a frame sized `frameSize`.
    private var alignment: Alignment {
        switch position {
        case .topLeading: return .topLeading
        case .topCenter: return .top
        case .topTrailing: return .topTrailing
        case .middleLeading: return .leading
        case .middleCenter: return .center
        case .middleTrailing: return .trailing
        case .bottomLeading: return .bottomLeading
        case .bottomCenter: return .bottom
        case .bottomTrailing: return .bottomTrailing
        }
    }

    /// Builds `text` styled with every one of `theme`'s decorations, applied
    /// in array order (PRD §3.4 — a theme like `softPink` layers a stroke
    /// under a shadow).
    ///
    /// Decoration constants (`OverlayTheme`) are expressed at
    /// `OverlayMetrics.referenceFontSize`; `scale` brings them to `fontSize`.
    private func decoratedText(fontSize: CGFloat, scale: CGFloat) -> some View {
        let plain = Text(text).font(Font(OverlayMetrics.font(for: theme, size: fontSize)))
        let mainColor = swiftUIColor(theme.textColor)
        var layered = AnyView(plain.foregroundColor(mainColor))

        for decoration in theme.decorations {
            switch decoration {
            case let .stroke(color, width):
                let strokeColor = swiftUIColor(color)
                let offsets = strokeOffsets(width: width * scale)
                let base = layered
                layered = AnyView(
                    ZStack {
                        ForEach(offsets.indices, id: \.self) { index in
                            plain.foregroundColor(strokeColor).offset(offsets[index])
                        }
                        base
                    }
                )
            case let .backgroundBox(color, opacity, cornerRadius, insets):
                let boxColor = swiftUIColor(color).opacity(opacity)
                layered = AnyView(
                    layered
                        .padding(.horizontal, insets.horizontal * scale)
                        .padding(.vertical, insets.vertical * scale)
                        .background(
                            RoundedRectangle(cornerRadius: cornerRadius * scale, style: .continuous)
                                .fill(boxColor)
                        )
                )
            case let .shadow(offset, blur, opacity, color):
                let shadowColor = swiftUIColor(color).opacity(opacity)
                layered = AnyView(
                    layered.shadow(color: shadowColor,
                                    radius: blur * scale,
                                    x: offset.width * scale,
                                    y: offset.height * scale)
                )
            }
        }

        return layered
    }

    /// Eight compass-direction offsets used to fake a text stroke: SwiftUI has
    /// no native glyph outline, so the stroke color is drawn as copies of the
    /// same text nudged in a ring behind the fill color (diagonals normalized
    /// so every copy sits `width` points away, not `width * √2`).
    private func strokeOffsets(width: CGFloat) -> [CGSize] {
        guard width > 0 else { return [] }
        let diagonal = width / CGFloat(2).squareRoot()
        let directions: [CGSize] = [
            CGSize(width: width, height: 0), CGSize(width: -width, height: 0),
            CGSize(width: 0, height: width), CGSize(width: 0, height: -width),
            CGSize(width: diagonal, height: diagonal), CGSize(width: diagonal, height: -diagonal),
            CGSize(width: -diagonal, height: diagonal), CGSize(width: -diagonal, height: -diagonal)
        ]
        return directions
    }

    private func swiftUIColor(_ color: OverlayColor) -> Color {
        Color(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.opacity)
    }
}

#Preview("All themes, bottom trailing") {
    ZStack {
        Color.gray
        ForEach(Array(OverlayTheme.all.enumerated()), id: \.offset) { index, theme in
            OverlayTextView(text: "第 \(index + 1) 天",
                             theme: theme,
                             position: .bottomTrailing,
                             frameSize: CGSize(width: 300, height: 400))
        }
    }
    .frame(width: 300, height: 400)
}

#Preview("Nine positions") {
    ZStack {
        Color.gray
        ForEach(OverlayPosition.allCases, id: \.self) { position in
            OverlayTextView(text: position.rawValue,
                             theme: .theme(for: .classicWhite),
                             position: position,
                             frameSize: CGSize(width: 300, height: 400))
        }
    }
    .frame(width: 300, height: 400)
}

#Preview("Long text shrinks") {
    ZStack {
        Color.white
        OverlayTextView(text: "小寶 2026.03.20　1 年 2 個月 5 天",
                         theme: .theme(for: .filmStrip),
                         position: .bottomTrailing,
                         frameSize: CGSize(width: 300, height: 400))
    }
    .frame(width: 300, height: 400)
}
