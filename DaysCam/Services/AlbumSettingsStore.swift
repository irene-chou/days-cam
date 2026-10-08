import Foundation
import Photos

/// What `PhotoSaver` needs to know about the 「存到『DaysCam』相簿」 switch
/// (issue #281).
///
/// Read and written from whatever queue the photo library calls back on, so
/// implementations must not touch UI state here.
protocol AlbumSaveSettings: AnyObject {
    /// Whether the user has turned the switch on. Says nothing about whether
    /// permission is still there; `PhotoSaver` checks that on every save.
    var isAlbumSavingEnabled: Bool { get }
    /// The 「DaysCam」 album's `PHAssetCollection.localIdentifier`, once one
    /// has been found or created.
    var albumIdentifier: String? { get }
    /// Remembers the album found or created by a save.
    func rememberAlbum(identifier: String)
}

/// How a request for full photo access ended, as the gallery switch shows it
/// (issue #281, 64.4).
enum AlbumAccessResult: Equatable {
    /// `.authorized`: the switch is now on.
    case full
    /// `.limited`: treated as no permission; the switch stays off.
    case limited
    /// Denied, restricted, or anything else: the switch stays off.
    case denied
}

/// Holds the 「存到『DaysCam』相簿」 switch and the remembered album
/// (issue #281). Off by default; survives a relaunch via `UserDefaults`.
///
/// Turning the switch on is the only path in the app that asks for
/// `.readWrite` in order to save (PRD 0.2 FR-5.3′ exception). Nothing here
/// asks at creation, so creating the store at launch never prompts.
final class AlbumSettingsStore: ObservableObject, AlbumSaveSettings {
    private enum Keys {
        static let savesToAlbum = "savesToDaysCamAlbum"
        static let albumIdentifier = "daysCamAlbumIdentifier"
    }

    /// The album's fixed name; 0.5 has no custom names.
    static let albumTitle = "DaysCam"

    /// The access level the switch needs. Limited access cannot reliably
    /// create or add to an album, so only `.authorized` counts.
    static let accessLevel: PHAccessLevel = .readWrite

    /// The switch as the gallery shows it. Main queue only.
    @Published private(set) var savesToAlbum: Bool

    private let defaults: UserDefaults
    private let library: PhotoLibraryAccessing

    /// Creates a store, restoring the switch from `defaults`. Never touches
    /// the photo library.
    ///
    /// - Parameters:
    ///   - defaults: where the switch and album id live; tests pass an
    ///     isolated suite.
    ///   - library: used only by `requestEnabling` and `reconcile`.
    init(defaults: UserDefaults = .standard, library: PhotoLibraryAccessing = SystemPhotoLibrary()) {
        self.defaults = defaults
        self.library = library
        savesToAlbum = defaults.bool(forKey: Keys.savesToAlbum)
    }

    // MARK: AlbumSaveSettings

    var isAlbumSavingEnabled: Bool {
        defaults.bool(forKey: Keys.savesToAlbum)
    }

    var albumIdentifier: String? {
        defaults.string(forKey: Keys.albumIdentifier)
    }

    func rememberAlbum(identifier: String) {
        defaults.set(identifier, forKey: Keys.albumIdentifier)
    }

    // MARK: Switch

    /// The user turned the switch on (64.2, 64.4).
    ///
    /// Asks for `.readWrite` only if it has not been decided yet; the switch
    /// goes on only with full access. `completion` runs once, on the main
    /// queue; on anything but `.full` the gallery shows the 「前往設定」 notice.
    func requestEnabling(completion: @escaping (AlbumAccessResult) -> Void) {
        let status = library.authorizationStatus(for: Self.accessLevel)
        guard status == .notDetermined else {
            finishEnabling(with: status, completion: completion)
            return
        }
        library.requestAuthorization(for: Self.accessLevel) { granted in
            self.finishEnabling(with: granted, completion: completion)
        }
    }

    /// The user turned the switch off. Never prompts.
    func disable() {
        setSavesToAlbum(false)
    }

    /// Call when the gallery appears (64.5). If the switch is on but full
    /// access has since been withdrawn, turns the switch off and returns
    /// true, once: the gallery shows its notice for that. Reads the status
    /// without prompting.
    @discardableResult
    func reconcile() -> Bool {
        guard savesToAlbum, library.authorizationStatus(for: Self.accessLevel) != .authorized else {
            return false
        }
        setSavesToAlbum(false)
        return true
    }

    /// Maps a settled status to the switch result.
    static func accessResult(for status: PHAuthorizationStatus) -> AlbumAccessResult {
        switch status {
        case .authorized: return .full
        case .limited: return .limited
        default: return .denied
        }
    }

    private func finishEnabling(with status: PHAuthorizationStatus,
                                completion: @escaping (AlbumAccessResult) -> Void) {
        let result = Self.accessResult(for: status)
        let apply = {
            self.setSavesToAlbum(result == .full)
            completion(result)
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    private func setSavesToAlbum(_ newValue: Bool) {
        defaults.set(newValue, forKey: Keys.savesToAlbum)
        if savesToAlbum != newValue { savesToAlbum = newValue }
    }
}
