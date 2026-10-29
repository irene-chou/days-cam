import Foundation
import os
import Photos
import UIKit

/// Why a photo could not be added to the library.
///
/// The wording shown to the user lives in the view layer, next to the other
/// display messages; this type only says what went wrong (PRD §7.3).
enum PhotoSaveError: Error, Equatable {
    /// Permission to add photos was refused, or is restricted by policy. The
    /// photo was not saved, and the user has to be told exactly that.
    case permissionDenied
    /// The library refused the write — out of space, for example. The
    /// associated value is the system's description of the failure.
    case saveFailed(String)
}

/// The slice of `PHPhotoLibrary` that saving needs.
///
/// Injected so the permission branches can be unit tested: the real library
/// prompts the user and writes to their actual photos, neither of which a test
/// can drive (PRD §8).
///
/// `changes` returns the identifier of whatever it created (or `nil` if it
/// created nothing usable) rather than plain `Void`, so the completion can
/// hand the new asset's `localIdentifier` back to the caller (PRD 0.2
/// FR-15.1, TASK-28) without a second round trip to the library.
protocol PhotoLibraryAccessing {
    func authorizationStatus(for level: PHAccessLevel) -> PHAuthorizationStatus
    func requestAuthorization(for level: PHAccessLevel, handler: @escaping (PHAuthorizationStatus) -> Void)
    func performChanges(_ changes: @escaping () -> String?,
                        completion: @escaping (Bool, String?, Error?) -> Void)
    /// Creates the asset and adds it to the album in **one** change block
    /// (issue #281). The album is the one with `albumIdentifier`, else the
    /// first album titled `albumTitle`, else a new album of that title.
    /// Needs `.readWrite` full or limited access; never prompts.
    /// Title lookup is best effort: limited access can hide a user-created
    /// namesake, so creating a separate DaysCam album is expected.
    func saveToAlbum(_ image: UIImage,
                     albumIdentifier: String?,
                     albumTitle: String,
                     completion: @escaping (AlbumWriteResult) -> Void)
    /// Creates the asset and adds it to the album in one change block, like
    /// `saveToAlbum`, but never looks an album up by title: when
    /// `albumIdentifier` is `nil` or no longer resolves, a new album titled
    /// `albumTitle` is created even if a same-titled one exists (PRD 2.0
    /// §4.1). Needs full `.readWrite` access.
    func saveToRecordAlbum(_ image: UIImage,
                           albumIdentifier: String?,
                           albumTitle: String,
                           completion: @escaping (AlbumWriteResult) -> Void)
}

extension PhotoLibraryAccessing {
    /// Default for fakes that never write to a record album.
    func saveToRecordAlbum(_ image: UIImage,
                           albumIdentifier: String?,
                           albumTitle: String,
                           completion: @escaping (AlbumWriteResult) -> Void) {
        completion(AlbumWriteResult(succeeded: false, assetIdentifier: nil, albumIdentifier: nil, error: nil))
    }
}

/// Where a camera photo ended up (PRD 2.0 FR-21.4).
struct RecordSaveOutcome: Equatable {
    /// The new asset's `localIdentifier`.
    let assetID: String
    /// The record's album, or `nil` when the photo is only in 「最近項目」 and
    /// the caller has to store `assetID` as a fallback id.
    let albumID: String?
}

/// What one `saveToAlbum` change block did.
struct AlbumWriteResult {
    /// The change block committed: the asset exists and is in the album.
    let succeeded: Bool
    /// The new asset's `localIdentifier`.
    let assetIdentifier: String?
    /// The album's `localIdentifier`, found or newly created.
    let albumIdentifier: String?
    let error: Error?
}

