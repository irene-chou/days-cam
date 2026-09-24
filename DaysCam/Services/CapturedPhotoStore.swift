import Foundation
import Photos

/// The slice of `PHPhotoLibrary`/`PHAsset` the read side needs: requesting
/// `.readWrite` access, and checking which of a list of identifiers still
/// resolve to a real asset.
///
/// Injected so both can be faked: neither `PHPhotoLibrary`'s prompt nor a
/// real `PHAsset` lookup can run in a unit test — there is no public
/// initializer to build a fake `PHAsset` with, the same boundary
/// `CameraServiceTests` documents for `AVCaptureDevice` (PRD §8).
protocol PhotoLibraryReadAccessing {
    func readAuthorizationStatus() -> PHAuthorizationStatus
    func requestReadAuthorization(handler: @escaping (PHAuthorizationStatus) -> Void)
    /// Returns whichever of `identifiers` still exist in the library, in no
    /// particular order — `CapturedPhotoStore` re-sorts to match
    /// `capturedAssetIDs`' own newest-first order.
    func existingIdentifiers(among identifiers: [String]) -> Set<String>
}

/// Production implementation, straight through to `PHPhotoLibrary`/`PHAsset`.
struct SystemPhotoLibraryReadAccess: PhotoLibraryReadAccessing {
    /// The only access level the read side ever asks for (PRD 0.2 FR-15.3).
    /// Saving stays on `PhotoSaver.accessLevel` (`.addOnly`) — the two are
    /// deliberately never the same request.
    static let accessLevel: PHAccessLevel = .readWrite

    func readAuthorizationStatus() -> PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: Self.accessLevel)
    }

    func requestReadAuthorization(handler: @escaping (PHAuthorizationStatus) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: Self.accessLevel, handler: handler)
    }

    func existingIdentifiers(among identifiers: [String]) -> Set<String> {
        guard !identifiers.isEmpty else { return [] }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var found: Set<String> = []
        result.enumerateObjects { asset, _, _ in found.insert(asset.localIdentifier) }
        return found
    }
}

/// Remembers which photos this app saved, and reads them back through the
/// two-stage permission model (PRD 0.2 FR-15.1, FR-15.3, FR-15.4, TASK-28).
///
/// `capturedAssetIDs` is a plain list of `PHAsset.localIdentifier` strings,
/// not `PHAsset` objects: a `PHAsset` cannot be constructed in a test either,
/// so keeping this store's public surface down to identifiers is what makes
/// it independently testable. Turning an identifier into a displayable asset
/// (thumbnail, capture timestamp for the gallery's title) is the gallery's
/// own job (TASK-29), not this store's.
///
/// Wiring a freshly-saved photo's identifier in after `PhotoSaver` succeeds is
/// ui-shell's (`CameraScreenModel`, TASK-21) — this type only holds the list
/// and answers `recordCapturedAsset(_:)` when asked to.
final class CapturedPhotoStore: ObservableObject {
    static let fileName = "photos.json"

    /// Every DaysCam-saved photo's `localIdentifier`, newest first
    /// (PRD 0.2 §4.4). Not filtered against the library until `fetchAssets()`
    /// is called — reading it directly (e.g. for FR-15.2's "does this app
    /// have anything to fall back to at all") never needs `.readWrite`.
    @Published private(set) var capturedAssetIDs: [String]

    private let directory: URL
    private let fileManager: FileManager
    private let library: PhotoLibraryReadAccessing

    /// Creates a store, loading whatever was previously persisted.
    ///
    /// - Parameters:
    ///   - directory: where `photos.json` lives. Defaults to
    ///     `Application Support/DaysCam` — the same directory `ProfileStore`
    ///     uses, with its own file name. Tests pass a temporary directory.
    ///   - library: read-permission and existence-check seam; defaults to the
    ///     real `PHPhotoLibrary`/`PHAsset`.
    init(directory: URL? = nil,
         fileManager: FileManager = .default,
         library: PhotoLibraryReadAccessing = SystemPhotoLibraryReadAccess()) {
        let resolvedDirectory = directory ?? Self.defaultDirectory(fileManager: fileManager)
        self.directory = resolvedDirectory
        self.fileManager = fileManager
        self.library = library
        self.capturedAssetIDs = Self.readIDs(from: resolvedDirectory.appendingPathComponent(Self.fileName))
    }

