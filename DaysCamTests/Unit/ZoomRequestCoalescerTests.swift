import XCTest
@testable import DaysCam

/// Covers `ZoomRequestCoalescer` (issue #280, 63.4): a burst of zoom requests
/// becomes one queued job that applies only the newest factor.
final class ZoomRequestCoalescerTests: XCTestCase {
    private var jobs: [() -> Void] = []
    private var applied: [CGFloat] = []

    private func submit(_ coalescer: ZoomRequestCoalescer, _ factor: CGFloat) {
        coalescer.submit(factor,
                         schedule: { [unowned self] in jobs.append($0) },
                         apply: { [unowned self] in applied.append($0) })
    }

    func testBurstSchedulesOneJobAndAppliesOnlyTheLastFactor() {
        let coalescer = ZoomRequestCoalescer()
        for factor in [1.1, 1.2, 1.3, 1.4, 1.5] as [CGFloat] { submit(coalescer, factor) }
        XCTAssertEqual(jobs.count, 1, "佇列上最多一個工作")
        jobs[0]()
        XCTAssertEqual(applied, [1.5], "中間值被丟棄")
    }

    func testRequestMadeWhileTheJobIsRunningGetsANewJob() {
        let coalescer = ZoomRequestCoalescer()
        submit(coalescer, 2)
        jobs[0]()
        submit(coalescer, 3)
        XCTAssertEqual(jobs.count, 2)
        jobs[1]()
        XCTAssertEqual(applied, [2, 3])
    }

    func testRequestBetweenScheduleAndRunIsFoldedIntoTheSameJob() {
        let coalescer = ZoomRequestCoalescer()
        submit(coalescer, 2)
        submit(coalescer, 4)
        jobs[0]()
        submit(coalescer, 5)
        jobs[1]()
        XCTAssertEqual(applied, [4, 5])
    }

    func testRunningWithNothingPendingAppliesNothing() {
        let coalescer = ZoomRequestCoalescer()
        submit(coalescer, 2)
        jobs[0]()
        applied.removeAll()
        jobs[0]() // a stale second run
        XCTAssertTrue(applied.isEmpty)
    }
}