/// Production implementation, straight through to `PHPhotoLibrary`.
struct SystemPhotoLibrary: PhotoLibraryAccessing {
    func authorizationStatus(for level: PHAccessLevel) -> PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: level)
    }

    func requestAuthorization(for level: PHAccessLevel, handler: @escaping (PHAuthorizationStatus) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: level, handler: handler)
    }

    func performChanges(_ changes: @escaping () -> String?,
                        completion: @escaping (Bool, String?, Error?) -> Void) {
        // `PHPhotoLibrary.performChanges` only ever hands the completion a
        // success flag and an error — the identifier `changes` produces (from
        // `PHAssetChangeRequest`'s placeholder, which is available
        // synchronously, before the write commits) is captured here and
        // threaded through to `completion` alongside them.
        var identifier: String?
        PHPhotoLibrary.shared().performChanges({
            identifier = changes()
        }, completionHandler: { succeeded, error in
            completion(succeeded, identifier, error)
        })
    }

    func saveToAlbum(_ image: UIImage,
                     albumIdentifier: String?,
                     albumTitle: String,
                     completion: @escaping (AlbumWriteResult) -> Void) {
        // Looked up before the change block: fetching inside one is not
        // allowed. A remembered id that no longer resolves (the user deleted
        // the album) falls back to the title, then to creating it (64.3).
        // Under limited access, title lookup may hide a user-created namesake;
        // creating another album in that case is expected (TASK-79, #306).
        let existing = Self.album(identifier: albumIdentifier) ?? Self.album(titled: albumTitle)
        var assetIdentifier: String?
        var resolvedAlbumIdentifier = existing?.localIdentifier
        PHPhotoLibrary.shared().performChanges({
            guard let asset = PHAssetChangeRequest.creationRequestForAsset(from: image)
                .placeholderForCreatedAsset else { return }
            assetIdentifier = asset.localIdentifier
            if let existing {
                PHAssetCollectionChangeRequest(for: existing)?.addAssets([asset] as NSArray)
            } else {
                let creation = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumTitle)
                creation.addAssets([asset] as NSArray)
                resolvedAlbumIdentifier = creation.placeholderForCreatedAssetCollection.localIdentifier
            }
        }, completionHandler: { succeeded, error in
            completion(AlbumWriteResult(succeeded: succeeded,
                                        assetIdentifier: assetIdentifier,
                                        albumIdentifier: resolvedAlbumIdentifier,
                                        error: error))
        })
    }

    func saveToRecordAlbum(_ image: UIImage,
                           albumIdentifier: String?,
                           albumTitle: String,
                           completion: @escaping (AlbumWriteResult) -> Void) {
        let existing = Self.album(identifier: albumIdentifier)
        var assetIdentifier: String?
        var resolvedAlbumIdentifier = existing?.localIdentifier
        PHPhotoLibrary.shared().performChanges({
            guard let asset = PHAssetChangeRequest.creationRequestForAsset(from: image)
                .placeholderForCreatedAsset else { return }
            assetIdentifier = asset.localIdentifier
            if let existing {
                PHAssetCollectionChangeRequest(for: existing)?.addAssets([asset] as NSArray)
            } else {
                let creation = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumTitle)
                creation.addAssets([asset] as NSArray)
                resolvedAlbumIdentifier = creation.placeholderForCreatedAssetCollection.localIdentifier
            }
        }, completionHandler: { succeeded, error in
            completion(AlbumWriteResult(succeeded: succeeded,
                                        assetIdentifier: assetIdentifier,
                                        albumIdentifier: resolvedAlbumIdentifier,
                                        error: error))
        })
    }

    private static func album(identifier: String?) -> PHAssetCollection? {
        guard let identifier else { return nil }
        return PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [identifier], options: nil).firstObject
    }

    private static func album(titled title: String) -> PHAssetCollection? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title = %@", title)
        return PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: options)
            .firstObject
    }
}

/// Where a photo goes (issue #281, 64.7).
enum PhotoSaveRoute: Equatable {
    /// 「最近項目」 only, through `.addOnly` — the 0.4 behaviour.
    case recentsOnly
    /// 「最近項目」 and the 「DaysCam」 album, through `.readWrite`.
    case recentsAndAlbum
}

