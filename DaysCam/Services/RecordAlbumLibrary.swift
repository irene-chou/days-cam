import Photos
import UIKit

/// One photo of a record, identified by `PHAsset.localIdentifier`.
struct RecordPhoto: Equatable, Identifiable {
    let id: String
    /// `PHAsset.creationDate`. The only date source: EXIF is never read.
    let creationDate: Date?
}

/// A user album as listed by the album picker.
struct AlbumSummary: Equatable, Identifiable {
    /// `PHAssetCollection.localIdentifier`.
    let id: String
    let title: String
    /// Number of still photos (videos excluded).
    let photoCount: Int
}

/// Why a record-album operation failed.
enum RecordAlbumError: Error, Equatable {
    /// `.readWrite` access is missing for an operation that needs it.
    case permissionDenied
    /// An asset or album the operation needs no longer resolves.
    case notFound
    /// The library refused the change or could not produce the image.
    case failed(String)
}

/// How a read is served for a given `.readWrite` status (PRD §7.3).
enum RecordReadMode: Equatable {
    /// Full access: the record's album plus its fallback ids.
    case album
    /// Limited access: only the record's fallback ids that the app can still
    /// see; albums are not read, and other visible photos are not the
    /// record's (2026-10-31 ruling, #640).
    case fallbackOnly
    /// No read access.
    case none

    init(status: PHAuthorizationStatus) {
        switch status {
        case .authorized: self = .album
        case .limited: self = .fallbackOnly
        default: self = .none
        }
    }
}

/// The pure part of reading a record's photos, shared by the system library
/// and the fake so the tests cover the real rules.
enum RecordAlbumLogic {
    /// Unions `groups` by id (first occurrence wins), then orders oldest to
    /// newest. A `nil` date sorts first; ties break on `id` so the order is
    /// stable.
    static func merge(_ groups: [RecordPhoto]...) -> [RecordPhoto] {
        var seen: Set<String> = []
        var result: [RecordPhoto] = []
        for photo in groups.joined() where seen.insert(photo.id).inserted {
            result.append(photo)
        }
        return result.sorted { lhs, rhs in
            switch (lhs.creationDate, rhs.creationDate) {
            case (nil, nil): return lhs.id < rhs.id
            case (nil, _): return true
            case (_, nil): return false
            case let (l?, r?): return l == r ? lhs.id < rhs.id : l < r
            }
        }
    }
}

/// Access to the photos of a record (PRD 2.0 §4.1, §7).
///
/// Injected so the photo wall, viewer, export and camera can be tested without
/// a real library. It only reports results; writing album ids or fallback ids
/// back to the profile is the caller's job.
@MainActor
protocol RecordAlbumLibrary {
    /// The current `.readWrite` status; never prompts.
    func authorizationStatus() -> PHAuthorizationStatus
    /// Requests `.readWrite` access if undecided and returns the status.
    func requestReadWriteAccess() async -> PHAuthorizationStatus

    /// Still photos in the album united with the `fallbackIDs` that still
    /// exist (full access), or only the `fallbackIDs` still visible (limited),
    /// oldest first. Empty without read access. An unknown album is treated
    /// as none.
    func photos(albumIdentifier: String?, fallbackIDs: [String]) -> [RecordPhoto]
    /// `photos(...).count`, or `nil` without read access.
    func photoCount(albumIdentifier: String?, fallbackIDs: [String]) -> Int?
    /// The user's regular albums in the Photos app's order. Empty unless
    /// access is full.
    func userAlbums() -> [AlbumSummary]

    /// Adds the assets to the album, creating a new album titled `albumTitle`
    /// when `albumIdentifier` is `nil` or unknown (a same-titled album is not
    /// reused). Returns the album's identifier for the caller to store.
    func addAssets(_ ids: [String], albumIdentifier: String?, albumTitle: String) async throws -> String
    /// Creates an empty album titled `title` (a same-titled album is not
    /// reused) and returns its identifier for the caller to store. Throws
    /// `permissionDenied` without full access (FR-21.6).
    func createAlbum(title: String) async throws -> String
    /// Removes the assets from the album only, in one change; the photos stay
    /// in the library.
    func removeAssets(_ ids: [String], fromAlbum albumIdentifier: String) async throws
    /// Deletes the assets in one change, through one system confirmation.
    /// `false` when the user cancelled or the change failed.
    func deleteAssets(_ ids: [String]) async -> Bool

    /// Yields once per photo-library change, from a background queue.
    func changes() -> AsyncStream<Void>

    /// A grid-cell image of at most `targetSize` pixels.
    func thumbnail(id: String, targetSize: CGSize) async -> UIImage?
    /// A screen-sized image for the viewer.
    func displayImage(id: String, targetSize: CGSize) async -> UIImage?
    /// The original-quality image, downloading from iCloud if needed;
    /// `progress` reports 0...1.
    func fullImage(id: String, progress: @escaping @Sendable (Double) -> Void) async throws -> UIImage
    /// Hints that these thumbnails will be wanted soon. May do nothing.
    func startCaching(ids: [String], targetSize: CGSize)
}

