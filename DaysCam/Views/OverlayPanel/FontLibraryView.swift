import SwiftUI
import UIKit

/// The font list inside the style tab's 字型 page (TASK-56): the downloaded
/// fonts first, then the ones still to download by category, then the 字型授權
/// row. One font per row with its full name; the state icon sits at the
/// trailing edge. All state and actions live in `FontLibraryModel`.
struct FontListView: View {
    @ObservedObject var model: FontLibraryModel

    @State private var showsLicense = false
    /// The name and size text follow Dynamic Type, so a row grows with them.
    @ScaledMetric(relativeTo: .body) private var nameSize = FontListView.rowTextSize
    @ScaledMetric(relativeTo: .caption) private var sizeTextSize: CGFloat = 12
    @ScaledMetric(relativeTo: .subheadline) private var weightTextSize: CGFloat = FontListView.weightTextSize

    /// Row metrics (TASK-77): a row is at least 52pt and grows with the name.
    static let rowMinHeight: CGFloat = 52
    static let rowHorizontalPadding: CGFloat = 12
    /// Font name size in a downloaded row.
    static let rowTextSize: CGFloat = 17
    static let statusIconSize: CGFloat = 20
    /// The weight buttons of the expanded card (TASK-89, design A): at least
    /// 44pt tall, equal widths, each drawn in its own weight.
    static let weightButtonMinHeight: CGFloat = 44
    static let weightTextSize: CGFloat = 15
    static let weightButtonSpacing: CGFloat = 8
    static let cardCornerRadius: CGFloat = 12
    /// The selection bar left of the name.
    static let selectionBarWidth: CGFloat = 3
    /// The `danger` token of the design (`#E0503F`).
    static let danger = Color(red: 0xE0 / 255, green: 0x50 / 255, blue: 0x3F / 255)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(model.sections) { section in
                if let title = section.title {
                    Text(title)
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.6)
                        .foregroundColor(CameraTheme.inkTertiary)
                        .padding(.horizontal, 2)
                        .padding(.top, 14)
                        .padding(.bottom, 6)
                        .accessibilityAddTraits(.isHeader)
                }
                LazyVStack(spacing: 0) {
                    ForEach(section.cells) { cell in
                        cellView(cell, showsSeparator: cell.id != section.cells.last?.id)
                    }
                }
            }
            licenseRow
        }
        .padding(.vertical, 4)
        .onAppear { model.listDidAppear() }
        .onDisappear { model.listDidDisappear() }
        .fullScreenCover(isPresented: $showsLicense) {
            FontLicenseView(onBack: { showsLicense = false })
        }
        .confirmationDialog(model.deletePrompt?.title ?? "",
                            isPresented: Binding(get: { model.deletePrompt != nil },
                                                 set: { if !$0 { model.cancelDeletion() } }),
                            titleVisibility: .visible,
                            presenting: model.deletePrompt) { _ in
            Button("刪除字型", role: .destructive) { model.confirmDeletion() }
            Button("取消", role: .cancel) { model.cancelDeletion() }
        } message: { prompt in
            Text(prompt.usage)
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func cellView(_ cell: FontLibraryModel.Cell, showsSeparator: Bool) -> some View {
        let button = Button {
            model.didTap(cell.fontID)
        } label: {
            cell.isExpanded ? AnyView(cardTitle(cell)) : AnyView(cellLabel(cell, showsSeparator: showsSeparator))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(cell.accessibilityLabel)
        .accessibilityAddTraits(cell.isSelected ? .isSelected : [])
        let row = Group {
            if cell.canDelete {
                button
                    .contextMenu {
                        Button("套用") { model.didTap(cell.fontID) }
                        Button(role: .destructive) {
                            model.requestDeletion(of: cell.fontID)
                        } label: {
                            Label("刪除字型", systemImage: "trash")
                            if let size = FontCatalog.entry(for: cell.fontID).downloadSizeText {
                                Text("釋放 \(size)")
                            }
                        }
                    }
                    .accessibilityAction(named: "刪除字型") { model.requestDeletion(of: cell.fontID) }
            } else {
                button
            }
        }
        if cell.isExpanded {
            VStack(spacing: 0) {
                row
                weightButtons(cell)
            }
            .background(RoundedRectangle(cornerRadius: Self.cardCornerRadius)
                .fill(CameraTheme.active.opacity(0.12)))
            .padding(.vertical, 6)
        } else {
            row
        }
    }

    // MARK: - Expanded card (TASK-89, design A)

    /// The selected multi-weight font's name row inside its card: the name in
    /// the chosen weight and a check at the trailing edge.
    private func cardTitle(_ cell: FontLibraryModel.Cell) -> some View {
        HStack(spacing: 8) {
            nameView(cell)
            Spacer(minLength: 8)
            Image(systemName: "checkmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(CameraTheme.active)
                .frame(minWidth: Self.statusIconSize)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Self.rowHorizontalPadding)
        .frame(minHeight: Self.rowMinHeight)
        .contentShape(Rectangle())
    }

    /// One equal-width button per weight, each in its own weight; the chosen
    /// one has the yellow frame. A face not on the device shows its download
    /// icon, and tapping it downloads first and applies afterwards.
    private func weightButtons(_ cell: FontLibraryModel.Cell) -> some View {
        HStack(spacing: Self.weightButtonSpacing) {
            ForEach(cell.weights) { weight in
                Button {
                    model.didTapWeight(weight.weightID)
                } label: {
                    weightLabel(weight)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(weight.accessibilityLabel)
                .accessibilityAddTraits(weight.isSelected ? .isSelected : [])
                .accessibilityIdentifier("fontWeight.\(weight.weightID)")
            }
        }
        .padding(.horizontal, Self.rowHorizontalPadding)
        .padding(.bottom, 12)
    }

    private func weightLabel(_ weight: FontLibraryModel.WeightCell) -> some View {
        HStack(spacing: 4) {
            Text(weight.name)
                .font(Font(OverlayMetrics.font(for: weight.fontID,
                                               weightID: weight.weightID,
                                               size: weightTextSize,
                                               availability: model.availability)))
                .foregroundColor(CameraTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            weightStatusIcon(weight.status)
        }
        .frame(maxWidth: .infinity, minHeight: Self.weightButtonMinHeight)
        .background(RoundedRectangle(cornerRadius: 10)
            .fill(CameraTheme.ink.opacity(weight.isSelected ? 0.08 : 0.05)))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(CameraTheme.active, lineWidth: weight.isSelected ? 2 : 0))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func weightStatusIcon(_ status: FontLibraryModel.Status) -> some View {
        switch status {
        case .none, .justCompleted:
            EmptyView()
        case .notDownloaded:
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 14))
                .foregroundColor(CameraTheme.inkTertiary)
        case .downloading(let progress):
            FontProgressRing(progress: progress, diameter: 14)
        case .preparing:
            FontProgressRing(progress: nil, diameter: 14)
        case .failed:
            Image(systemName: "exclamationmark.arrow.circlepath")
                .font(.system(size: 14))
                .foregroundColor(Self.danger)
        }
    }

    private func cellLabel(_ cell: FontLibraryModel.Cell, showsSeparator: Bool) -> some View {
        HStack(spacing: 8) {
            nameView(cell)
            Spacer(minLength: 8)
            if let countText = cell.weightCountText {
                Text(countText)
                    .font(.system(size: sizeTextSize))
                    .foregroundColor(CameraTheme.inkTertiary)
                    .fixedSize()
            }
            if case .notDownloaded = cell.status,
               let size = FontCatalog.entry(for: cell.fontID).downloadSizeText {
                Text(size)
                    .font(.system(size: sizeTextSize))
                    .foregroundColor(CameraTheme.inkTertiary)
                    .fixedSize()
            }
            statusIcon(cell.status)
                .frame(minWidth: Self.statusIconSize)
        }
        .padding(.horizontal, Self.rowHorizontalPadding)
        .frame(minHeight: Self.rowMinHeight)
        .background(cell.isSelected ? CameraTheme.active.opacity(0.12) : Color.clear)
        .overlay(alignment: .leading) {
            if cell.isSelected {
                Capsule()
                    .fill(CameraTheme.active)
                    .frame(width: Self.selectionBarWidth)
                    .padding(.vertical, 12)
                    .padding(.leading, 4)
            }
        }
        .overlay(alignment: .bottom) {
            if showsSeparator {
                Rectangle()
                    .fill(CameraTheme.ink.opacity(0.08))
                    .frame(height: 1)
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func nameView(_ cell: FontLibraryModel.Cell) -> some View {
        if cell.usesRealFont {
            // The font itself, resolved as the viewfinder resolves it. Long
            // names wrap onto a second line, never shrink or truncate.
            Text(cell.name)
                .font(Font(OverlayMetrics.resolvedFont(for: cell.fontID, weightID: cell.nameWeightID, availability: model.availability)
                    .font(ofSize: nameSize)))
                .foregroundColor(CameraTheme.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .padding(.vertical, 8)
        } else {
            // Not drawable yet: its preview image keeps the glyphs.
            FontPreviewImage(fontID: cell.fontID,
                             accessibilityName: cell.name,
                             maxHeight: nil,
                             tint: cell.isSelected ? CameraTheme.ink : CameraTheme.inkTertiary)
                .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func statusIcon(_ status: FontLibraryModel.Status) -> some View {
        switch status {
        case .none:
            EmptyView()
        case .notDownloaded:
            Image(systemName: "arrow.down.circle")
                .font(.system(size: Self.statusIconSize))
                .foregroundColor(CameraTheme.inkTertiary)
        case .downloading(let progress):
            FontProgressRing(progress: progress, diameter: Self.statusIconSize)
        case .preparing:
            FontProgressRing(progress: nil, diameter: Self.statusIconSize)
        case .failed:
            Image(systemName: "exclamationmark.arrow.circlepath")
                .font(.system(size: Self.statusIconSize))
                .foregroundColor(Self.danger)
        case .justCompleted:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: Self.statusIconSize))
                .foregroundColor(CameraTheme.active)
        }
    }

    // MARK: - 字型授權 (FR-16.13)

    private var licenseRow: some View {
        Button {
            showsLicense = true
        } label: {
            HStack {
                Text(FontLibraryModel.licenseRowTitle)
                    .font(.system(size: 13))
                    .foregroundColor(CameraTheme.inkSecondary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(CameraTheme.inkTertiary)
            }
            .padding(.horizontal, 2)
            .frame(height: 44)
            .padding(.top, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The transient message of the font list, shown from the panel's pinned
/// header so it stays in view while the list scrolls.
struct FontToastView: View {
    @ObservedObject var model: FontLibraryModel

    var body: some View {
        if let toast = model.toast {
            Text(toast.text)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(CameraTheme.toastBackground))
                .transition(.opacity)
                .task(id: toast.id) {
                    try? await Task.sleep(nanoseconds: 1_900_000_000)
                    guard !Task.isCancelled else { return }
                    withAnimation { model.dismissToast(toast) }
                }
                .accessibilityAddTraits(.isStaticText)
        }
    }
}

// MARK: - Shared pieces

/// A font's name drawn from its pre-rendered preview image (FR-16.4): a
/// template image, so it takes `foregroundColor`, and it shows the real
/// glyphs before the font is downloaded.
///
/// The list keeps the native 17pt glyph size and lets rows grow for wrapped
/// full names. Tight callers may explicitly cap the height.
struct FontPreviewImage: View {
    let fontID: OverlayFontID
    let accessibilityName: String
    /// Caps the height, for tight places such as a grid cell.
    var maxHeight: CGFloat?
    /// The color the glyphs are drawn in.
    var tint: Color = CameraTheme.ink

    var body: some View {
        // Drawn at the image's own point size (never magnified), only shrunk
        // when `maxHeight` is smaller than the image is tall.
        let natural = UIImage(named: fontID.rawValue)?.size ?? CGSize(width: 60, height: 22)
        let scale = maxHeight.map { min(1, $0 / max(natural.height, 1)) } ?? 1
        Image(fontID.rawValue)
            .renderingMode(.template)
            .resizable()
            .frame(width: natural.width * scale, height: natural.height * scale)
            .foregroundColor(tint)
            .accessibilityLabel(accessibilityName)
    }
}

/// The small ring of the design: a filled arc for a known progress, a spinner
/// for `nil`.
struct FontProgressRing: View {
    let progress: Double?
    var diameter: CGFloat = 16

    var body: some View {
        ZStack {
            if let progress {
                Circle().stroke(CameraTheme.ink.opacity(0.12), lineWidth: 2.4)
                Circle()
                    .trim(from: 0, to: min(max(progress, 0), 1))
                    .stroke(CameraTheme.active, style: StrokeStyle(lineWidth: 2.4, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            } else {
                ProgressView()
                    .controlSize(.mini)
                    .tint(CameraTheme.active)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}

// MARK: - Previews

@MainActor
private func previewListModel(_ states: [OverlayFontID: FontState],
                              current: OverlayFontID = .pingFang) -> FontLibraryModel {
    FontLibraryModel(profileID: UUID(),
                     currentFontID: current,
                     library: StaticFontLibrary(states: states),
                     profiles: { [] },
                     applyFont: { _, _ in })
}

#Preview("字型清單 · 只有蘋方") {
    ScrollView { FontListView(model: previewListModel([:])).padding(.horizontal, 10) }
        .background(CameraTheme.background)
}

#Preview("字型清單 · 下載中、準備中、失敗") {
    ScrollView {
        FontListView(model: previewListModel([.huninn: .available,
                                              .songti: .downloading(progress: 0.38),
                                              .kaiti: .downloading(progress: 0.92),
                                              .hiraginoSans: .preparing,
                                              .xingkai: .failed(.noNetwork)],
                                             current: .huninn))
            .padding(.horizontal, 10)
    }
    .background(CameraTheme.background)
}