/// Adds a finished photo to the system photo library (PRD FR-5.3).
///
/// It asks for add-only access and nothing more: the app never reads the
/// user's photos, and the photo goes to 「最近項目」 like any other capture
/// (FR-5.6). The one exception is the gallery's 「存到『DaysCam』相簿」
/// switch (issue #281): with it on and full or limited access granted, the
/// photo is also added to that album. Saving never asks for `.readWrite`
/// itself — only the switch does.
///
/// What it is handed is already final. Baking the overlay in belongs to
/// `OverlayRenderer`; by the time a photo reaches here the text is part of the
/// pixels, and nothing is written to metadata (PRD §6.2).
final class PhotoSaver {

    /// The only access level this app ever asks for (PRD FR-5.3).
    ///
    /// Named rather than inlined so a static check can confirm the app only
    /// ever asks to add, never to read the user's photos (acceptance 10.1).
    static let accessLevel: PHAccessLevel = .addOnly

    private let library: PhotoLibraryAccessing
    private let albumSettings: AlbumSaveSettings

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DaysCam",
                                       category: "photo-saver")

    /// - Parameters:
    ///   - library: the photo library; tests pass a fake.
    ///   - albumSettings: the album switch; defaults to the persisted one, so
    ///     a saver created per shot always sees the current switch.
    init(library: PhotoLibraryAccessing = SystemPhotoLibrary(),
         albumSettings: AlbumSaveSettings = AlbumSettingsStore()) {
        self.library = library
        self.albumSettings = albumSettings
    }

    /// The route for a save, given the switch and the current `.readWrite`
    /// status (issue #281, 64.7).
    ///
    /// `readWriteStatus` is only asked when the switch is on, so a save with
    /// it off checks nothing beyond `.addOnly` (64.1). Full and limited access
    /// take the album route (79.5); denied or restricted access falls back
    /// to 「最近項目」 (64.5). Never
    /// prompts.
    static func route(albumEnabled: Bool,
                      readWriteStatus: () -> PHAuthorizationStatus) -> PhotoSaveRoute {
        guard albumEnabled else { return .recentsOnly }
        let status = readWriteStatus()
        guard status == .authorized || status == .limited else { return .recentsOnly }
        return .recentsAndAlbum
    }

    /// Saves `image` to the photo library, asking for permission the first
    /// time (PRD §2.2: the prompt belongs to the first save, not to launch).
    ///
    /// `completion` runs exactly once, on the main queue. The shutter stays
    /// disabled until it does (PRD FR-5.5), so neither a missing nor a
    /// duplicated call is survivable.
    ///
    /// A refusal fails without writing anything: the caller has to tell the
    /// user the photo was not saved (PRD §2.3).
    ///
    /// This discards the new asset's identifier — kept as-is, under this
    /// exact name and signature, so `CameraScreenModel`'s existing `save` seam
    /// (its default forwards to exactly this) keeps compiling and behaving as
    /// before ui-shell wires `capturedAssetIDs` through in TASK-21. New call
    /// sites should prefer `saveReturningIdentifier` below (PRD 0.2 FR-15.1).
    ///
    /// Deliberately a *different method name* rather than an overload
    /// distinguished only by the completion closure's `Result` type: a
    /// trailing closure that discards or under-specifies its parameter (e.g.
    /// `{ _ in ... }`, as `PhotoSaverTests` already had before this method
    /// existed) cannot be resolved against two such overloads — the compiler
    /// reports "ambiguous use" rather than picking one, so every existing
    /// call site would have needed an explicit closure-parameter type
    /// annotation just to keep compiling.
    func save(_ image: UIImage, completion: @escaping (Result<Void, PhotoSaveError>) -> Void) {
        performSave(image, map: { _ in () }, completion: completion)
    }

    /// Saves `image` exactly as `save(_:completion:)` does, but on success
    /// hands back the new photo's `PHAsset.localIdentifier` — what
    /// `CapturedPhotoStore.recordCapturedAsset(_:)` needs (PRD 0.2 FR-15.1,
    /// TASK-28). This is what ui-shell's TASK-21 wiring is expected to call.
    func saveReturningIdentifier(_ image: UIImage,
                                 completion: @escaping (Result<String, PhotoSaveError>) -> Void) {
        performSave(image, map: { $0 }, completion: completion)
    }

    /// Shared permission/write logic behind both `save` methods above. `map`
    /// converts the raw identifier a successful write produces into whatever
    /// the caller promises (`Void` or the identifier itself).
    private func performSave<T>(_ image: UIImage,
                               map: @escaping (String) -> T,
                               completion: @escaping (Result<T, PhotoSaveError>) -> Void) {
        let route = Self.route(albumEnabled: albumSettings.isAlbumSavingEnabled) {
            library.authorizationStatus(for: AlbumSettingsStore.accessLevel)
        }
        if route == .recentsAndAlbum {
            writeToAlbum(image, map: map, completion: completion)
            return
        }
        saveAddOnly(image, map: map, completion: completion)
    }

    /// The `.addOnly` path: asks for permission if undecided, then writes to
    /// 「最近項目」 only.
    private func saveAddOnly<T>(_ image: UIImage,
                                map: @escaping (String) -> T,
                                completion: @escaping (Result<T, PhotoSaveError>) -> Void) {
        let accessLevel = Self.accessLevel

        switch library.authorizationStatus(for: accessLevel) {
        case .notDetermined:
            // Captured strongly on purpose: these closures are never stored,
            // so there is no cycle, and an in-flight save must answer even if
            // the caller has let go of the saver — a completion that never
            // runs leaves the shutter disabled forever.
            library.requestAuthorization(for: accessLevel) { status in
                if Self.allowsAdding(status) {
                    self.write(image, map: map, completion: completion)
                } else {
                    self.finish(.failure(.permissionDenied), completion)
                }
            }
        case let status where Self.allowsAdding(status):
            write(image, map: map, completion: completion)
        default:
            // Denied or restricted. Both are settled refusals, so re-asking
            // would do nothing but produce a prompt the system suppresses.
            finish(.failure(.permissionDenied), completion)
        }
    }

    /// Saves an exported image into 「最近項目」 only (PRD 2.0 FR-19.9): asks
    /// for `.addOnly` at most, never adds it to any album. `completion` runs
    /// once on the main queue; a refused or failed write is a `.failure`.
    func saveToRecentsOnly(_ image: UIImage,
                           completion: @escaping (Result<String, PhotoSaveError>) -> Void) {
        saveAddOnly(image, map: { $0 }, completion: completion)
    }

    /// Saves a camera photo for a record (PRD 2.0 FR-21.4), by the current
    /// `.readWrite` status (never prompts for it):
    /// - full access: saves and adds it to the record's album, creating one
    ///   titled `albumTitle` if `albumIdentifier` is `nil` or unknown;
    ///   returns `(assetID, albumID)`.
    /// - limited or undecided: saves through `.addOnly` to 「最近項目」 and
    ///   returns `(assetID, nil)`; the caller keeps `assetID` as a fallback.
    /// - denied or restricted: `.permissionDenied`, nothing written.
    /// A failed write is always a `.failure`; there is no silent retry.
    func saveToRecordAlbum(_ image: UIImage,
                           albumIdentifier: String?,
                           albumTitle: String,
                           completion: @escaping (Result<RecordSaveOutcome, PhotoSaveError>) -> Void) {
        switch library.authorizationStatus(for: .readWrite) {
        case .authorized:
            library.saveToRecordAlbum(image, albumIdentifier: albumIdentifier, albumTitle: albumTitle) { result in
                let outcome: Result<RecordSaveOutcome, PhotoSaveError>
                if !result.succeeded {
                    outcome = .failure(.saveFailed(Self.describe(result.error)))
                } else if let asset = result.assetIdentifier, let album = result.albumIdentifier {
                    outcome = .success(RecordSaveOutcome(assetID: asset, albumID: album))
                } else {
                    outcome = .failure(.saveFailed("儲存成功但未取得照片識別碼"))
                }
                self.finish(outcome, completion)
            }
        case .limited, .notDetermined:
            saveAddOnly(image, map: { RecordSaveOutcome(assetID: $0, albumID: nil) }, completion: completion)
        default:
            finish(.failure(.permissionDenied), completion)
        }
    }

    /// Whether `status` permits adding a photo.
    ///
    /// `.limited` is defensive: it belongs to the read-and-write access level
    /// and is not expected back from `.addOnly`. If it ever does come back it
    /// still means "you may add", so it is treated that way rather than
    /// falling into the refusal branch.
    private static func allowsAdding(_ status: PHAuthorizationStatus) -> Bool {
        status == .authorized || status == .limited
    }

    private func write<T>(_ image: UIImage,
                          map: @escaping (String) -> T,
                          completion: @escaping (Result<T, PhotoSaveError>) -> Void) {
        library.performChanges {
            // Creating the asset from the image is the whole change: no album
            // is created and no metadata is written (FR-5.6, PRD §6.2). The
            // placeholder's identifier is available synchronously, before the
            // write commits — this is the one place it can be read.
            PHAssetChangeRequest.creationRequestForAsset(from: image).placeholderForCreatedAsset?.localIdentifier
        } completion: { succeeded, identifier, error in
            let result: Result<T, PhotoSaveError>
            switch (succeeded, identifier) {
            case let (true, .some(identifier)):
                result = .success(map(identifier))
            case (true, .none):
                // Should not happen in practice — the placeholder always has
                // an identifier — but a success with nothing to identify it
                // by is not something the caller can act on either.
                result = .failure(.saveFailed("儲存成功但未取得照片識別碼"))
            case (false, _):
                result = .failure(.saveFailed(Self.describe(error)))
            }
            self.finish(result, completion)
        }
    }

    /// Saves into 「最近項目」 and the album in one change block. If that block
    /// fails, nothing was written, so the photo is saved again the 0.4 way:
    /// the album is a nice-to-have and must not cost the user the photo. A
    /// photo that lands only in 「最近項目」 is a success; the album failure is
    /// only logged (issue #281).
    private func writeToAlbum<T>(_ image: UIImage,
                                 map: @escaping (String) -> T,
                                 completion: @escaping (Result<T, PhotoSaveError>) -> Void) {
        library.saveToAlbum(image,
                            albumIdentifier: albumSettings.albumIdentifier,
                            albumTitle: AlbumSettingsStore.albumTitle) { result in
            if result.succeeded {
                if let album = result.albumIdentifier, album != self.albumSettings.albumIdentifier {
                    self.albumSettings.rememberAlbum(identifier: album)
                }
                // Committed, so the photo exists: never write it a second time.
                if let asset = result.assetIdentifier {
                    self.finish(.success(map(asset)), completion)
                } else {
                    self.finish(.failure(.saveFailed("儲存成功但未取得照片識別碼")), completion)
                }
                return
            }
            Self.logger.error("Adding to the album failed, saving to recents only: \(Self.describe(result.error), privacy: .public)")
            self.write(image, map: map, completion: completion)
        }
    }

    /// The library can report a failure without an error, so there is always
    /// something to show the user.
    private static func describe(_ error: Error?) -> String {
        guard let error else { return "未知錯誤" }
        return error.localizedDescription
    }

    private func finish<T>(_ result: Result<T, PhotoSaveError>,
                           _ completion: @escaping (Result<T, PhotoSaveError>) -> Void) {
        if Thread.isMainThread {
            completion(result)
        } else {
            DispatchQueue.main.async { completion(result) }
        }
    }
}