extension RecordAlbumLibrary {
    func startCaching(ids: [String], targetSize: CGSize) {}

    /// Test doubles that never create albums fail like a refused change.
    func createAlbum(title: String) async throws -> String {
        throw RecordAlbumError.failed("無法建立相簿")
    }

    /// Removes one asset from the album; the photo stays in the library.
    func removeAsset(_ id: String, fromAlbum albumIdentifier: String) async throws {
        try await removeAssets([id], fromAlbum: albumIdentifier)
    }

    /// Deletes one asset through the system confirmation. `false` when the
    /// user cancelled or the change failed.
    func deleteAsset(_ id: String) async -> Bool {
        await deleteAssets([id])
    }
}

/// Bridges `PHPhotoLibraryChangeObserver` (background queue) to an `AsyncStream`.
private final class RecordLibraryChangeBridge: NSObject, PHPhotoLibraryChangeObserver {
    private let continuation: AsyncStream<Void>.Continuation
    init(continuation: AsyncStream<Void>.Continuation) { self.continuation = continuation }
    func photoLibraryDidChange(_ changeInstance: PHChange) { continuation.yield() }
}

/// In-flight `PHImageManager` request; the cancel handler may run on any
/// thread before the request has started, so id and flag share a lock.
private final class RecordImageRequestHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var requestID: PHImageRequestID?
    private var isCancelled = false

    func start(_ id: PHImageRequestID) {
        lock.lock()
        requestID = id
        let cancelNow = isCancelled
        lock.unlock()
        if cancelNow { PHImageManager.default().cancelImageRequest(id) }
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let id = requestID
        lock.unlock()
        if let id { PHImageManager.default().cancelImageRequest(id) }
    }
}

/// Production implementation over `PHPhotoLibrary`.
@MainActor
final class SystemRecordAlbumLibrary: RecordAlbumLibrary {
    private let cachingManager = PHCachingImageManager()

