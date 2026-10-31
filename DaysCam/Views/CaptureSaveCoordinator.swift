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

    init() {}

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
    /// earlier write has answered, and the next starts when it returns or
    /// throws. Read the record's album inside `body`, not before.
    func serialized<T>(_ body: () async throws -> T) async rethrows -> T {
        let finished = await withCheckedContinuation { (continuation: CheckedContinuation<() -> Void, Never>) in
            enqueueSave { finished in continuation.resume(returning: finished) }
        }
        defer { finished() }
        return try await body()
    }

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
