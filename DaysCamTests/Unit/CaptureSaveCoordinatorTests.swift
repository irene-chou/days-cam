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
}