    /// The file the identifiers are stored in.
    var fileURL: URL {
        directory.appendingPathComponent(Self.fileName)
    }

    private static func defaultDirectory(fileManager: FileManager) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let root = base ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return root.appendingPathComponent("DaysCam", isDirectory: true)
    }

    /// Reads the stored identifiers, treating anything missing or unreadable
    /// as an empty list rather than crashing — the photos themselves are
    /// still safe in the system library either way (acceptance 28.5).
    private static func readIDs(from url: URL) -> [String] {
        guard let data = try? Data(contentsOf: url),
              let ids = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return ids
    }
}

// MARK: - Recording (PRD 0.2 FR-15.1)

extension CapturedPhotoStore {
    /// Adds `assetID` to the front of `capturedAssetIDs` and persists it.
    ///
    /// Called once per successful save, with `PhotoSaver`'s returned
    /// identifier. The wiring itself — calling this after a save completes —
    /// is `CameraScreenModel`'s (ui-shell, TASK-21); this method is what it
    /// calls.
    func recordCapturedAsset(_ assetID: String) {
        var updated = capturedAssetIDs
        updated.removeAll { $0 == assetID } // defensive: never store the same id twice
        updated.insert(assetID, at: 0)
        capturedAssetIDs = updated
        persist(updated)
    }

    /// Writes `ids` atomically, creating the directory if needed. Mirrors
    /// `ProfileStore.persist`'s reasoning: `.atomic` swaps a temporary file
    /// in, so a crash or a full disk leaves the previous file intact.
    ///
    /// A write failure here is silently dropped rather than thrown: the
    /// photo itself already landed in the system library via `PhotoSaver` by
    /// the time this runs, so losing this write only risks a stale gallery
    /// list after a relaunch — not the data loss `ProfileStore.persist`
    /// guards against.
    private func persist(_ ids: [String]) {
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(ids)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            // Nothing to report to: see the doc comment above.
        }
    }
}

// MARK: - Reading (PRD 0.2 FR-15.4)

extension CapturedPhotoStore {
    /// The still-existing captured photos, newest first — pruning any
    /// identifier the system library no longer has (deleted from the Photos
    /// app) from both the published list and the file (acceptance 28.2).
    @discardableResult
    func fetchAssets() -> [String] {
        let existing = library.existingIdentifiers(among: capturedAssetIDs)
        let pruned = capturedAssetIDs.filter { existing.contains($0) }
        if pruned != capturedAssetIDs {
            capturedAssetIDs = pruned
            persist(pruned)
        }
        return pruned
    }
}

// MARK: - Read permission (PRD 0.2 FR-15.3)

extension CapturedPhotoStore {
    /// Requests `.readWrite` access the first time it is needed (acceptance
    /// 28.4): a no-op whenever the status is already settled — granted,
    /// limited, denied or restricted — since the system suppresses a repeat
    /// prompt anyway and re-asking a settled grant needlessly is not
    /// something a caller should have to guard against itself.
    ///
    /// Saving is unaffected: `PhotoSaver` only ever asks for `.addOnly`, and
    /// nothing about this method changes that (PRD 0.2 acceptance 28.3).
    func requestReadAccessIfNeeded(completion: ((PHAuthorizationStatus) -> Void)? = nil) {
        let status = library.readAuthorizationStatus()
        guard status == .notDetermined else {
            completion?(status)
            return
        }
        library.requestReadAuthorization { newStatus in
            completion?(newStatus)
        }
    }
}
