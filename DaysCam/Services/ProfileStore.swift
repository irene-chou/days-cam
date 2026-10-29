import Foundation
import os
import UIKit

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

    /// Name of the profile a fresh install (or a rebuilt, unreadable store) starts with.
    static let defaultProfileName = "我的紀錄"
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
    /// True only when this launch's `load()` found no profile file at all and
    /// seeded the default profile — a fresh install (TASK-96, #400). An
    /// unreadable file, or one holding no usable record, is re-seeded too,
    /// but that is an existing install (`didRecoverFromCorruption`), so this
    /// stays `false` there. Read-only; it changes nothing about how profiles
    /// are read or written.
    private(set) var didSeedFreshInstall = false
    /// How many records the last `load()` could not decode and dropped while
    /// keeping the rest (TASK-134, #474) — typically a file written by a newer
    /// build. Zero when nothing was dropped, and when the whole file was
    /// unusable (that is `didRecoverFromCorruption`). The original file is
    /// kept beside it as `profiles.json.partial-<timestamp>`. Flag only; no UI
    /// reads it yet.
    private(set) var droppedUndecodableRecordCount = 0

    /// True while the original file still has to be copied to a
    /// `.partial-` backup before anything may overwrite it (#477). Every write
    /// retries the copy first and fails with `writeFailed` if it still cannot
    /// be made, so the undecodable records are never lost without a copy.
    private(set) var isPartialBackupPending = false

    /// The most recent background write failure, or nil once a write succeeds
    /// (TASK-124, #464). In-memory `profiles` is never rolled back; the failed
    /// snapshot stays queued and the next write (or `flush()`) retries it.
    /// Nothing reads it yet; the upper layer decides how to show it.
    @Published private(set) var lastWriteError: ProfileStoreError?

    /// Writes bytes to the file; replaced in tests to count, fail or observe
    /// the calling thread.
    typealias DataWriter = (Data, URL) throws -> Void
    /// Runs `work` after `delay` seconds; replaced in tests so nothing sleeps.
    typealias Scheduler = (TimeInterval, DispatchWorkItem) -> Void

    /// Trailing debounce for background writes.
    static let writeDebounce: TimeInterval = 0.4

    private struct WriteState {
        /// Latest not-yet-written snapshot; newer replaces older.
        var snapshot: [CameraProfile]?
        var scheduled: DispatchWorkItem?
    }

    private let writeState = OSAllocatedUnfairLock(initialState: WriteState())
    /// Serialises every actual file write (background, `flush()`, `load()`).
    private let persistLock = NSLock()
    private var isDirectoryReady = false
    /// Number of write attempts so far; taken under `persistLock`, so it is
    /// the real order the attempts hit the disk in.
    private var writeSequence = 0
    /// Highest attempt whose outcome has reached `lastWriteError`. Main
    /// thread only. Anything older arriving later is stale and dropped.
    private var publishedSequence = 0
    private let dataWriter: DataWriter
    private let scheduler: Scheduler
    private var lifecycleObservers: [NSObjectProtocol] = []
    private let notificationCenter: NotificationCenter

    private let directory: URL
    private let calendar: Calendar
    private let now: () -> Date
    private let defaults: UserDefaults
    private let fileManager: FileManager

    /// Creates a store.
    ///
    /// - Parameter directory: where `profiles.json` lives. Defaults to
    ///   `Application Support/DaysCam`; tests pass a temporary directory.
    /// - Parameters:
    ///   - writeQueue: where debounced writes run; never the main queue.
    ///   - scheduler: overrides the debounce timer (tests).
    ///   - dataWriter: overrides the atomic file write (tests).
    ///   - notificationCenter: where the resign-active and background
    ///     notifications are observed to flush pending writes.
    init(directory: URL? = nil,
         calendar: Calendar = .autoupdatingCurrent,
         now: @escaping () -> Date = DayCountCalculator.defaultNow(),
         defaults: UserDefaults = .standard,
         fileManager: FileManager = .default,
         writeQueue: DispatchQueue = DispatchQueue(label: "com.irenechou.DaysCam.profile-writer",
                                                   qos: .utility),
         scheduler: Scheduler? = nil,
         dataWriter: @escaping DataWriter = { data, url in try data.write(to: url, options: [.atomic]) },
         notificationCenter: NotificationCenter = .default) {
        self.directory = directory ?? Self.defaultDirectory(fileManager: fileManager)
        self.calendar = calendar
        self.now = now
        self.defaults = defaults
        self.fileManager = fileManager
        self.dataWriter = dataWriter
        self.notificationCenter = notificationCenter
        self.scheduler = scheduler ?? { delay, work in
            writeQueue.asyncAfter(deadline: .now() + delay, execute: work)
        }
        let flushNames: [Notification.Name] = [UIApplication.willResignActiveNotification,
                                               UIApplication.didEnterBackgroundNotification]
        lifecycleObservers = flushNames.map { name in
            notificationCenter.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                self?.flush()
            }
        }
    }

    deinit {
        lifecycleObservers.forEach(notificationCenter.removeObserver)
        flush()
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
        // 1.x data: keep a copy of the untouched file before any repair or
        // migration rewrites it (PRD-2.0 M-4). If the copy fails nothing is
        // migrated this launch and the next one retries.
        let canMigrate = LegacyDataMigrator.needsMigration(defaults: defaults)
            && LegacyDataMigrator.backUpProfilesFile(in: directory,
                                                     profilesFileName: Self.fileName,
                                                     fileManager: fileManager)
        loadAndRepair()
        if canMigrate && !didSeedFreshInstall {
            migrateLegacyData()
        }
        return profiles
    }

    @discardableResult
    private func loadAndRepair() -> [CameraProfile] {
        didRecoverFromCorruption = false
        didSeedFreshInstall = false
        droppedUndecodableRecordCount = 0
        isPartialBackupPending = false

        guard fileManager.fileExists(atPath: fileURL.path) else {
            // A missing profiles.json is only a fresh install when no 1.x
            // trace remains; otherwise (corrupt file set aside, an earlier
            // write that failed) the seeded profile still has to receive the
            // old photos and album, and `load()` migrates it.
            let hasLegacyData = LegacyDataMigrator.hasLegacyData(
                in: directory, profilesFileName: Self.fileName,
                photosFileName: CapturedPhotoStore.fileName,
                defaults: defaults, fileManager: fileManager)
            didSeedFreshInstall = !hasLegacyData
            seedDefaultProfile()
            if !hasLegacyData {
                LegacyDataMigrator.markMigrated(defaults: defaults)
            }
            return profiles
        }

        // Decode record by record: one unreadable record (an unknown enum
        // value from a newer build, say) must not take the others with it.
        guard let data = try? Data(contentsOf: fileURL),
              let records = try? JSONDecoder().decode([LossyRecord].self, from: data),
              records.isEmpty || records.contains(where: { $0.profile != nil }) else {
            setAsideCorruptFile()
            didRecoverFromCorruption = true
            seedDefaultProfile()
            return profiles
        }
        let decoded = records.compactMap(\.profile)
        let droppedCount = records.count - decoded.count

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
        droppedUndecodableRecordCount = droppedCount
        // Persist the cleaned-up records so the repair happens once, not on
        // every launch.
        if droppedCount > 0 {
            // Rewriting drops the undecodable records for good, so `persist`
            // keeps the original first. If the copy fails the file is left
            // alone and every later write retries it.
            isPartialBackupPending = true
            try? persistSynchronously(repaired)
        } else if repaired != decoded {
            try? persistSynchronously(repaired)
        }
        return profiles
    }

    /// Attaches the 1.x photo IDs and album to the last-used profile, then
    /// records version 2. The new `profiles.json` is written first; if that
    /// fails the version stays 1, memory and disk keep the old data, and the
    /// next launch retries (PRD-2.0 M-1~M-3, §4.2).
    private func migrateLegacyData() {
        let migrated = LegacyDataMigrator.migrated(
            profiles,
            targetID: lastUsedProfileID,
            photosURL: directory.appendingPathComponent(CapturedPhotoStore.fileName),
            defaults: defaults)
        if migrated != profiles {
            do {
                try persistSynchronously(migrated)
            } catch {
                return
            }
            profiles = migrated
        }
        LegacyDataMigrator.markMigrated(defaults: defaults)
    }

    /// Writes the one profile a fresh install starts with (PRD §4.3).
    private func seedDefaultProfile() {
        let today = calendar.dateComponents([.year, .month, .day], from: now())
        let timestamp = now()
        let seeded = CameraProfile(name: Self.defaultProfileName,
                                   startDate: today,
                                   showName: true,
                                   createdAt: timestamp,
                                   updatedAt: timestamp)
        profiles = [seeded]
        try? persistSynchronously(profiles)
        select(id: seeded.id)
    }

    /// Copies the current file to `profiles.json.partial-<timestamp>` before it
    /// is rewritten without its undecodable records. Returns whether the copy
    /// exists.
    private func keepPartialBackup() -> Bool {
        // Milliseconds plus a random suffix: two loads in the same second must
        // not overwrite each other's backup.
        let stamp = Int(now().timeIntervalSince1970 * 1000)
        let suffix = UUID().uuidString.prefix(8)
        let destination = directory.appendingPathComponent("\(Self.fileName).partial-\(stamp)-\(suffix)")
        do {
            try fileManager.copyItem(at: fileURL, to: destination)
            return true
        } catch {
            return false
        }
    }

    /// One array element that decodes to `nil` instead of failing the array.
    private struct LossyRecord: Decodable {
        let profile: CameraProfile?

        init(from decoder: Decoder) throws {
            profile = try? decoder.singleValueContainer().decode(CameraProfile.self)
        }
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
        try commit(updated)
        // A new profile becomes the active one (PRD FR-1.10).
        select(id: candidate.id)
        return candidate
    }

    /// Like `update(_:)`, but returns only once the change is on disk, for an
    /// explicit user action that must not be reported as done while the save
    /// has failed (font apply, #492). Throws `writeFailed` on a disk failure;
    /// the change is then rolled back in memory too, since the caller tells
    /// the user it did not happen, and the failure is returned to the caller
    /// instead of being published to `lastWriteError`.
    @discardableResult
    func updateAndWait(_ profile: CameraProfile) throws -> CameraProfile {
        let previous = profiles
        let (stored, updated) = try applyUpdate(profile)
        try commit(updated, previous: previous)
        return stored
    }

    /// Validates and overwrites an existing profile, keeping its `createdAt`.
    @discardableResult
    func update(_ profile: CameraProfile) throws -> CameraProfile {
        let (candidate, updated) = try applyUpdate(profile)
        scheduleWrite(updated)
        return candidate
    }

    /// Validates `profile` and swaps it into memory; the caller decides how
    /// the file follows.
    private func applyUpdate(_ profile: CameraProfile) throws -> (CameraProfile, [CameraProfile]) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else {
            throw ProfileStoreError.profileNotFound(id: profile.id)
        }
        var candidate = try validated(profile)
        // `createdAt` belongs to the record, not to whoever is editing it.
        candidate.createdAt = profiles[index].createdAt
        candidate.updatedAt = now()

        var updated = profiles
        updated[index] = candidate
        profiles = updated
        return (candidate, updated)
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
        try commit(updated)
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
        try commit(updated)
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
                                       displayUnits: source.displayUnits,
                                       useAgeWording: source.useAgeWording,
                                       dayCountFormat: source.dayCountFormat,
                                       position: source.position,
                                       style: source.style,
                                       showFilmDate: source.showFilmDate,
                                       filmDateCorner: source.filmDateCorner,
                                       createdAt: timestamp,
                                       updatedAt: timestamp)

        var updated = profiles
        updated.insert(duplicated, at: index + 1)
        try commit(updated)
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

