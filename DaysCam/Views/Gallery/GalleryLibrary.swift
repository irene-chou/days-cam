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
    /// The current `.readWrite` status, read without ever prompting. The
    /// camera screen uses it to decide whether the launch thumbnail may be
    /// read at all (FR-15.2, FR-15.3).
    func readStatus() -> PHAuthorizationStatus
    /// Requests `.readWrite` access if it has not been decided yet and
    /// returns the resulting status (FR-15.3). Never prompts again once
    /// decided.
    func requestReadAccess() async -> PHAuthorizationStatus
    /// Up to `limit` captured photo ids that currently resolve to a visible
    /// asset, newest first. Unlike `photos()` it never prunes
    /// `capturedAssetIDs`: under `.limited` access an id may exist yet be
    /// invisible, and the launch thumbnail must not forget it.
    func latestVisiblePhotoIDs(limit: Int) -> [String]
    /// The still-existing captured photos, newest first.
    func photos() -> [GalleryPhoto]
    /// Deletes the photo through the system confirmation (FR-15.6).
    /// Returns `false` when the user cancelled or the change failed.
    func deletePhoto(id: String) async -> Bool
    /// Loads a displayable image no larger than `targetSize` (pixels).
    func image(id: String, targetSize: CGSize) async -> UIImage?
    /// Yields once per photo-library change (e.g. limited selection edited,
    /// photo deleted elsewhere). The system calls back on a background
    /// queue and the stream yields from there; consumers (`GalleryModel`)
    /// hop to the main actor before touching state. The observer is
    /// registered when iteration starts and unregistered when the consuming
    /// task is cancelled. Never modifies `capturedAssetIDs`.
    func changes() -> AsyncStream<Void>
}

extension GalleryLibrary {
    /// Default: no change notifications.
    func changes() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}

/// Bridges `PHPhotoLibraryChangeObserver` (called on a background queue)
/// to an `AsyncStream`.
private final class PhotoLibraryChangeBridge: NSObject, PHPhotoLibraryChangeObserver {
    private let continuation: AsyncStream<Void>.Continuation
    init(continuation: AsyncStream<Void>.Continuation) { self.continuation = continuation }
    func photoLibraryDidChange(_ changeInstance: PHChange) { continuation.yield() }
}

/// Production library: `CapturedPhotoStore` decides which identifiers
/// count, `PHAsset`/`PHImageManager` supply dates and pixels.
@MainActor
struct SystemGalleryLibrary: GalleryLibrary {
    let store: CapturedPhotoStore

    func readStatus() -> PHAuthorizationStatus {
        SystemPhotoLibraryReadAccess().readAuthorizationStatus()
    }

    func requestReadAccess() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            store.requestReadAccessIfNeeded { status in
                continuation.resume(returning: status)
            }
        }
    }

    func latestVisiblePhotoIDs(limit: Int) -> [String] {
        let ids = store.capturedAssetIDs
        guard !ids.isEmpty else { return [] }
        var visible: Set<String> = []
        PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
            .enumerateObjects { asset, _, _ in visible.insert(asset.localIdentifier) }
        return Array(ids.filter { visible.contains($0) }.prefix(limit))
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

    func changes() -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let bridge = PhotoLibraryChangeBridge(continuation: continuation)
            PHPhotoLibrary.shared().register(bridge)
            continuation.onTermination = { _ in
                PHPhotoLibrary.shared().unregisterChangeObserver(bridge)
            }
        }
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
