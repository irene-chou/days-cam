import Foundation

/// A reason a profile operation could not be completed.
enum ProfileStoreError: Error, Equatable {
    /// The profile limit has been reached; nothing was written (PRD FR-1.7).
    case limitReached(limit: Int)
    /// The only remaining profile cannot be deleted (PRD FR-1.8).
    case lastProfile
    /// No stored profile has this identifier.
    case profileNotFound(id: UUID)
    /// The profile violates one of the PRD §4.1 invariants.
    case invalidProfile(CameraProfileValidationError)
    /// The file could not be written; the previous contents are intact.
    case writeFailed(String)
}

/// Stores the camera profiles as a single JSON file and enforces the PRD §4.1
/// invariants on the way in and on the way out.
///
/// The clock, the calendar, the directory and the defaults are all injected so
/// the whole thing can be exercised against a temporary directory without
/// touching the real one (PRD §8).
///
/// Validation deliberately lives here rather than in `CameraProfile`'s
/// initializer: an editing screen needs to hold a half-finished profile, so
/// this is the layer that decides what may be persisted.
final class ProfileStore: ObservableObject {
    /// Maximum number of profiles (PRD FR-1.7).
    static let profileLimit = 20
    static let fileName = "profiles.json"
    /// `UserDefaults` key holding the profile to restore on next launch.
    static let lastUsedProfileIDKey = "lastUsedProfileID"

    /// Every stored profile, in insertion order.
    @Published private(set) var profiles: [CameraProfile] = []
    /// The profile the camera screen is using. Always points at an existing
    /// profile once `load()` has run and the list is non-empty.
    @Published private(set) var selectedProfileID: UUID?
    /// True when the last `load()` left the user with none of their own
    /// profiles and re-seeded: an unreadable file, or a readable one whose
    /// every record failed validation.
    ///
    /// The camera screen shows a one-off alert for this (PRD §7.3).
    @Published private(set) var didRecoverFromCorruption = false

    private let directory: URL
    private let calendar: Calendar
    private let now: () -> Date
    private let defaults: UserDefaults
    private let fileManager: FileManager

    /// Creates a store.
    ///
    /// - Parameter directory: where `profiles.json` lives. Defaults to
    ///   `Application Support/DaysCam`; tests pass a temporary directory.
    init(directory: URL? = nil,
         calendar: Calendar = .autoupdatingCurrent,
         now: @escaping () -> Date = DayCountCalculator.defaultNow(),
         defaults: UserDefaults = .standard,
         fileManager: FileManager = .default) {
        self.directory = directory ?? Self.defaultDirectory(fileManager: fileManager)
        self.calendar = calendar
        self.now = now
        self.defaults = defaults
        self.fileManager = fileManager
    }

    /// The file the profiles are stored in.
    var fileURL: URL {
        directory.appendingPathComponent(Self.fileName)
    }

    private static func defaultDirectory(fileManager: FileManager) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let root = base ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return root.appendingPathComponent("DaysCam", isDirectory: true)
    }
}

// MARK: - Loading

extension ProfileStore {
    /// Reads the profiles, seeding or repairing as needed.
    ///
    /// Three outcomes: no file yet seeds one default profile; an unreadable
    /// file is set aside and re-seeded; a readable file has each record
    /// validated, with repairable ones cleaned up and hopeless ones dropped
    /// (PRD §4.1, §7.3).
    @discardableResult
    func load() -> [CameraProfile] {
        didRecoverFromCorruption = false

        guard fileManager.fileExists(atPath: fileURL.path) else {
            seedDefaultProfile()
            return profiles
        }

        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([CameraProfile].self, from: data) else {
            setAsideCorruptFile()
            didRecoverFromCorruption = true
            seedDefaultProfile()
            return profiles
        }

        // Strip what can be stripped, drop what cannot be repaired. This is
        // defence in depth — only the app writes this file — which is why a
        // dropped record is not surfaced to the user (PRD §7.3).
        let repaired = decoded.compactMap { try? $0.validatedForPersistence(calendar: calendar) }

        if repaired.isEmpty {
            // A file that decodes but holds no usable record looks exactly like
            // a lost file from the user's side: every profile of theirs is
            // gone. So it gets the same one-off alert as an unreadable file.
            // The test is "is the user left with anything of their own", which
            // is why a single dropped record stays silent (PRD §7.3).
            //
            // Seeding on a fresh install is not a loss and never reaches here:
            // that case returns above, before the file is read.
            //
            // The file is set aside for the same reason an unreadable one is:
            // re-seeding overwrites it, and it holds the only copy of what the
            // user configured, however invalid this build found it.
            setAsideCorruptFile()
            didRecoverFromCorruption = true
            seedDefaultProfile()
            return profiles
        }

        profiles = repaired
        resolveSelection()
        // Persist the cleaned-up records so the repair happens once, not on
        // every launch.
        if repaired != decoded {
            try? persist(repaired)
        }
        return profiles
    }

