import SwiftUI
import UIKit

/// The font list inside the style tab's 字型 page (TASK-56): the downloaded
/// fonts first, then the ones still to download by category, then the 字型授權
/// row. Three 48pt cells per row; state shows as a corner icon only. All state
/// and actions live in `FontLibraryModel`.
struct FontListView: View {
    @ObservedObject var model: FontLibraryModel

    @State private var showsLicense = false

    /// Cell height and corner radius (TASK-49 D).
    static let cellHeight: CGFloat = 48
    static let cellCornerRadius: CGFloat = 12
    /// Font name size in a downloaded cell.
    static let cellTextSize: CGFloat = 15
    /// A preview image is shrunk to this height (the images differ in height;
    /// `docs/fonts-manifest.md`).
    static let previewMaxHeight: CGFloat = 22
    /// The corner icon's size and its inset from the cell's top-right corner.
    static let statusIconSize: CGFloat = 15
    static let statusIconInset: CGFloat = 5
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
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                          alignment: .leading,
                          spacing: 8) {
                    ForEach(section.cells) { cell in
                        cellView(cell)
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

    // MARK: - Cells

    @ViewBuilder
    private func cellView(_ cell: FontLibraryModel.Cell) -> some View {
        let button = Button {
            model.didTap(cell.fontID)
        } label: {
            cellLabel(cell)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(cell.accessibilityLabel)
        .accessibilityAddTraits(cell.isSelected ? .isSelected : [])
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

    private func cellLabel(_ cell: FontLibraryModel.Cell) -> some View {
        let isGet = !cell.state.isAvailable && !cell.isSelected
        return ZStack {
            if cell.usesRealFont {
                // The font itself, resolved as the viewfinder resolves it.
                Text(cell.name)
                    .font(Font(OverlayMetrics.resolvedFont(for: cell.fontID, availability: model.availability)
                        .font(ofSize: Self.cellTextSize)))
                    .foregroundColor(CameraTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                // Not drawable yet: its preview image keeps the glyphs.
                FontPreviewImage(fontID: cell.fontID,
                                 accessibilityName: cell.name,
                                 maxHeight: Self.previewMaxHeight,
                                 tint: cell.isSelected ? CameraTheme.ink : CameraTheme.inkTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.cellHeight)
        .background(
            RoundedRectangle(cornerRadius: Self.cellCornerRadius, style: .continuous)
                .fill(cell.isSelected ? CameraTheme.active.opacity(0.12)
                      : (isGet ? Color.clear : CameraTheme.ink.opacity(0.05)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Self.cellCornerRadius, style: .continuous)
                .strokeBorder(cell.isSelected ? CameraTheme.active : CameraTheme.ink.opacity(isGet ? 0.12 : 0),
                              lineWidth: cell.isSelected ? 1.5 : 1)
        )
        .overlay(alignment: .topTrailing) {
            statusIcon(cell.status)
                .padding(Self.statusIconInset)
        }
        .contentShape(Rectangle())
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
/// The images differ in height, so callers put it in a fixed-height box
/// rather than rely on the image's own height.
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
