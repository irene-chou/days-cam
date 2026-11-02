import Combine
import Foundation

/// The camera saves of the whole app (#621, #636 review): how many photos
/// are being prepared or saved, and the one-at-a-time queue of every write
/// that may create a record's album (camera saves, "加入照片", and the album
/// creation of #651).
///
/// Built once by `DaysCamApp` and shared by every `CameraScreenModel`. A
/// camera is a new model each time it opens, so if each kept its own count,
/// closing and reopening the camera would let a new one start while the old
/// one's photos are still in memory, past the limit of 0.2 FR-5.5; and two
/// cameras saving at once for a record without an album would each create
/// one. Shared, the limit holds across cameras and a save always starts
/// after the previous one has answered, reading the album it may have just
/// created. Album creation and "加入照片" join the same queue (#651), so a
/// photo taken or added while a record's album is still being created goes
/// into that album instead of making a second one.
@MainActor
final class CaptureSaveCoordinator: ObservableObject {
    /// The most photos prepared or saved at once, across every camera; at
    /// the limit the shutter stays disabled so full-resolution images cannot
    /// pile up in memory.
    static let maxInFlightSaves = 2

    /// Photos taken and not yet answered for: goes up when a photo arrives
    /// from the camera and down when it fails, its save calls back, or its
    /// save times out.
    @Published private(set) var inFlightCount = 0

    /// Saves waiting for the one before them to answer.
    private var waitingSaves: [() -> Void] = []
    private var isSaveRunning = false

    /// Seconds a `serialized` body may run before the queue gives up on it.
    private let workTimeout: TimeInterval

    init(workTimeout: TimeInterval = 30) {
        self.workTimeout = workTimeout
    }

    /// Whether the limit is reached.
    var isAtLimit: Bool {
        inFlightCount >= Self.maxInFlightSaves
    }

    /// Counts one more photo in flight.
    func photoDidArrive() {
        inFlightCount += 1
    }

    /// One photo is done with: failed, saved or timed out.
    func photoDidFinish() {
        inFlightCount = max(0, inFlightCount - 1)
    }

    /// Runs `start` once every earlier save, from any camera, has answered
    /// (or timed out). `start` calls the closure it is handed exactly once
    /// when its save is over, which starts the next.
    func enqueueSave(_ start: @escaping (_ finished: @escaping () -> Void) -> Void) {
        waitingSaves.append { [self] in start { self.saveDidFinish() } }
        startNextSaveIfIdle()
    }

    /// Runs `body` in the same queue as `enqueueSave`: it starts once every
    /// earlier write has answered, and the next starts when it returns,
    /// throws or times out. Read the record's album inside `body`, not
    /// before.
    ///
    /// If `body` has not answered after `workTimeout`, the queue moves on
    /// and this throws `RecordAlbumError.timedOut`, so a PhotoKit call that
    /// never calls back cannot hold every later save (#663). A late answer
    /// is dropped.
    func serialized<T>(_ body: @escaping () async throws -> T) async throws -> T {
        let finished = await withCheckedContinuation { (continuation: CheckedContinuation<() -> Void, Never>) in
            enqueueSave { finished in continuation.resume(returning: finished) }
        }
        defer { finished() }
        let race = WorkRace<T>()
        return try await withCheckedThrowingContinuation { continuation in
            race.continuation = continuation
            let work = Task { @MainActor in
                do { race.settle(.success(try await body())) } catch { race.settle(.failure(error)) }
            }
            let timer = Task { @MainActor [workTimeout] in
                try? await Task.sleep(nanoseconds: UInt64(workTimeout * 1_000_000_000))
                guard !Task.isCancelled else { return }
                if race.settle(.failure(RecordAlbumError.timedOut)) { work.cancel() }
            }
            race.timer = timer
        }
    }

    /// Album ids created or used by a write whose write-back to the profile
    /// failed, by record. The next write for the record reuses the album
    /// instead of making a second one (#663).
    private var pendingAlbums: [UUID: String] = [:]

    /// Records whose album creation is still running inside a `serialized`
    /// body, even after that body timed out: PhotoKit may yet make the album,
    /// so no later write for the record may make another (#663).
    private var creatingAlbums: Set<UUID> = []

    /// Whether an album creation for `profileID` has started and not returned.
    func isCreatingAlbum(for profileID: UUID) -> Bool { creatingAlbums.contains(profileID) }

    /// Marks the start of a creation call for `profileID`; pair with
    /// `endAlbumCreation` in a `defer` so a late return clears it.
    func beginAlbumCreation(for profileID: UUID) { creatingAlbums.insert(profileID) }

    /// Marks the creation call for `profileID` as returned.
    func endAlbumCreation(for profileID: UUID) { creatingAlbums.remove(profileID) }

    /// Photos saved to the library while a record's album creation was
    /// pending: they join the album once it exists. In memory only; after a
    /// restart they stay in the library and in `fallbackAssetIDs`.
    private var awaitingAlbum: [UUID: [String]] = [:]

    /// Queues `assetID` to be added to `profileID`'s album once it exists.
    func addAwaitingAsset(_ assetID: String, for profileID: UUID) {
        guard !(awaitingAlbum[profileID] ?? []).contains(assetID) else { return }
        awaitingAlbum[profileID, default: []].append(assetID)
    }

    /// Removes and returns the photos waiting for `profileID`'s album.
    func takeAwaitingAssets(for profileID: UUID) -> [String] {
        awaitingAlbum.removeValue(forKey: profileID) ?? []
    }

    /// Puts back photos whose add to the album failed, ahead of newer ones.
    func restoreAwaitingAssets(_ ids: [String], for profileID: UUID) {
        guard !ids.isEmpty else { return }
        awaitingAlbum[profileID] = ids + (awaitingAlbum[profileID] ?? []).filter { !ids.contains($0) }
    }

    /// The album created for `profileID` but not stored on it yet.
    func pendingAlbum(for profileID: UUID) -> String? { pendingAlbums[profileID] }

    /// Remembers `albumID` for `profileID` until it is stored (`nil` forgets).
    func setPendingAlbum(_ albumID: String?, for profileID: UUID) { pendingAlbums[profileID] = albumID }

    private func startNextSaveIfIdle() {
        guard !isSaveRunning, !waitingSaves.isEmpty else { return }
        isSaveRunning = true
        waitingSaves.removeFirst()()
    }

    private func saveDidFinish() {
        isSaveRunning = false
        startNextSaveIfIdle()
    }
}

/// Settles a `serialized` call once, by whichever of the work and the timer
/// answers first. Main-actor only.
@MainActor
private final class WorkRace<T> {
    var continuation: CheckedContinuation<T, Error>?
    var timer: Task<Void, Never>?

    /// Resumes the caller; `false` when it already was.
    @discardableResult
    func settle(_ result: Result<T, Error>) -> Bool {
        guard let continuation else { return false }
        self.continuation = nil
        timer?.cancel()
        continuation.resume(with: result)
        return true
    }
}