    /// Writes the one profile a fresh install starts with (PRD §4.3).
    private func seedDefaultProfile() {
        let today = calendar.dateComponents([.year, .month, .day], from: now())
        let timestamp = now()
        let seeded = CameraProfile(name: "預設",
                                   startDate: today,
                                   createdAt: timestamp,
                                   updatedAt: timestamp)
        profiles = [seeded]
        try? persist(profiles)
        select(id: seeded.id)
    }

    /// Renames an unreadable file rather than deleting it, so the user's data
    /// can still be recovered by hand (PRD §7.3).
    private func setAsideCorruptFile() {
        let stamp = Int(now().timeIntervalSince1970)
        let destination = directory.appendingPathComponent("\(Self.fileName).corrupt-\(stamp)")
        try? fileManager.removeItem(at: destination)
        try? fileManager.moveItem(at: fileURL, to: destination)
    }
}

// MARK: - Mutating

extension ProfileStore {
    /// Validates and stores a new profile.
    ///
    /// Returns the profile as stored, which may differ from the argument: the
    /// name is trimmed and the start date is reduced to year/month/day.
    @discardableResult
    func add(_ profile: CameraProfile) throws -> CameraProfile {
        guard profiles.count < Self.profileLimit else {
            throw ProfileStoreError.limitReached(limit: Self.profileLimit)
        }
        var candidate = try validated(profile)
        let timestamp = now()
        candidate.createdAt = timestamp
        candidate.updatedAt = timestamp

        var updated = profiles
        updated.append(candidate)
        try persist(updated)
        profiles = updated
        // A new profile becomes the active one (PRD FR-1.10).
        select(id: candidate.id)
        return candidate
    }

    /// Validates and overwrites an existing profile, keeping its `createdAt`.
    @discardableResult
    func update(_ profile: CameraProfile) throws -> CameraProfile {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else {
            throw ProfileStoreError.profileNotFound(id: profile.id)
        }
        var candidate = try validated(profile)
        // `createdAt` belongs to the record, not to whoever is editing it.
        candidate.createdAt = profiles[index].createdAt
        candidate.updatedAt = now()

        var updated = profiles
        updated[index] = candidate
        try persist(updated)
        profiles = updated
        return candidate
    }

    /// Deletes a profile, refusing to remove the last one (PRD FR-1.8).
    func delete(id: UUID) throws {
        guard profiles.contains(where: { $0.id == id }) else {
            throw ProfileStoreError.profileNotFound(id: id)
        }
        guard profiles.count > 1 else {
            throw ProfileStoreError.lastProfile
        }

        var updated = profiles
        updated.removeAll { $0.id == id }
        try persist(updated)
        profiles = updated
        resolveSelection()
    }

    private func validated(_ profile: CameraProfile) throws -> CameraProfile {
        do {
            return try profile.validatedForPersistence(calendar: calendar)
        } catch let error as CameraProfileValidationError {
            throw ProfileStoreError.invalidProfile(error)
        }
    }
}

// MARK: - Ordering, duplicating, naming (PRD 0.2 FR-9, TASK-20)

extension ProfileStore {
    /// Reorders `profiles` — the model behind PRD 0.2 FR-9.4's drag handle —
    /// and persists immediately, the same way FR-9.4 describes ("放開後立即
    /// 持久化"). Takes the same `(IndexSet, Int)` shape SwiftUI's `.onMove`
    /// hands a view, so ui-shell's list can forward it unchanged.
    func move(fromOffsets source: IndexSet, toOffset destination: Int) throws {
        // Implemented by hand rather than with `Array.move(fromOffsets:toOffset:)`,
        // which is a SwiftUI extension: the data layer must not depend on
        // SwiftUI (CLAUDE.md), and only compiles today because another file in
        // the module happens to import it. Semantics match SwiftUI's version.
        var updated = profiles
        let moving = source.map { updated[$0] }
        for index in source.reversed() {
            updated.remove(at: index)
        }
        let insertionIndex = destination - source.count(in: 0..<destination)
        updated.insert(contentsOf: moving, at: insertionIndex)
        try persist(updated)
        profiles = updated
    }

