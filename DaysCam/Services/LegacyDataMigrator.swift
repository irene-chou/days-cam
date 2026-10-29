import Foundation

/// Moves 1.3.0 data into the 2.0 profile model (PRD-2.0 §4.2, §4.3 M-1~M-5).
///
/// Purely local: it reads `photos.json` and two `UserDefaults` keys and never
/// touches the photo library, so launching 2.0 asks for no permission.
/// `ProfileStore.load()` drives it and owns the write order (new
/// `profiles.json` first, version number second).
enum LegacyDataMigrator {
    /// `UserDefaults` key holding the data version; missing means 1 (1.x).
    static let dataVersionKey = "profileDataVersion"
    /// The data version 2.0 writes.
    static let currentDataVersion = 2
    /// Copy of the 1.x `profiles.json`, kept beside it.
    static let backupFileName = "profiles.v1.json"

    // Mirrors `AlbumSettingsStore`'s private keys; that store is retired in #621.
    private static let albumIdentifierKey = "daysCamAlbumIdentifier"

    /// True while `defaults` still holds 1.x data.
    static func needsMigration(defaults: UserDefaults) -> Bool {
        defaults.integer(forKey: dataVersionKey) < currentDataVersion
    }

    /// Records that migration finished.
    static func markMigrated(defaults: UserDefaults) {
        defaults.set(currentDataVersion, forKey: dataVersionKey)
    }

    /// Copies `profiles.json` to `profiles.v1.json` once (M-4).
    ///
    /// Returns false only when a needed copy failed; an existing backup is
    /// left alone, and a missing source needs no backup.
    static func backUpProfilesFile(in directory: URL,
                                   profilesFileName: String,
                                   fileManager: FileManager) -> Bool {
        let source = directory.appendingPathComponent(profilesFileName)
        let backup = directory.appendingPathComponent(backupFileName)
        guard fileManager.fileExists(atPath: source.path) else { return true }
        guard !fileManager.fileExists(atPath: backup.path) else { return true }
        do {
            try fileManager.copyItem(at: source, to: backup)
            return true
        } catch {
            return false
        }
    }

    /// True when a missing `profiles.json` still comes with 1.x leftovers: a
    /// non-empty `photos.json`, a remembered album, a v1 backup or a
    /// `profiles.json.corrupt-*` set-aside file. Such an install is not fresh.
    static func hasLegacyData(in directory: URL,
                              profilesFileName: String,
                              photosFileName: String,
                              defaults: UserDefaults,
                              fileManager: FileManager) -> Bool {
        if !legacyAssetIDs(at: directory.appendingPathComponent(photosFileName)).isEmpty { return true }
        if let album = defaults.string(forKey: albumIdentifierKey), !album.isEmpty { return true }
        let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.contains { $0 == backupFileName || $0.hasPrefix("\(profilesFileName).corrupt-") }
    }

    /// Returns `profiles` with the legacy photo IDs and album attached to the
    /// profile `targetID` (M-2, M-3).
    ///
    /// IDs are appended as stored, unfiltered and in order, skipping any the
    /// profile already holds so a retry never duplicates them. An existing
    /// `albumIdentifier` is kept.
    static func migrated(_ profiles: [CameraProfile],
                         targetID: UUID?,
                         photosURL: URL,
                         defaults: UserDefaults) -> [CameraProfile] {
        guard let targetID, let index = profiles.firstIndex(where: { $0.id == targetID }) else {
            return profiles
        }
        var result = profiles
        var seen = Set(result[index].fallbackAssetIDs)
        for id in legacyAssetIDs(at: photosURL) where seen.insert(id).inserted {
            result[index].fallbackAssetIDs.append(id)
        }
        if result[index].albumIdentifier == nil,
           let album = defaults.string(forKey: albumIdentifierKey), !album.isEmpty {
            result[index].albumIdentifier = album
        }
        return result
    }

    /// The IDs in `photos.json`, or empty when it is missing or unreadable.
    private static func legacyAssetIDs(at url: URL) -> [String] {
        guard let data = try? Data(contentsOf: url),
              let ids = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return ids
    }
}
