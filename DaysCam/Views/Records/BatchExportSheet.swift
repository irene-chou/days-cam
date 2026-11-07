import SwiftUI

/// The export sheet (PRD 2.0 FR-22.5–22.9, D8 「批次匯出」), for the wall's
/// batch and the viewer's one photo (#679): the preview, then 匯出中 with
/// 停止, then the failures if any.
/// Only the preview can be swiped away (that is 取消); the other two stay
/// until their buttons are used.
struct BatchExportSheet: View {
    @ObservedObject var model: BatchExportModel
    /// The 文字樣式 page for a photo (FR-19), opened from 調整文字樣式.
    let makeExportModel: (RecordPhoto) -> ExportModel

    @State private var stylingPhoto: RecordPhoto?
    @State private var previewImage: UIImage?
    @Environment(\.displayScale) private var displayScale

    /// The carousel's share of the sheet width (D8 `.car{width:62%}`).
    static let carouselWidthRatio: CGFloat = 0.62

    /// The preview's share of the screen height.
    static let previewDetent: CGFloat = 0.85

    /// The carousel's box: 62% of the content width at 3:4, shorter when the
    /// rest of the preview (`reserved` points) would not fit the sheet
    /// otherwise, as on an iPhone SE (#679).
    static func carouselSize(reserved: CGFloat) -> CGSize {
        let width = ((UIScreen.main.bounds.width - 40) * carouselWidthRatio).rounded()
        let room = (UIScreen.main.bounds.height * previewDetent - reserved).rounded(.down)
        let height = min((width * 4 / 3).rounded(), room)
        return CGSize(width: min(width, (height * 3 / 4).rounded()), height: height)
    }

    /// Everything on the preview but the carousel's image, roughly: the
    /// padding, title, buttons and text options, plus ‹ i／M › and the skip
    /// line when shown (the batch note wraps to two lines on an SE).
    private var carouselSize: CGSize {
        let reserved: CGFloat = 300 + (model.exportable.count > 1 ? 52 : 0) + (model.skippedMessage == nil ? 0 : 44)
        return Self.carouselSize(reserved: reserved)
    }

    var body: some View {
        content
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(CameraTheme.background.ignoresSafeArea())
            .presentationDetents(detents)
            .presentationDragIndicator(model.phase == .preview ? .visible : .hidden)
            .interactiveDismissDisabled(model.phase != .preview)
            .preferredColorScheme(.light)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("batchExportSheet")
            .fullScreenCover(item: $stylingPhoto) { photo in
                ExportView(model: makeExportModel(photo))
            }
    }