extension ProfileStore {
    /// Writes any change that is still waiting out its debounce, on the
    /// calling thread, and returns once it is on disk (or has failed into
    /// `lastWriteError`). Called when the app resigns active or backgrounds.
    func flush() {
        let pendingWork = writeState.withLock { state -> DispatchWorkItem? in
            defer { state.scheduled = nil }
            return state.scheduled
        }
        pendingWork?.cancel()
        writePending()
    }

    /// Makes `updated` the stored profiles and writes it to disk before
    /// returning: for every explicit user action (add, delete, duplicate,
    /// reorder, font apply), which must not be reported as done while the save
    /// has failed (#492, human decision 2026-10-12). Only continuous
    /// adjustments (sliders, drags) go through `scheduleWrite`.
    ///
    /// On a disk failure memory goes back to `previous` and `writeFailed` is
    /// thrown to the caller, which reports it; nothing is published to
    /// `lastWriteError`.
    fileprivate func commit(_ updated: [CameraProfile], previous: [CameraProfile]? = nil) throws {
        let before = previous ?? profiles
        profiles = updated
        let pendingWork = writeState.withLock { state -> DispatchWorkItem? in
            defer { state.scheduled = nil; state.snapshot = updated }
            return state.scheduled
        }
        pendingWork?.cancel()
        if let failure = writePending(publishFailure: false) {
            // Back to what the caller saw before; any earlier edit that was
            // still waiting for its debounce stays queued for the next write.
            profiles = before
            writeState.withLock { $0.snapshot = before }
            throw failure
        }
    }

