import Photos
import SwiftUI
import UIKit

/// PRD 0.2 FR-15.5～15.9 / design D-5: the photo browsing screen. Only a
/// back chevron (to the camera) and a trash — no share, edit or favorite
/// (FR-15.9); dragging the photo down also goes back (TASK-60). All state
/// lives in `GalleryModel`.
struct GalleryView: View {
    @ObservedObject var model: GalleryModel
    /// Closes the gallery — the back key and "去拍照".
    var onClose: () -> Void = {}

    @Environment(\.scenePhase) private var scenePhase

    /// Pull-down-to-close state (TASK-60): how far the finger has moved
    /// down, and whether this drag was judged vertical (nil until decided).
    @State private var dismissOffset: CGFloat = 0
    @State private var isDismissDragVertical: Bool?

    var body: some View {
        let progress = GalleryDismissDrag.progress(offset: dismissOffset)
        VStack(spacing: 0) {
            header
            content
        }
        .scaleEffect(GalleryDismissDrag.scale(progress: progress), anchor: .center)
        .offset(y: dismissOffset)
        // The cover itself is clear so the camera shows through as the
        // page fades; the page's own background carries the fade.
        .background(CameraTheme.background.opacity(1 - progress).ignoresSafeArea())
        .presentationBackground(.clear)
        .preferredColorScheme(.light)
        .task { await model.requestAccessAndLoad() }
        // Live updates while open (started by the load); unregistered on close.
        .onDisappear { model.stopObservingLibraryChanges() }
        // Back from the Photos app (or Settings): re-read the list so a
        // photo deleted there disappears (FR-15.4).
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            if model.phase == .denied {
                Task { await model.requestAccessAndLoad() }
            } else {
                model.reload()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            VStack(spacing: 1) {
                Text(model.titleText)
                    .font(CameraTheme.toolFont(.subheadline))
                    .foregroundColor(CameraTheme.ink)
                if let subtitle = model.subtitleText {
                    Text(subtitle)
                        .font(.system(.caption2, design: .rounded).monospacedDigit())
                        .foregroundColor(CameraTheme.inkTertiary)
                }
            }
            HStack {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(CameraTheme.active)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("回相機")
                Spacer()
            }
        }
        .frame(height: 52)
        .padding(.horizontal, 8)
    }