    private var detents: Set<PresentationDetent> {
        model.phase == .preview ? [.fraction(Self.previewDetent)] : [.height(250)]
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .preview: preview
        case .running: progress
        case .failed: failures
        }
    }

    // MARK: - Preview (FR-22.5, FR-22.6)

    private var preview: some View {
        VStack(spacing: 12) {
            VStack(spacing: 6) {
                Text(model.previewTitle)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(CameraTheme.ink)
                    .accessibilityIdentifier("batchExportTitle")
                Text(model.previewNote)
                    .font(.system(size: 13.5))
                    .foregroundColor(CameraTheme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let skipped = model.skippedMessage {
                    Text(skipped)
                        .font(.system(size: 13.5))
                        .foregroundColor(CameraTheme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("batchExportSkipped")
                }
            }
            .multilineTextAlignment(.center)
            carousel
            textOptions
            Spacer(minLength: 0)
            primaryButton(model.exportButtonTitle, identifier: "batchExportStartButton") { model.start() }
            secondaryButton("取消", identifier: "batchExportCancelButton") { model.cancel() }
        }
    }

    /// The photo on show with its own marking, and ‹ i／M › under it.
    private var carousel: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.black.opacity(0.08))
                if let previewImage {
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 6)
                }
            }
            .frame(width: carouselSize.width, height: carouselSize.height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.previewPhoto.flatMap(model.overlayText(for:)) ?? "")
            .accessibilityIdentifier("batchExportPreview")
            if model.exportable.count > 1 {
                HStack(spacing: 14) {
                    navButton("chevron.left", label: "上一張", identifier: "batchExportPrevious") { model.showPrevious() }
                    Text(model.previewPosition)
                        .font(.system(size: 12.5).monospacedDigit())
                        .foregroundColor(CameraTheme.inkSecondary)
                        .accessibilityIdentifier("batchExportPosition")
                    navButton("chevron.right", label: "下一張", identifier: "batchExportNext") { model.showNext() }
                }
            }
        }
        // Redrawn for another photo, when 文字樣式 changed the record, or on 隱藏文字.
        .task(id: PreviewKey(photoID: model.previewPhoto?.id, profile: model.profile,
                             hidesText: model.hidesText, scale: displayScale)) {
            guard let photo = model.previewPhoto else { return }
            let side = carouselSize.height * displayScale
            let image = await model.previewImage(for: photo, targetSize: CGSize(width: side, height: side))
            guard !Task.isCancelled else { return }
            previewImage = image
        }
    }

    private struct PreviewKey: Equatable {
        let photoID: String?
        let profile: CameraProfile?
        let hidesText: Bool
        let scale: CGFloat
    }

    /// 隱藏文字 over 調整文字樣式 (#679): plain text buttons alike. While the
    /// text is hidden the first reads 顯示文字 and the style page is off.
    private var textOptions: some View {
        VStack(spacing: 4) {
            textButton(model.hidesText ? "顯示文字" : "隱藏文字", identifier: "exportHideTextButton") {
                model.toggleHidesText()
            }
            textButton("調整文字樣式", identifier: "batchExportStyleLink") { stylingPhoto = model.previewPhoto }
                .disabled(model.hidesText)
                .opacity(model.hidesText ? 0.4 : 1)
        }
    }

    private func textButton(_ title: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(CameraTheme.active)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
    }

    private func navButton(_ systemImage: String, label: String, identifier: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(CameraTheme.ink)
                .frame(width: 30, height: 30)
                .background(Circle().fill(CameraTheme.ink.opacity(0.07)))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    // MARK: - Progress (FR-22.7)

    private var progress: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("匯出中")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(CameraTheme.ink)
                .accessibilityIdentifier("batchExportProgressTitle")
            ProgressView(value: model.progressFraction)
                .progressViewStyle(.linear)
                .tint(CameraTheme.accent)
                .accessibilityHidden(true)
            Text(model.progressText)
                .font(.system(size: 12.5).monospacedDigit())
                .foregroundColor(CameraTheme.inkSecondary)
                .accessibilityLabel("已完成 \(model.progressText)")
                .accessibilityIdentifier("batchExportProgressText")
            Spacer(minLength: 0)
            secondaryButton("停止", identifier: "batchExportStopButton") { model.stop() }
                .disabled(model.isStopping)
                .opacity(model.isStopping ? 0.5 : 1)
        }
    }

    // MARK: - Failures (FR-22.9)

    private var failures: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.failureTitle)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(CameraTheme.ink)
                .accessibilityIdentifier("batchExportFailureTitle")
            Text(model.failureMessage)
                .font(.system(size: 13.5))
                .foregroundColor(CameraTheme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("batchExportFailureMessage")
            Spacer(minLength: 0)
            primaryButton("重試失敗的", identifier: "batchExportRetryButton") { model.retryFailed() }
            secondaryButton("好", identifier: "batchExportDoneButton") { model.acknowledgeFailures() }
        }
    }

    // MARK: - Buttons

    private func primaryButton(_ title: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .heavy))
                .foregroundColor(CameraTheme.inkOnAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Capsule().fill(CameraTheme.accent))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private func secondaryButton(_ title: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(CameraTheme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Capsule().fill(CameraTheme.fill))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}