    func authorizationStatus() -> PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func requestReadWriteAccess() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { continuation.resume(returning: $0) }
        }
    }

    // MARK: Reading

    /// Only still photos count (Live Photos included, videos excluded).
    private static var imageOptions: PHFetchOptions {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
        return options
    }

    private static func photos(from result: PHFetchResult<PHAsset>) -> [RecordPhoto] {
        var photos: [RecordPhoto] = []
        result.enumerateObjects { asset, _, _ in
            photos.append(RecordPhoto(id: asset.localIdentifier, creationDate: asset.creationDate))
        }
        return photos
    }

    private static func album(identifier: String?) -> PHAssetCollection? {
        guard let identifier else { return nil }
        return PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [identifier], options: nil).firstObject
    }

    func photos(albumIdentifier: String?, fallbackIDs: [String]) -> [RecordPhoto] {
        let primary: [RecordPhoto]
        switch RecordReadMode(status: authorizationStatus()) {
        case .none:
            return []
        case .album:
            if let album = Self.album(identifier: albumIdentifier) {
                primary = Self.photos(from: PHAsset.fetchAssets(in: album, options: Self.imageOptions))
            } else {
                primary = []
            }
        case .fallbackOnly:
            // A fetch by id under limited access only returns assets still in
            // the user's selection, so deselected ids simply drop out.
            primary = []
        }
        return RecordAlbumLogic.merge(primary, fallbackImages(fallbackIDs))
    }

    /// Fallback assets that are still photos (the id fetch cannot filter).
    private func fallbackImages(_ ids: [String]) -> [RecordPhoto] {
        guard !ids.isEmpty else { return [] }
        var photos: [RecordPhoto] = []
        PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).enumerateObjects { asset, _, _ in
            if asset.mediaType == .image {
                photos.append(RecordPhoto(id: asset.localIdentifier, creationDate: asset.creationDate))
            }
        }
        return photos
    }

    func photoCount(albumIdentifier: String?, fallbackIDs: [String]) -> Int? {
        guard RecordReadMode(status: authorizationStatus()) != .none else { return nil }
        return photos(albumIdentifier: albumIdentifier, fallbackIDs: fallbackIDs).count
    }

    func userAlbums() -> [AlbumSummary] {
        guard authorizationStatus() == .authorized else { return [] }
        // `.album` + `.albumRegular` = albums the user made; smart albums and
        // shared albums are other types. Default order is the Photos app's.
        let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
        var summaries: [AlbumSummary] = []
        collections.enumerateObjects { collection, _, _ in
            let count = PHAsset.fetchAssets(in: collection, options: Self.imageOptions).count
            summaries.append(AlbumSummary(id: collection.localIdentifier,
                                          title: collection.localizedTitle ?? "",
                                          photoCount: count))
        }
        return summaries
    }

    // MARK: Writing

    private static func perform(_ changes: @escaping () -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges(changes) { succeeded, error in
                if succeeded {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: RecordAlbumError.failed(error?.localizedDescription ?? "未知錯誤"))
                }
            }
        }
    }

    func addAssets(_ ids: [String], albumIdentifier: String?, albumTitle: String) async throws -> String {
        guard authorizationStatus() == .authorized else { throw RecordAlbumError.permissionDenied }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        guard assets.count == Set(ids).count else { throw RecordAlbumError.notFound }
        let existing = Self.album(identifier: albumIdentifier)
        // Written inside the change block, read after it completes.
        let created = CreatedAlbumID()
        try await Self.perform {
            if let existing {
                PHAssetCollectionChangeRequest(for: existing)?.addAssets(assets)
            } else {
                let creation = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumTitle)
                creation.addAssets(assets)
                created.value = creation.placeholderForCreatedAssetCollection.localIdentifier
            }
        }
        if let existing { return existing.localIdentifier }
        guard let identifier = created.value else { throw RecordAlbumError.failed("未取得相簿識別碼") }
        return identifier
    }

    func createAlbum(title: String) async throws -> String {
        guard authorizationStatus() == .authorized else { throw RecordAlbumError.permissionDenied }
        let created = CreatedAlbumID()
        try await Self.perform {
            let creation = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
            created.value = creation.placeholderForCreatedAssetCollection.localIdentifier
        }
        guard let identifier = created.value else { throw RecordAlbumError.failed("未取得相簿識別碼") }
        return identifier
    }

    func removeAssets(_ ids: [String], fromAlbum albumIdentifier: String) async throws {
        guard !ids.isEmpty else { return }
        guard authorizationStatus() == .authorized else { throw RecordAlbumError.permissionDenied }
        guard let album = Self.album(identifier: albumIdentifier) else { throw RecordAlbumError.notFound }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        guard assets.count > 0 else { throw RecordAlbumError.notFound }
        try await Self.perform {
            PHAssetCollectionChangeRequest(for: album)?.removeAssets(assets)
        }
    }

    func deleteAssets(_ ids: [String]) async -> Bool {
        guard !ids.isEmpty else { return true }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        guard assets.count > 0 else { return true }
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.deleteAssets(assets)
            }, completionHandler: { success, _ in
                continuation.resume(returning: success)
            })
        }
    }

    func changes() -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let bridge = RecordLibraryChangeBridge(continuation: continuation)
            PHPhotoLibrary.shared().register(bridge)
            continuation.onTermination = { _ in
                PHPhotoLibrary.shared().unregisterChangeObserver(bridge)
            }
        }
    }

    // MARK: Images

    func thumbnail(id: String, targetSize: CGSize) async -> UIImage? {
        try? await request(id: id, targetSize: targetSize, contentMode: .aspectFill, progress: nil)
    }

    func displayImage(id: String, targetSize: CGSize) async -> UIImage? {
        try? await request(id: id, targetSize: targetSize, contentMode: .aspectFit, progress: nil)
    }

    func fullImage(id: String, progress: @escaping @Sendable (Double) -> Void) async throws -> UIImage {
        try await request(id: id, targetSize: PHImageManagerMaximumSize, contentMode: .default, progress: progress)
    }

    func startCaching(ids: [String], targetSize: CGSize) {
        guard !ids.isEmpty else { return }
        var assets: [PHAsset] = []
        PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        cachingManager.startCachingImages(for: assets, targetSize: targetSize, contentMode: .aspectFill, options: nil)
    }

    private func request(id: String, targetSize: CGSize, contentMode: PHImageContentMode,
                         progress: (@Sendable (Double) -> Void)?) async throws -> UIImage {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else {
            throw RecordAlbumError.notFound
        }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast
        if let progress {
            options.progressHandler = { fraction, _, _, _ in progress(fraction) }
        }
        let handle = RecordImageRequestHandle()
        let image: UIImage? = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                var resumed = false
                let requestID = PHImageManager.default().requestImage(
                    for: asset, targetSize: targetSize, contentMode: contentMode, options: options
                ) { image, info in
                    if (info?[PHImageResultIsDegradedKey] as? Bool) == true { return }
                    guard !resumed else { return }
                    resumed = true
                    continuation.resume(returning: image)
                }
                handle.start(requestID)
            }
        } onCancel: {
            handle.cancel()
        }
        guard let image else { throw RecordAlbumError.failed("無法載入照片") }
        return image
    }
}

/// Carries the placeholder id out of a change block.
private final class CreatedAlbumID: @unchecked Sendable {
    var value: String?
}