    // MARK: - States

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            Color.clear.frame(maxHeight: .infinity)
        case .empty:
            message(systemName: "photo", title: "還沒有照片",
                    detail: "用 DaysCam 拍的照片會出現在這裡。",
                    buttonTitle: "去拍照", action: onClose)
        case .denied:
            message(systemName: "lock", title: "需要照片權限",
                    detail: "DaysCam 需要讀取權限，才能顯示你用 DaysCam 拍的照片。已拍的照片都安全存在相簿裡。",
                    buttonTitle: "前往設定") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
        case .photos:
            photoBrowser
        }
    }

    private func message(systemName: String, title: String, detail: String,
                         buttonTitle: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemName)
                .font(.system(size: 40, weight: .light))
                .foregroundColor(CameraTheme.inkSecondary)
            Text(title)
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundColor(CameraTheme.ink)
            Text(detail)
                .font(.system(.footnote, design: .rounded))
                .foregroundColor(CameraTheme.inkSecondary)
                .multilineTextAlignment(.center)
            Button(action: action) {
                Text(buttonTitle)
                    .font(CameraTheme.toolFont(.subheadline))
                    .foregroundColor(CameraTheme.ink)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(CameraTheme.accent, in: Capsule())
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Photos

    private var photoBrowser: some View {
        VStack(spacing: 0) {
            TabView(selection: $model.selectedIndex) {
                ForEach(Array(model.photos.enumerated()), id: \.element.id) { index, photo in
                    GalleryImage(model: model, photo: photo, maxPixel: 1600, contentMode: .fit)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(maxHeight: .infinity)
            .simultaneousGesture(dismissGesture)

            thumbnailStrip

            HStack {
                Spacer()
                Button {
                    Task { await model.deleteCurrent() }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(CameraTheme.ink)
                        .frame(width: 44, height: 44)
                }
                .disabled(model.isDeleting)
                .accessibilityLabel("刪除")
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Pull down to close (TASK-60)

    /// Only a mostly vertical, downward drag on the photo area counts; the
    /// axis is decided once, at the start of the drag, so a horizontal page
    /// swipe never turns into a dismiss halfway.
    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                if isDismissDragVertical == nil {
                    isDismissDragVertical = GalleryDismissDrag.isVertical(translation: value.translation)
                }
                guard isDismissDragVertical == true else { return }
                dismissOffset = max(value.translation.height, 0)
            }
            .onEnded { value in
                let wasVertical = isDismissDragVertical == true
                isDismissDragVertical = nil
                guard wasVertical else { return }
                if GalleryDismissDrag.shouldDismiss(offset: value.translation.height,
                                                    predictedEndOffset: value.predictedEndTranslation.height) {
                    onClose()
                } else {
                    withAnimation(CameraTheme.spring) { dismissOffset = 0 }
                }
            }
    }

    private var thumbnailStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 4) {
                    ForEach(Array(model.photos.enumerated()), id: \.element.id) { index, photo in
                        let isCurrent = index == model.selectedIndex
                        Button {
                            withAnimation(CameraTheme.spring) { model.selectedIndex = index }
                        } label: {
                            GalleryImage(model: model, photo: photo, maxPixel: 120, contentMode: .fill)
                                .frame(width: 40, height: 40)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .opacity(isCurrent ? 1 : 0.55)
                                .scaleEffect(isCurrent ? 1.08 : 1)
                        }
                        .id(photo.id)
                        .accessibilityLabel("第 \(index + 1) 張")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .frame(height: 64)
            .onChange(of: model.selectedIndex) { _, index in
                guard model.photos.indices.contains(index) else { return }
                withAnimation(CameraTheme.spring) { proxy.scrollTo(model.photos[index].id, anchor: .center) }
            }
        }
    }
}

/// The numbers behind the pull-down-to-close drag (TASK-60), kept apart from
/// the view so they can be tested.
enum GalleryDismissDrag {
    /// Downward travel that always closes on release.
    static let closeDistance: CGFloat = 120
    /// Predicted travel of a quick flick that closes even when short.
    static let flickDistance: CGFloat = 360
    /// A flick must have moved at least this far to count.
    static let minimumFlickTravel: CGFloat = 30
    /// Travel at which the page is fully faded.
    static let fadeDistance: CGFloat = 300

    /// A drag counts as vertical only when it is mostly up/down.
    static func isVertical(translation: CGSize) -> Bool {
        abs(translation.height) > abs(translation.width)
    }

    /// 0 at rest, 1 once the page is fully faded.
    static func progress(offset: CGFloat) -> CGFloat {
        min(max(offset, 0) / fadeDistance, 1)
    }

    /// The page shrinks up to 15% as it follows the finger.
    static func scale(progress: CGFloat) -> CGFloat {
        1 - 0.15 * progress
    }

    /// Past 120pt, or a quick flick that has already moved a little.
    static func shouldDismiss(offset: CGFloat, predictedEndOffset: CGFloat) -> Bool {
        offset > closeDistance || (offset > minimumFlickTravel && predictedEndOffset > flickDistance)
    }
}

/// Loads one photo's pixels through the model and shows it, never cropped
/// when `contentMode` is `.fit` (FR-15.5: original ratio, centered).
private struct GalleryImage: View {
    let model: GalleryModel
    let photo: GalleryPhoto
    let maxPixel: CGFloat
    let contentMode: ContentMode

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.clear
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                CameraTheme.fill
            }
        }
        .clipped()
        .task(id: photo.id) {
            image = await model.image(for: photo, targetSize: CGSize(width: maxPixel, height: maxPixel))
        }
    }
}

// MARK: - Previews (B′, compare with docs/design/D5-gallery.html)

#if DEBUG
@MainActor
private struct PreviewLibrary: GalleryLibrary {
    var status: PHAuthorizationStatus = .authorized
    var count = 6
    func readStatus() -> PHAuthorizationStatus { status }
    func requestReadAccess() async -> PHAuthorizationStatus { status }
    func latestVisiblePhotoIDs(limit: Int) -> [String] { (0..<min(count, limit)).map { "p\($0)" } }
    func photos() -> [GalleryPhoto] {
        (0..<count).map { GalleryPhoto(id: "p\($0)", creationDate: Date(timeIntervalSince1970: 1_768_000_000 - Double($0) * 86_400)) }
    }
    func deletePhoto(id: String) async -> Bool { true }
    func image(id: String, targetSize: CGSize) async -> UIImage? {
        let hues: [CGFloat] = [0.58, 0.07, 0.38, 0.72, 0.11, 0.55]
        let index = Int(id.dropFirst()) ?? 0
        let size = CGSize(width: 300, height: index % 2 == 0 ? 400 : 300)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor(hue: hues[index % hues.count], saturation: 0.35, brightness: 0.85, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}

#Preview("有照片") {
    GalleryView(model: GalleryModel(library: PreviewLibrary(), timeZone: TimeZone(identifier: "Asia/Taipei") ?? .current))
}

#Preview("空狀態") {
    GalleryView(model: GalleryModel(library: PreviewLibrary(count: 0)))
}

#Preview("權限被拒") {
    GalleryView(model: GalleryModel(library: PreviewLibrary(status: .denied)))
}
#endif
