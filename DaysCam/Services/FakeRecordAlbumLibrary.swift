#if DEBUG
import Photos
import UIKit

/// In-memory `RecordAlbumLibrary` for unit and UI tests: albums and photos
/// live in arrays, the authorization status and failures are settable. It
/// shares `RecordAlbumLogic` with the system implementation.
@MainActor
final class FakeRecordAlbumLibrary: RecordAlbumLibrary {
    struct Asset: Equatable {
        let id: String
        var mediaType: PHAssetMediaType = .image
        var creationDate: Date?
    }

    struct Album: Equatable {
        let id: String
        var title: String
        var assetIDs: [String]
    }

    var status: PHAuthorizationStatus
    /// What `requestReadWriteAccess` answers when the status is undecided.
    var grants: PHAuthorizationStatus = .authorized
    private(set) var assets: [Asset]
    private(set) var albums: [Album]
    /// Under `.limited`, only these assets are visible; `nil` means all.
    var visibleIDs: Set<String>?
    /// Non-nil makes `addAssets`, `removeAsset` and `fullImage` throw it.
    var failure: RecordAlbumError?
    /// Result of `deleteAsset` (`false` = the user cancelled the dialog).
    var confirmsDeletion = true
    /// How many times an album's contents were read (limited access must not).
    private(set) var albumReadCount = 0
    private var nextID = 1

    init(status: PHAuthorizationStatus = .authorized, assets: [Asset] = [], albums: [Album] = []) {
        self.status = status
        self.assets = assets
        self.albums = albums
    }

    // MARK: Test setup

    func addAsset(_ asset: Asset) { assets.append(asset) }
    func removeFromLibrary(_ id: String) {
        assets.removeAll { $0.id == id }
        for index in albums.indices { albums[index].assetIDs.removeAll { $0 == id } }
    }

    // MARK: RecordAlbumLibrary

    func authorizationStatus() -> PHAuthorizationStatus { status }

    func requestReadWriteAccess() async -> PHAuthorizationStatus {
        if status == .notDetermined { status = grants }
        return status
    }

    private func visibleImage(_ id: String) -> RecordPhoto? {
        guard let asset = assets.first(where: { $0.id == id }), asset.mediaType == .image else { return nil }
        if status == .limited, let visibleIDs, !visibleIDs.contains(id) { return nil }
        return RecordPhoto(id: id, creationDate: asset.creationDate)
    }

    func photos(albumIdentifier: String?, fallbackIDs: [String]) -> [RecordPhoto] {
        let primary: [RecordPhoto]
        switch RecordReadMode(status: status) {
        case .none:
            return []
        case .album:
            albumReadCount += 1
            let ids = albums.first { $0.id == albumIdentifier }?.assetIDs ?? []
            primary = ids.compactMap(visibleImage)
        case .allVisible:
            primary = assets.compactMap { visibleImage($0.id) }
        }
        return RecordAlbumLogic.merge(primary, fallbackIDs.compactMap(visibleImage))
    }

    func photoCount(albumIdentifier: String?, fallbackIDs: [String]) -> Int? {
        guard RecordReadMode(status: status) != .none else { return nil }
        return photos(albumIdentifier: albumIdentifier, fallbackIDs: fallbackIDs).count
    }

    func userAlbums() -> [AlbumSummary] {
        guard status == .authorized else { return [] }
        return albums.map { album in
            AlbumSummary(id: album.id, title: album.title,
                         photoCount: album.assetIDs.compactMap(visibleImage).count)
        }
    }

    func addAssets(_ ids: [String], albumIdentifier: String?, albumTitle: String) async throws -> String {
        if let failure { throw failure }
        guard status == .authorized else { throw RecordAlbumError.permissionDenied }
        guard ids.allSatisfy({ id in assets.contains { $0.id == id } }) else { throw RecordAlbumError.notFound }
        if let index = albums.firstIndex(where: { $0.id == albumIdentifier }) {
            for id in ids where !albums[index].assetIDs.contains(id) { albums[index].assetIDs.append(id) }
            return albums[index].id
        }
        let id = "fake-album-\(nextID)"
        nextID += 1
        albums.append(Album(id: id, title: albumTitle, assetIDs: ids))
        return id
    }

    func removeAsset(_ id: String, fromAlbum albumIdentifier: String) async throws {
        if let failure { throw failure }
        guard let index = albums.firstIndex(where: { $0.id == albumIdentifier }) else { throw RecordAlbumError.notFound }
        albums[index].assetIDs.removeAll { $0 == id }
    }

    func deleteAsset(_ id: String) async -> Bool {
        guard confirmsDeletion else { return false }
        removeFromLibrary(id)
        return true
    }

    func changes() -> AsyncStream<Void> { AsyncStream { $0.finish() } }

    func thumbnail(id: String, targetSize: CGSize) async -> UIImage? { Self.solidImage(for: id, size: targetSize) }

    func displayImage(id: String, targetSize: CGSize) async -> UIImage? { Self.solidImage(for: id, size: targetSize) }

    func fullImage(id: String, progress: @escaping @Sendable (Double) -> Void) async throws -> UIImage {
        if let failure { throw failure }
        progress(1)
        guard let image = Self.solidImage(for: id, size: CGSize(width: 64, height: 64)) else {
            throw RecordAlbumError.failed("無法載入照片")
        }
        return image
    }

    private static func solidImage(for id: String, size: CGSize) -> UIImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        let hue = CGFloat(abs(id.hashValue) % 360) / 360
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor(hue: hue, saturation: 0.5, brightness: 0.9, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}

extension FakeRecordAlbumLibrary {
    /// `n` still photos, one per day ending on `today`, oldest first:
    /// ids `uitest-photo-1…n`, no album.
    static func generatedPhotos(count: Int, today: Date, calendar: Calendar = .autoupdatingCurrent) -> [Asset] {
        guard count > 0 else { return [] }
        return (0..<count).map { offset in
            let daysAgo = count - 1 - offset
            return Asset(id: "uitest-photo-\(offset + 1)",
                         creationDate: calendar.date(byAdding: .day, value: -daysAgo, to: today))
        }
    }

    /// The library for UI tests: with `-UITestRecordPhotos <n>` it holds `n`
    /// generated photos dated one per day back from `DAYSCAM_FAKE_TODAY`
    /// (or the real today). `nil` without the argument, so the caller uses
    /// the real library. `-UITestPhotoAccess` picks the status (default full).
    static func forUITests(arguments: [String] = ProcessInfo.processInfo.arguments,
                           environment: [String: String] = ProcessInfo.processInfo.environment,
                           calendar: Calendar = .autoupdatingCurrent) -> FakeRecordAlbumLibrary? {
        guard let index = arguments.firstIndex(of: "-UITestRecordPhotos"),
              arguments.indices.contains(index + 1),
              let count = Int(arguments[index + 1]) else { return nil }
        let today = DayCountCalculator.debugFakeToday(environment: environment, calendar: calendar) ?? Date()
        var status = PHAuthorizationStatus.authorized
        if let accessIndex = arguments.firstIndex(of: "-UITestPhotoAccess"),
           arguments.indices.contains(accessIndex + 1) {
            switch arguments[accessIndex + 1] {
            case "limited": status = .limited
            case "denied", "withdrawn": status = .denied
            default: break
            }
        }
        return FakeRecordAlbumLibrary(status: status, assets: generatedPhotos(count: count, today: today, calendar: calendar))
    }
}
#endif
