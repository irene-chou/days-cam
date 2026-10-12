import XCTest
@testable import DaysCam

/// The two long-lived objects that keep a calendar in a stored property must
/// follow the device's time zone when it changes, not the one they were built
/// in (PRD §6.3).
///
/// `Calendar.current` is a snapshot: stored at init it freezes the time zone
/// of that moment, so an app launched in Taipei and reopened in New York keeps
/// counting days from Taipei's midnight. `.autoupdatingCurrent` does not.
///
/// These are the only tests that deliberately rely on the default calendar —
/// every other test injects one — so they change the process time zone and
/// put it back afterwards.
final class AutoupdatingCalendarTests: XCTestCase {

    private var savedTimeZone = NSTimeZone.default
    private var directory = URL(fileURLWithPath: NSTemporaryDirectory())
    private var suiteName = ""

    /// 2026-01-10 11:00 in Taipei, 2026-01-09 22:00 in New York.
    private let instant = Date(timeIntervalSince1970: 1_768_014_000)

    override func setUpWithError() throws {
        try super.setUpWithError()
        savedTimeZone = NSTimeZone.default
        NSTimeZone.default = try XCTUnwrap(TimeZone(identifier: "Asia/Taipei"))
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("AutoupdatingCalendarTests-\(UUID().uuidString)", isDirectory: true)
        suiteName = "AutoupdatingCalendarTests-\(UUID().uuidString)"
    }

    override func tearDownWithError() throws {
        NSTimeZone.default = savedTimeZone
        try? FileManager.default.removeItem(at: directory)
        UserDefaults().removePersistentDomain(forName: suiteName)
        try super.tearDownWithError()
    }

    private func flyToNewYork() throws {
        NSTimeZone.default = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
    }

    func testFixtureInstantFallsOnDifferentDaysInTheTwoZones() throws {
        var taipei = Calendar(identifier: .gregorian)
        taipei.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Taipei"))
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))

        XCTAssertEqual(taipei.component(.day, from: instant), 10)
        XCTAssertEqual(newYork.component(.day, from: instant), 9)
    }

    func testDayCountCalculatorFollowsATimeZoneChangeAfterItWasBuilt() throws {
        let calculator = DayCountCalculator(now: { self.instant })
        let start = DateFixture.components(2026, 1, 9)
        XCTAssertEqual(calculator.rawDayDifference(from: start), 1, "built and read in Taipei: the 10th")

        try flyToNewYork()

        XCTAssertEqual(calculator.rawDayDifference(from: start), 0,
                       "same calculator, now in New York: still the 9th there")
    }

    func testProfileStoreSeedsTodayInTheZoneTheDeviceIsInNow() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let store = ProfileStore(directory: directory, now: { self.instant }, defaults: defaults, scheduler: ProfileStore.immediateScheduler)

        try flyToNewYork()
        let seeded = store.load()

        XCTAssertEqual(seeded.first?.startDate, DateFixture.components(2026, 1, 9),
                       "built in Taipei, first launched in New York: today is the 9th")
    }
}