    /// Queues `snapshot` as the next write. Memory is already up to date; the
    /// file follows after a trailing debounce so a slider drag costs one
    /// write, not one per step (#464).
    fileprivate func scheduleWrite(_ snapshot: [CameraProfile]) {
        let work = DispatchWorkItem { [weak self] in self?.writePending() }
        let previous = writeState.withLock { state -> DispatchWorkItem? in
            let old = state.scheduled
            state.snapshot = snapshot
            state.scheduled = work
            return old
        }
        previous?.cancel()
        scheduler(Self.writeDebounce, work)
    }

    /// Writes the queued snapshot, if any. A failed snapshot is put back
    /// unless something newer arrived, so the next write retries it.
    ///
    /// - Parameter publishFailure: whether a failure goes to
    ///   `lastWriteError`; a caller that reports the failure itself passes
    ///   `false`. Success always clears the error.
    /// - Returns: the failure, or nil when nothing was queued or it succeeded.
    @discardableResult
    private func writePending(publishFailure: Bool = true) -> ProfileStoreError? {
        persistLock.lock()
        defer { persistLock.unlock() }
        guard let snapshot = writeState.withLock({ state -> [CameraProfile]? in
            defer { state.snapshot = nil }
            return state.snapshot
        }) else { return nil }
        writeSequence += 1
        let sequence = writeSequence
        do {
            try persist(snapshot)
            publishWriteError(nil, sequence: sequence)
            return nil
        } catch {
            writeState.withLock { state in
                if state.snapshot == nil { state.snapshot = snapshot }
            }
            let failure = error as? ProfileStoreError ?? .writeFailed(String(describing: error))
            if publishFailure { publishWriteError(failure, sequence: sequence) }
            return failure
        }
    }

