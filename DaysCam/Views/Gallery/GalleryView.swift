import Photos
import SwiftUI
import UIKit

/// PRD 0.2 FR-15.5～15.9 / design D-5: the photo browsing screen. Only a
/// checkmark (back to the camera) and a trash — no share, edit or favorite
/// (FR-15.9). All state lives in `GalleryModel`.
struct GalleryView: View {
    @ObservedObject var model: GalleryModel
    /// Closes the gallery — the checkmark key (FR-14.3) and "去拍照".
    var onClose: () -> Void = {}

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .background(CameraTheme.background.ignoresSafeArea())
        .preferredColorScheme(.light)
        .task {
            await model.requestAccessAndLoad()
            // Live updates while open; cancelled (and unregistered) on close.
            await model.observeLibraryChanges()
        }
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
                    Image(systemName: "checkmark")
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