    /// Inserts a copy of the profile named `id` directly after it: a new
    /// identity, fresh timestamps, and the name "{原名} 副本" — auto-numbered
    /// through `uniqueName(base:)` if that name is already taken (PRD 0.2
    /// FR-9.5, FR-9.9).
    ///
    /// Deliberately does **not** change `selectedProfileID` (PRD 0.2 A-3):
    /// unlike `add(_:)`, which PRD FR-1.10 says must switch to what it just
    /// created, a duplicate is meant to sit alongside the original without
    /// disturbing whatever is currently on screen.
    @discardableResult
    func duplicate(id: UUID) throws -> CameraProfile {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else {
            throw ProfileStoreError.profileNotFound(id: id)
        }
        guard profiles.count < Self.profileLimit else {
            throw ProfileStoreError.limitReached(limit: Self.profileLimit)
        }

        let source = profiles[index]
        // Only the original name is ever truncated — never " 副本" and never
        // the disambiguating number — so the result always ends with
        // "副本" or "副本 N" (PRD 0.2 FR-9.9, acceptance 20.5).
        let name = uniqueName(base: source.name, keeping: Self.duplicateSuffix)

        let timestamp = now()
        let duplicated = CameraProfile(name: name,
                                       startDate: source.startDate,
                                       countingRule: source.countingRule,
                                       showDayCount: source.showDayCount,
                                       showDate: source.showDate,
                                       showName: source.showName,
                                       largestUnit: source.largestUnit,
                                       smallestUnit: source.smallestUnit,
                                       useAgeWording: source.useAgeWording,
                                       position: source.position,
                                       style: source.style,
                                       createdAt: timestamp,
                                       updatedAt: timestamp)

        var updated = profiles
        updated.insert(duplicated, at: index + 1)
        try persist(updated)
        profiles = updated
        return duplicated
    }

    /// The suffix `duplicate(id:)` appends to a copied profile's name
    /// (PRD 0.2 FR-9.5).
    private static let duplicateSuffix = " 副本"

    /// A name that does not collide with any current profile's name
    /// (PRD 0.2 FR-9.9): `base` followed by `tag` if nothing already has that
    /// exact name, otherwise with " 2", " 3", … appended until free.
    ///
    /// Only `base` is truncated — never `tag` and never the numbering —
    /// whenever the combination would exceed `CameraProfile.maximumNameLength`,
    /// so the result is always immediately valid for `validate(calendar:)`.
    /// A brand-new "新設定檔" (ui-shell, TASK-26) passes no tag;
    /// `duplicate(id:)` passes " 副本" so repeated copies of a long name
    /// become "…副本 2" instead of losing "副本".
    func uniqueName(base: String, keeping tag: String = "") -> String {
        let existingNames = Set(profiles.map(\.name))

        func compose(numberSuffix: String) -> String {
            let maxBaseLength = max(0, CameraProfile.maximumNameLength - tag.count - numberSuffix.count)
            return String(base.prefix(maxBaseLength)) + tag + numberSuffix
        }

        let unnumbered = compose(numberSuffix: "")
        guard existingNames.contains(unnumbered) else {
            return unnumbered
        }

        var number = 2
        while true {
            let candidate = compose(numberSuffix: " \(number)")
            if !existingNames.contains(candidate) {
                return candidate
            }
            number += 1
        }
    }
}

// MARK: - Selection

extension ProfileStore {
    /// The profile to restore on next launch, falling back to the first one
    /// when the stored identifier no longer exists (PRD §4.2).
    var lastUsedProfileID: UUID? {
        if let raw = defaults.string(forKey: Self.lastUsedProfileIDKey),
           let stored = UUID(uuidString: raw),
           profiles.contains(where: { $0.id == stored }) {
            return stored
        }
        return profiles.first?.id
    }

    /// Makes `id` the active profile and remembers it for next launch.
    func select(id: UUID) {
        defaults.set(id.uuidString, forKey: Self.lastUsedProfileIDKey)
        selectedProfileID = id
    }

    /// Points the selection at a profile that actually exists.
    private func resolveSelection() {
        let resolved = lastUsedProfileID
        selectedProfileID = resolved
        if let resolved {
            defaults.set(resolved.uuidString, forKey: Self.lastUsedProfileIDKey)
        }
    }
}

// MARK: - Writing

private extension ProfileStore {
    /// Writes the profiles atomically, creating the directory if needed.
    ///
    /// `.atomic` writes to a temporary file and swaps it in, so a crash or a
    /// full disk leaves the previous file intact rather than truncated
    /// (PRD §4.3).
    func persist(_ profiles: [CameraProfile]) throws {
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(profiles)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            throw ProfileStoreError.writeFailed(String(describing: error))
        }
    }
}
