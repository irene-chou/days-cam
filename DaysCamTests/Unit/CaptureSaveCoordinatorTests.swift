import XCTest
@testable import DaysCam

/// The app-wide camera save queue and count (#636 review).
@MainActor
final class CaptureSaveCoordinatorTests: XCTestCase {
    func testCountsAndLimit() {
        let coordinator = CaptureSaveCoordinator()
        XCTAssertFalse(coordinator.isAtLimit)
        coordinator.photoDidArrive()
        coordinator.photoDidArrive()
        XCTAssertEqual(coordinator.inFlightCount, 2)
        XCTAssertTrue(coordinator.isAtLimit)
        coordinator.photoDidFinish()
        XCTAssertFalse(coordinator.isAtLimit)
        coordinator.photoDidFinish()
        coordinator.photoDidFinish()
        XCTAssertEqual(coordinator.inFlightCount, 0, "never below zero")
    }

    func testSavesRunOneAtATimeInOrder() {
        let coordinator = CaptureSaveCoordinator()
        var started: [Int] = []
        var finishers: [() -> Void] = []
        for index in 0..<3 {
            coordinator.enqueueSave { finished in
                started.append(index)
                finishers.append(finished)
            }
        }
        XCTAssertEqual(started, [0])
        finishers[0]()
        XCTAssertEqual(started, [0, 1])
        finishers[1]()
        XCTAssertEqual(started, [0, 1, 2])
    }

    /// #651: `serialized` work waits for the save before it, and the save
    /// after it waits for it, even when it throws.
    func testSerializedJoinsTheSameQueue() async {
        let coordinator = CaptureSaveCoordinator()
        var log: [String] = []
        var finishFirst: (() -> Void)?
        coordinator.enqueueSave { finished in
            log.append("save 1")
            finishFirst = finished
        }
        let work = Task {
            try await coordinator.serialized {
                log.append("work")
                throw RecordAlbumError.failed("boom")
            }
        }
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(log, ["save 1"], "waits for the save before it")
        coordinator.enqueueSave { finished in
            log.append("save 2")
            finished()
        }
        finishFirst?()
        _ = await work.result
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(log, ["save 1", "work", "save 2"])
    }

    /// #663-2: work that never answers times out with a failure, and the
    /// save behind it starts.
    func testSerializedTimesOutAndFreesTheQueue() async {
        let coordinator = CaptureSaveCoordinator(workTimeout: 0.1)
        var started = false
        let hung = Task {
            try await coordinator.serialized { () -> Int in
                try await withCheckedThrowingContinuation { (_: CheckedContinuation<Int, Error>) in }
            }
        }
        for _ in 0..<5 { await Task.yield() }
        coordinator.enqueueSave { finished in
            started = true
            finished()
        }
        XCTAssertFalse(started)
        let result = await hung.result
        XCTAssertThrowsError(try result.get()) { XCTAssertEqual($0 as? RecordAlbumError, .timedOut) }
        XCTAssertTrue(started)
    }

    func testSerializedReturnsAnswerBeforeTheTimeout() async throws {
        let coordinator = CaptureSaveCoordinator(workTimeout: 5)
        let value = try await coordinator.serialized { 7 }
        XCTAssertEqual(value, 7)
    }

    func testPendingAlbumIsPerRecordAndClearable() {
        let coordinator = CaptureSaveCoordinator()
        let id = UUID()
        coordinator.setPendingAlbum("a", for: id)
        XCTAssertEqual(coordinator.pendingAlbum(for: id), "a")
        XCTAssertNil(coordinator.pendingAlbum(for: UUID()))
        coordinator.setPendingAlbum(nil, for: id)
        XCTAssertNil(coordinator.pendingAlbum(for: id))
    }
}
