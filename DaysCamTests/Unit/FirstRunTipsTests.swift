import XCTest
@testable import DaysCam

/// #647 acceptance 7–10 (#699 retired the viewer bubble): the first-run flags and the UI-test default.
final class FirstRunTipsTests: XCTestCase {
    private var suiteName = ""
    private var defaults = UserDefaults.standard

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "FirstRunTipsTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testNothingIsSeenAtFirst() {
        let tips = FirstRunTips(defaults: defaults)
        XCTAssertFalse(tips.overlayTapSeen)
    }

    /// #656-9: the camera's text-tap hint is its own flag and persists.
    func testOverlayTapHintIsSeparateAndPersists() {
        let tips = FirstRunTips(defaults: defaults)
        XCTAssertFalse(tips.overlayTapSeen)
        tips.markOverlayTapSeen()
        XCTAssertTrue(FirstRunTips(defaults: defaults).overlayTapSeen)
    }

    /// 10: UI tests count every tip as seen unless they ask for them.
    func testSeenByDefaultForUITests() {
        let tips = FirstRunTips(defaults: defaults, seenByDefault: true)
        XCTAssertTrue(tips.overlayTapSeen)
    }
}
