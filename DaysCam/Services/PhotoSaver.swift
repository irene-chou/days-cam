import Foundation
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
}

/// Adds a finished photo to the system photo library (PRD FR-5.3).
///
/// It asks for add-only access and nothing more: the app never reads the
/// user's photos. It also never creates an album — the photo goes to
/// 「最近項目」 like any other capture (FR-5.6).
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

    init(library: PhotoLibraryAccessing = SystemPhotoLibrary()) {
        self.library = library
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