    /// Hands an attempt's outcome to `lastWriteError` on the main thread. An
    /// outcome older than one already published is dropped, whichever way
    /// it went: a late failure must not undo a newer success, nor a late
    /// success a newer failure.
    private func publishWriteError(_ error: ProfileStoreError?, sequence: Int) {
        let apply = { [weak self] in
            guard let self, sequence > self.publishedSequence else { return }
            self.publishedSequence = sequence
            self.lastWriteError = error
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    /// Writes the profiles atomically.
    ///
    /// `.atomic` writes to a temporary file and swaps it in, so a crash or a
    /// full disk leaves the previous file intact rather than truncated
    /// (PRD §4.3). The directory is created once and again only after a
    /// failed write. Callers on the load path hold no pending snapshot, so
    /// they take `persistLock` here; background writers already hold it.
    fileprivate func persistSynchronously(_ profiles: [CameraProfile]) throws {
        persistLock.lock()
        defer { persistLock.unlock() }
        try persist(profiles)
    }

    /// Caller must hold `persistLock`.
    private func persist(_ profiles: [CameraProfile]) throws {
        do {
            if !isDirectoryReady {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                isDirectoryReady = true
            }
            if isPartialBackupPending {
                guard keepPartialBackup() else {
                    throw ProfileStoreError.writeFailed("could not back up the original profiles file")
                }
                isPartialBackupPending = false
            }
            let encoder = JSONEncoder()
            #if DEBUG
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            #else
            encoder.outputFormatting = [.sortedKeys]
            #endif
            let data = try encoder.encode(profiles)
            try dataWriter(data, fileURL)
        } catch {
            isDirectoryReady = false
            throw ProfileStoreError.writeFailed(String(describing: error))
        }
    }
}
