import SwiftUI

/// Renders already-computed overlay text styled and placed by an
/// `OverlayStyle`/`OverlayPlacement` (PRD 0.2 §4.1–§4.2).
///
/// Deliberately takes a finished string rather than a `CameraProfile`: what to
/// print is decided by the caller (`TemplateRenderer`'s output), this view
/// only lays it out. Font size, margin, shrink-to-fit and placement all go
/// through `OverlayMetrics` — the same functions the baking path
/// (`OverlayRenderer`) calls — so the viewfinder and the saved photo agree
/// (PRD FR-6.1, FR-4.7, FR-4.8; 0.2 FR-5.10, FR-12). No decoration constant
/// is defined here; they all live in `OverlayTheme` (TASK-18 18.11).
///
/// Never intercepts touches (PRD FR-6.4), so it never blocks the shutter or
/// camera controls underneath it.
struct OverlayTextView: View {
    /// The text to draw. An empty string draws nothing.
    let text: String
    /// The look (font, colors, outline, shadow, size) to draw `text` with.
    let style: OverlayStyle
    /// Where to draw `text`: a nine-point anchor or a custom center (PRD 0.2 §4.1).
    let placement: OverlayPlacement
    /// The size of the frame the overlay is positioned within — the
    /// viewfinder's bounds live, the photo's pixel size when baking. Margin
    /// and base font size scale off its short edge (PRD FR-4.3, FR-4.7).
    let frameSize: CGSize

    /// The measured size of the decorated text block. Starts at `.zero`, so
    /// the very first layout pass places the block as though it were empty;
    /// `onGeometryChange` below corrects it to the real size one frame later.
    /// This measure-then-place order (rather than SwiftUI alignment) is what
    /// lets `.custom` placements share `OverlayMetrics.origin` with the
    /// baking path instead of the view inventing its own nine-grid logic.
    @State private var blockSize: CGSize = .zero

    private var theme: OverlayTheme { OverlayTheme(style: style) }

