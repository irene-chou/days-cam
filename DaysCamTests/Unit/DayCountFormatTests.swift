import XCTest
@testable import DaysCam

/// #582 acceptance 1 and 2: the four day-only wordings on their own.
final class DayCountFormatTests: XCTestCase {

    func test_582_1_casesRawValuesAndDefault() {
        XCTAssertEqual(DayCountFormat.allCases, [.ordinal, .plain, .dayN, .dDay])
        XCTAssertEqual(DayCountFormat.allCases.map(\.rawValue), ["ordinal", "plain", "dayN", "dDay"])
        XCTAssertEqual(DayCountFormat.default, .ordinal)
    }

    func test_582_1_unknownStringDecodesToTheDefault() throws {
        let decoded = try JSONDecoder().decode([DayCountFormat].self, from: Data(#"["banana","dDay",""]"#.utf8))
        XCTAssertEqual(decoded, [.ordinal, .dDay, .ordinal])
    }

    func test_582_1_roundTripKeepsEveryCase() throws {
        let data = try JSONEncoder().encode(DayCountFormat.allCases)
        XCTAssertEqual(try JSONDecoder().decode([DayCountFormat].self, from: data), DayCountFormat.allCases)
    }

    func test_582_2_elapsedText() {
        // (format, [0, 1, 12, 365])
        let table: [(DayCountFormat, [String])] = [
            (.ordinal, ["第 0 天", "第 1 天", "第 12 天", "第 365 天"]),
            (.plain, ["0 天", "1 天", "12 天", "365 天"]),
            (.dayN, ["Day 0", "Day 1", "Day 12", "Day 365"]),
            (.dDay, ["D-Day", "D+1", "D+12", "D+365"])
        ]
        for (format, expected) in table {
            XCTAssertEqual([0, 1, 12, 365].map(format.elapsedText(count:)), expected, "\(format)")
        }
    }

    func test_582_2_countdownText() {
        // (format, [1, 7, 100])
        let table: [(DayCountFormat, [String])] = [
            (.ordinal, ["還有 1 天", "還有 7 天", "還有 100 天"]),
            (.plain, ["還有 1 天", "還有 7 天", "還有 100 天"]),
            (.dayN, ["1 days to go", "7 days to go", "100 days to go"]),
            (.dDay, ["D-1", "D-7", "D-100"])
        ]
        for (format, expected) in table {
            XCTAssertEqual([1, 7, 100].map(format.countdownText(daysUntilStart:)), expected, "\(format)")
        }
        XCTAssertEqual(DayCountFormat.ordinal.countdownText(daysUntilStart: 7),
                       TemplateRenderer.notStartedText(daysUntilStart: 7))
    }

    func test_582_5_onlyDDayIgnoresTheCountingRule() {
        XCTAssertEqual(DayCountFormat.allCases.filter { !$0.usesCountingRule }, [.dDay])
    }
}
