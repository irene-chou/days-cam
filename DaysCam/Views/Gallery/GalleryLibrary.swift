import Photos
import UIKit

/// One photo the gallery lists.
struct GalleryPhoto: Equatable, Identifiable {
    /// `PHAsset.localIdentifier`.
    let id: String
    /// `PHAsset.creationDate`, used **only** to show the title (PRD 0.2 §7,
    /// acceptance 29.8): it never feeds day-count or baking logic.
    let creationDate: Date?
}

/// The slice of the photo library the gallery needs (PRD 0.2 FR-15.4～15.6).
///
/// Injected so `GalleryModel` can be tested with a fake: neither the read
/// permission prompt nor a `PHAsset` can be built in a unit test.
@MainActor
protocol GalleryLibrary {
    /// Requests `.readWrite` access if it has not been decided yet and
    /// returns the resulting status (FR-15.3). Never prompts again once
    /// decided.
    func requestReadAccess() async -> PHAuthorizationStatus
    /// The still-existing captured photos, newest first.
    func photos() -> [GalleryPhoto]
    /// Deletes the photo through the system confirmation (FR-15.6).
    /// Returns `false` when the user cancelled or the change failed.
    func deletePhoto(id: String) async -> Bool
    /// Loads a displayable image no larger than `targetSize` (pixels).
    func image(id: String, targetSize: CGSize) async -> UIImage?
}

/// Production library: `CapturedPhotoStore` decides which identifiers
/// count, `PHAsset`/`PHImageManager` supply dates and pixels.
@MainActor
struct SystemGalleryLibrary: GalleryLibrary {
    let store: CapturedPhotoStore

    func requestReadAccess() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            store.requestReadAccessIfNeeded { status in
                continuation.resume(returning: status)
            }
        }
    }

    func photos() -> [GalleryPhoto] {
        let ids = store.fetchAssets()
        guard !ids.isEmpty else { return [] }
        var dates: [String: Date] = [:]
        PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
            .enumerateObjects { asset, _, _ in
                if let date = asset.creationDate { dates[asset.localIdentifier] = date }
            }
        return ids.map { GalleryPhoto(id: $0, creationDate: dates[$0]) }
    }

    func deletePhoto(id: String) async -> Bool {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        guard assets.count > 0 else { return true } // already gone
        let succeeded: Bool = await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.deleteAssets(assets)
            }, completionHandler: { success, _ in
                continuation.resume(returning: success)
            })
        }
        if succeeded { store.fetchAssets() } // prune the id from the store
        return succeeded
    }

    func image(id: String, targetSize: CGSize) async -> UIImage? {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        guard let asset = assets.firstObject else { return nil }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast
        return await withCheckedContinuation { continuation in
            var resumed = false
            PHImageManager.default().requestImage(for: asset, targetSize: targetSize,
                                                  contentMode: .aspectFit, options: options) { image, info in
                if (info?[PHImageResultIsDegradedKey] as? Bool) == true { return }
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: image)
            }
        }
    }
}
