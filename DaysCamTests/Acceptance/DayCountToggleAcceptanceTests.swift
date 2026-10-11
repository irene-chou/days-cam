import UIKit
import XCTest
@testable import DaysCam

/// QA acceptance for TASK-107 (#426), 107.2 and 107.8: a date-only profile
/// bakes a photo whose text is the date alone, and with the day count off the
/// order is 日期 名稱. The text goes through the same `TemplateRenderer` and
/// `OverlayRenderer.bake` pair the shutter uses; pixels are compared against a
/// bake of the literal expected string, so the text content is pinned by
/// pixels and not just by the renderer's own output.
final class DayCountToggleAcceptanceTests: XCTestCase {

    private let renderer = TemplateRenderer()
    private let capturedAt = DateFixture.date(2026, 10, 11, hour: 10)

    private func profile(showDayCount: Bool, showDate: Bool, showName: Bool) -> CameraProfile {
        CameraProfile(name: "寶寶",
                      startDate: DateFixture.components(2026, 9, 1),
                      showDayCount: showDayCount,
                      showDate: showDate,
                      showName: showName)
    }

    private func text(_ subject: CameraProfile) throws -> String {
        renderer.render(profile: subject, capturedAt: try XCTUnwrap(capturedAt), calendar: DateFixture.taipei)
    }

    private func bake(_ text: String) throws -> PixelGrid {
        let size = CGSize(width: 1200, height: 1600)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let blank = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        let baked = try XCTUnwrap(OverlayRenderer().bake(image: blank, text: text, style: OverlayStyle(),
                                                         placement: .anchor(.bottomTrailing), font: .pingFang))
        return try XCTUnwrap(PixelGrid(baked))
    }

    /// 107.2: text is exactly the date; with the name on it is "日期 名稱".
    func testDateOnlyAndDateNameTextOrder() throws {
        XCTAssertEqual(try text(profile(showDayCount: false, showDate: true, showName: false)), "2026.10.11")
        XCTAssertEqual(try text(profile(showDayCount: false, showDate: true, showName: true)), "2026.10.11 寶寶")
        XCTAssertEqual(try text(profile(showDayCount: true, showDate: true, showName: true)), "2026.10.11 寶寶 第 41 天")
    }

    /// 107.2 (photo): the baked pixels of a date-only profile equal a bake of
    /// the bare date, differ from a bake that also prints the day count, and
    /// are not blank.
    func testDateOnlyPhotoPixelsCarryOnlyTheDate() throws {
        let dateOnly = try bake(try text(profile(showDayCount: false, showDate: true, showName: false)))
        XCTAssertEqual(dateOnly.bytes, try bake("2026.10.11").bytes, "photo text is exactly the date")
        XCTAssertNotEqual(dateOnly.bytes, try bake("2026.10.11 第 41 天").bytes, "no day count baked in")
        XCTAssertNotEqual(dateOnly.bytes, try bake("").bytes, "something is drawn")
    }

    /// 107.2 (photo): date + name bakes "日期 名稱", not "名稱 日期".
    func testDateAndNamePhotoPixelsFollowDateThenName() throws {
        let both = try bake(try text(profile(showDayCount: false, showDate: true, showName: true)))
        XCTAssertEqual(both.bytes, try bake("2026.10.11 寶寶").bytes)
        XCTAssertNotEqual(both.bytes, try bake("寶寶 2026.10.11").bytes)
    }
}