    var body: some View {
        if !text.isEmpty, frameSize.width > 0, frameSize.height > 0 {
            let fontSize = Self.fittedFontSize(for: text, style: style, frameSize: frameSize)
            let scale = OverlayMetrics.decorationScale(forFontSize: fontSize)
            let origin = Self.origin(forBlockSize: blockSize, frameSize: frameSize, placement: placement)

            decoratedText(fontSize: fontSize, scale: scale)
                .onGeometryChange(for: CGSize.self) { proxy in
                    proxy.size
                } action: { newValue in
                    blockSize = newValue
                }
                .position(x: origin.x + blockSize.width / 2, y: origin.y + blockSize.height / 2)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Shared layout (mirrors `OverlayRenderer`'s private `OverlayLayout`)

    /// The font size this view draws `text` at for `frameSize`, after
    /// `style.sizeScale` and shrink-to-fit — the same value the baking path
    /// computes for the same inputs (PRD FR-6.1, 0.2 FR-5.10, FR-10.9).
    /// Exposed (rather than left as a body-local `let`) so
    /// `OverlayTextViewTests` can confirm it, without a hosting controller,
    /// against `OverlayMetrics` directly.
    static func fittedFontSize(for text: String, style: OverlayStyle, frameSize: CGSize) -> CGFloat {
        let shortEdge = min(frameSize.width, frameSize.height)
        let margin = OverlayMetrics.margin(forShortEdge: shortEdge)
        let baseFontSize = OverlayMetrics.baseFontSize(forShortEdge: shortEdge, sizeScale: style.sizeScale)
        let availableWidth = max(0, frameSize.width - margin * 2)
        return OverlayMetrics.fittedFontSize(for: text,
                                              theme: OverlayTheme(style: style),
                                              baseFontSize: baseFontSize,
                                              availableWidth: availableWidth)
    }

    /// The top-left corner this view places a block of `blockSize` at for
    /// `frameSize`/`placement` — a thin pass-through to
    /// `OverlayMetrics.origin(forBlockSize:in:placement:)`, the same call the
    /// baking path makes, so `.custom`'s margin-clamping (PRD 0.2 FR-12.2,
    /// FR-12.6) can never drift between preview and photo.
    static func origin(forBlockSize blockSize: CGSize,
                       frameSize: CGSize,
                       placement: OverlayPlacement) -> CGPoint {
        OverlayMetrics.origin(forBlockSize: blockSize, in: frameSize, placement: placement)
    }

    /// Builds `text` styled with every one of `theme`'s decorations, applied
    /// in array order (PRD §3.4 — a style with both an outline and a shadow
    /// layers a stroke under a shadow).
    ///
    /// Decoration constants (`OverlayTheme`) are expressed at
    /// `OverlayMetrics.referenceFontSize`; `scale` brings them to `fontSize`.
    private func decoratedText(fontSize: CGFloat, scale: CGFloat) -> some View {
        // `.lineLimit(1)` + `.fixedSize` keep this from wrapping: at the 60%
        // floor a still-too-long string must run past the margin instead
        // (PRD FR-4.8), and without them the outer `.frame` would constrain
        // the proposed width and SwiftUI would wrap onto a second line.
        let plain = Text(text)
            .font(Font(OverlayMetrics.font(for: theme.fontID, size: fontSize)))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
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
                // `.compositingGroup()` flattens whatever came before (in
                // particular the stroke's stack of offset copies) into one
                // layer first, so the shadow is cast once by the composed
                // glyph instead of once per stacked copy.
                layered = AnyView(
                    layered
                        .compositingGroup()
                        .shadow(color: shadowColor,
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

#Preview("Nine anchors") {
    ZStack {
        Color.gray
        ForEach(OverlayPosition.allCases, id: \.self) { position in
            OverlayTextView(text: position.rawValue,
                             style: OverlayStyle(),
                             placement: .anchor(position),
                             frameSize: CGSize(width: 300, height: 400))
        }
    }
    .frame(width: 300, height: 400)
}

#Preview("Custom placement, clamped into the margin") {
    ZStack {
        Color.gray
        OverlayTextView(text: "自訂位置",
                         style: OverlayStyle(outline: .thinStroke, shadow: .soft),
                         placement: .custom(x: 1.0, y: 1.0),
                         frameSize: CGSize(width: 300, height: 400))
    }
    .frame(width: 300, height: 400)
}

#Preview("Every outline and shadow, bottom trailing") {
    let outlines: [OverlayOutline] = [.none, .thinStroke, .thickStroke, .translucentBox, .solidBox]
    let shadows: [OverlayShadow] = [.none, .soft, .hard, .glow]
    return ZStack {
        Color(white: 0.5)
        VStack(alignment: .trailing, spacing: 4) {
            ForEach(Array(outlines.enumerated()), id: \.offset) { _, outline in
                HStack(spacing: 8) {
                    ForEach(Array(shadows.enumerated()), id: \.offset) { _, shadow in
                        OverlayTextView(text: "Aa",
                                         style: OverlayStyle(outline: outline, shadow: shadow),
                                         placement: .anchor(.middleCenter),
                                         frameSize: CGSize(width: 44, height: 44))
                            .frame(width: 44, height: 44)
                    }
                }
            }
        }
    }
    .frame(width: 300, height: 400)
}

#Preview("Every font") {
    ZStack {
        Color.white
        VStack(spacing: 6) {
            ForEach(OverlayFontID.allCases, id: \.self) { fontID in
                OverlayTextView(text: fontID.displayName,
                                 style: OverlayStyle(fontID: fontID, textColor: .autoContrastDark, shadow: .none),
                                 placement: .anchor(.middleCenter),
                                 frameSize: CGSize(width: 280, height: 32))
                    .frame(width: 280, height: 32)
            }
        }
    }
    .frame(width: 300, height: 400)
}

#Preview("sizeScale 70 vs 160") {
    ZStack {
        Color.white
        OverlayTextView(text: "70%",
                         style: OverlayStyle(textColor: .autoContrastDark, sizeScale: 70),
                         placement: .anchor(.topLeading),
                         frameSize: CGSize(width: 300, height: 400))
        OverlayTextView(text: "160%",
                         style: OverlayStyle(textColor: .autoContrastDark, sizeScale: 160),
                         placement: .anchor(.bottomTrailing),
                         frameSize: CGSize(width: 300, height: 400))
    }
    .frame(width: 300, height: 400)
}

#Preview("Long text shrinks") {
    ZStack {
        Color.white
        OverlayTextView(text: "小寶 2026.03.20　1 年 2 個月 5 天",
                         style: OverlayStyle(outline: .translucentBox, shadow: .none),
                         placement: .anchor(.bottomTrailing),
                         frameSize: CGSize(width: 300, height: 400))
    }
    .frame(width: 300, height: 400)
}
