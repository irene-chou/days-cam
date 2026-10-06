import SwiftUI
import UIKit

/// The full-screen 更多字型 list (PRD 0.3 FR-16, design D-6 option C). Looks
/// like `ProfileManagerView`: title on the left, a checkmark on the right to
/// close, white, no borders. All state and actions live in `FontLibraryModel`.
struct FontLibraryView: View {
    @ObservedObject var model: FontLibraryModel
    /// Closes the list — the checkmark key (FR-16.1).
    var onClose: () -> Void = {}

    @State private var showsLicense = false

    /// Row height (FR-16.3).
    static let rowHeight: CGFloat = 44
    /// Every name preview sits in a box this tall, so previews whose images
    /// differ in height (about 19 to 27pt) line up (`docs/fonts-manifest.md`).
    static let previewBoxHeight: CGFloat = 28

    var body: some View {
        ZStack {
            if showsLicense {
                FontLicenseView(onBack: { showsLicense = false })
                    .transition(.move(edge: .trailing))
            } else {
                listPage
                    .transition(.move(edge: .leading))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showsLicense)
        .background(Color.white)
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

    // MARK: - List page

    private var listPage: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(model.sections) { section in
                            Text(section.title)
                                .font(.system(size: 11, weight: .bold))
                                .tracking(0.6)
                                .foregroundColor(CameraTheme.inkTertiary)
                                .padding(.horizontal, 12)
                                .padding(.top, 12)
                                .padding(.bottom, 2)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(section.rows) { row in
                                rowView(row)
                                    .id(row.fontID)
                            }
                        }
                        licenseRow
                            .padding(.top, 16)
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 30)
                }
                .onAppear {
                    guard let target = model.scrollTarget else { return }
                    proxy.scrollTo(target, anchor: .center)
                }
            }
        }
        .overlay(alignment: .top) { toastView }
    }

    private var header: some View {
        HStack {
            Text("字型")
                .font(CameraTheme.toolFont(.headline))
                .foregroundColor(CameraTheme.ink)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "checkmark")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(CameraTheme.active)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("完成")
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.top, 14)
    }

    // MARK: - Rows (FR-16.3, FR-16.5)

    private func rowView(_ row: FontLibraryModel.Row) -> some View {
        HStack(spacing: 0) {
            Button {
                model.didTapRow(row.fontID)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(CameraTheme.active)
                        .opacity(row.isCurrent ? 1 : 0)
                        .frame(width: 16)
                    FontPreviewImage(fontID: row.fontID, accessibilityName: row.name)
                        .frame(height: Self.previewBoxHeight, alignment: .leading)
                    Spacer(minLength: 8)
                    if row.trailing != .menu {
                        trailingView(row.trailing)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: Self.rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(row.accessibilityLabel)
            .accessibilityAddTraits(row.isCurrent ? .isSelected : [])

            if row.trailing == .menu {
                Button {
                    model.requestDeletion(of: row.fontID)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(CameraTheme.inkSecondary)
                        .frame(width: 44, height: Self.rowHeight)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("\(row.name) 更多動作")
            }
        }
    }

    @ViewBuilder
    private func trailingView(_ trailing: FontLibraryModel.Trailing) -> some View {
        HStack(spacing: 6) {
            switch trailing {
            case .none, .menu:
                EmptyView()
            case .download(let sizeText):
                statusText(sizeText)
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 18))
                    .foregroundColor(CameraTheme.active)
            case .downloading(let percentText, let progress):
                statusText(percentText)
                FontProgressRing(progress: progress)
            case .preparing:
                FontProgressRing(progress: nil)
            case .retry:
                Text("重試")
                    .font(.system(size: 12))
                    .foregroundColor(Self.danger)
                Image(systemName: "exclamationmark.arrow.circlepath")
                    .font(.system(size: 18))
                    .foregroundColor(Self.danger)
            }
        }
    }

    private func statusText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12).monospacedDigit())
            .foregroundColor(CameraTheme.inkTertiary)
    }

    /// The `danger` token of the design (`#E0503F`).
    static let danger = Color(red: 0xE0 / 255, green: 0x50 / 255, blue: 0x3F / 255)

    // MARK: - 字型授權 (FR-16.13)

    private var licenseRow: some View {
        Button {
            showsLicense = true
        } label: {
            HStack {
                Text(FontLibraryModel.licenseRowTitle)
                    .font(.system(size: 15))
                    .foregroundColor(CameraTheme.ink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(CameraTheme.inkTertiary)
            }
            .padding(.horizontal, 10)
            .frame(height: Self.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Message

    @ViewBuilder
    private var toastView: some View {
        if let toast = model.toast {
            Text(toast.text)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(CameraTheme.toastBackground))
                .padding(.top, 8)
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
    /// Caps the height, for tight places such as a grid cell with a caption.
    var maxHeight: CGFloat?

    var body: some View {
        // Drawn at the image's own point size (never magnified), only shrunk
        // when `maxHeight` is smaller than the image is tall.
        let natural = UIImage(named: fontID.rawValue)?.size ?? CGSize(width: 60, height: 22)
        let scale = maxHeight.map { min(1, $0 / max(natural.height, 1)) } ?? 1
        Image(fontID.rawValue)
            .renderingMode(.template)
            .resizable()
            .frame(width: natural.width * scale, height: natural.height * scale)
            .foregroundColor(CameraTheme.ink)
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
                              current: OverlayFontID = .pingFang,
                              scrollTo: OverlayFontID? = nil) -> FontLibraryModel {
    FontLibraryModel(profileID: UUID(),
                     currentFontID: current,
                     library: StaticFontLibrary(states: states),
                     scrollTarget: scrollTo,
                     profiles: { [] },
                     applyFont: { _, _ in },
                     replaceFont: { _, _ in [] })
}

#Preview("清單 · 未下載（預設）") {
    FontLibraryView(model: previewListModel([:]))
}

#Preview("清單 · 下載中、準備中") {
    FontLibraryView(model: previewListModel([.huninn: .available,
                                             .songti: .downloading(progress: 0.38),
                                             .kaiti: .downloading(progress: 0.92),
                                             .hiraginoSans: .preparing],
                                            current: .huninn))
}

#Preview("清單 · 失敗") {
    FontLibraryView(model: previewListModel([.xingkai: .failed(.noNetwork),
                                             .yuanti: .failed(.other)],
                                            scrollTo: .xingkai))
}

#Preview("清單 · 已下載（開源有 ⋯）") {
    FontLibraryView(model: previewListModel([.huninn: .available,
                                             .iansui: .available,
                                             .notoSerifTC: .available,
                                             .songti: .available,
                                             .weibei: .available],
                                            current: .iansui))
}
