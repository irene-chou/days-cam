import XCTest
@testable import DaysCam

/// Pins the unit tracks of PRD §3.2: weeks never mix with years or months, and
/// exactly eight `(largest, smallest)` pairs are legal.
final class DisplayUnitTrackTests: XCTestCase {

    func testEachTrackListsItsUnitsLargestFirst() {
        XCTAssertEqual(DisplayUnitTrack.units(forLargest: .year), [.year, .month, .day])
        XCTAssertEqual(DisplayUnitTrack.units(forLargest: .month), [.month, .day])
        XCTAssertEqual(DisplayUnitTrack.units(forLargest: .week), [.week, .day])
        XCTAssertEqual(DisplayUnitTrack.units(forLargest: .day), [.day])
    }

    func testWeekNeverAppearsOnTheYearOrMonthTrack() {
        XCTAssertFalse(DisplayUnitTrack.units(forLargest: .year).contains(.week))
        XCTAssertFalse(DisplayUnitTrack.units(forLargest: .month).contains(.week))
        XCTAssertFalse(DisplayUnitTrack.units(forLargest: .week).contains(.year))
        XCTAssertFalse(DisplayUnitTrack.units(forLargest: .week).contains(.month))
    }

    func testExactlyEightLegalPairsInTrackOrder() {
        let expected = [
            DisplayUnitPair(largest: .year, smallest: .year),
            DisplayUnitPair(largest: .year, smallest: .month),
            DisplayUnitPair(largest: .year, smallest: .day),
            DisplayUnitPair(largest: .month, smallest: .month),
            DisplayUnitPair(largest: .month, smallest: .day),
            DisplayUnitPair(largest: .week, smallest: .week),
            DisplayUnitPair(largest: .week, smallest: .day),
            DisplayUnitPair(largest: .day, smallest: .day)
        ]
        XCTAssertEqual(DisplayUnitTrack.legalPairs.count, 8)
        XCTAssertEqual(DisplayUnitTrack.legalPairs, expected)
    }

    func testIsLegalPairAgreesWithTheLegalPairList() {
        for largest in DisplayUnit.allCases {
            for smallest in DisplayUnit.allCases {
                let pair = DisplayUnitPair(largest: largest, smallest: smallest)
                XCTAssertEqual(DisplayUnitTrack.isLegalPair(largest: largest, smallest: smallest),
                               DisplayUnitTrack.legalPairs.contains(pair),
                               "\(largest) / \(smallest)")
            }
        }
    }

    func testAllowedSmallestUnitsIsWhatThePickerOffers() {
        XCTAssertEqual(DisplayUnitTrack.allowedSmallestUnits(forLargest: .year), [.year, .month, .day])
        XCTAssertEqual(DisplayUnitTrack.allowedSmallestUnits(forLargest: .day), [.day])
    }

    func testUnitsForAPairAreTheSliceFromLargestDownToSmallest() {
        XCTAssertEqual(DisplayUnitTrack.units(largest: .year, smallest: .day), [.year, .month, .day])
        XCTAssertEqual(DisplayUnitTrack.units(largest: .year, smallest: .month), [.year, .month])
        XCTAssertEqual(DisplayUnitTrack.units(largest: .year, smallest: .year), [.year])
        XCTAssertEqual(DisplayUnitTrack.units(largest: .month, smallest: .day), [.month, .day])
        XCTAssertEqual(DisplayUnitTrack.units(largest: .week, smallest: .day), [.week, .day])
        XCTAssertEqual(DisplayUnitTrack.units(largest: .day, smallest: .day), [.day])
    }

    func testUnitsForAnIllegalPairIsEmpty() {
        XCTAssertEqual(DisplayUnitTrack.units(largest: .week, smallest: .month), [])
        XCTAssertEqual(DisplayUnitTrack.units(largest: .day, smallest: .year), [])
    }
}
