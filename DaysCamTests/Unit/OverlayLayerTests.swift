import XCTest
@testable import DaysCam

/// #718: the 疊字 layer's switch (`showOverlay`) — its data, how it reaches
/// the text that is drawn and baked, and the layer list's summaries.
@MainActor
final class OverlayLayerTests: XCTestCase {
    private func sampleProfile() -> CameraProfile {
        CameraProfile(id: UUID(uuidString: "11111111-2222-3333-4444-555555555555") ?? UUID(),
                      name: "小寶",
                      startDate: DateFixture.components(2024, 3, 9),
                      countingRule: .dayZero,
                      showDayCount: true,
                      showDate: true,
                      showName: true,
                      displayUnits: [.year, .month],
                      useAgeWording: true,
                      position: .custom(x: 0.3, y: 0.7),
                      style: OverlayStyle(legacyTheme: .softPink),
                      showFilmDate: true,
                      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                      updatedAt: Date(timeIntervalSince1970: 1_700_000_500))
    }

    private func jsonObject(_ profile: CameraProfile) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as? [String: Any])
    }

    private func decode(_ object: [String: Any]) throws -> CameraProfile {
        try JSONDecoder().decode(CameraProfile.self, from: JSONSerialization.data(withJSONObject: object))
    }

    // MARK: - 718-1: new records

    /// 718-1: a fresh install's record starts with both layers off.
    func test_718_1_seededRecordHasBothLayersOff() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "OverlayLayerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }
        let store = ProfileStore(directory: directory, calendar: DateFixture.taipei, now: { Date() },
                                 defaults: defaults, scheduler: ProfileStore.immediateScheduler)
        store.load()
        let seeded = try XCTUnwrap(store.profiles.first)
        XCTAssertFalse(seeded.showOverlay)
        XCTAssertFalse(seeded.showFilmDate)
    }

    /// The memberwise default stays on, so existing call sites keep their text.
    func test_718_1_initializerDefaultIsOn() {
        XCTAssertTrue(CameraProfile(name: "新", startDate: DateFixture.components(2025, 1, 1)).showOverlay)
    }

    // MARK: - 718-2: decoding

    /// 718-2: a record written before the field decodes with the layer on and
    /// everything else unchanged; written back it reads the same.
    func test_718_2_recordWithoutTheFieldDecodesOnAndRoundTrips() throws {
        let original = sampleProfile()
        var json = try jsonObject(original)
        XCTAssertNotNil(json.removeValue(forKey: "showOverlay"))

        let decoded = try decode(json)

        XCTAssertTrue(decoded.showOverlay)
        XCTAssertEqual(decoded, original)
        let reread = try JSONDecoder().decode(CameraProfile.self, from: JSONEncoder().encode(decoded))
        XCTAssertEqual(reread, decoded)
    }

    func test_718_2_offSurvivesARoundTripAndAnUnreadableValueFallsBackOn() throws {
        var profile = sampleProfile()
        profile.showOverlay = false
        let reread = try JSONDecoder().decode(CameraProfile.self, from: JSONEncoder().encode(profile))
        XCTAssertFalse(reread.showOverlay)
        XCTAssertEqual(reread, profile)

        var json = try jsonObject(profile)
        json["showOverlay"] = "no"
        let fallback = try decode(json)
        XCTAssertTrue(fallback.showOverlay)
        XCTAssertEqual(fallback.name, profile.name)
    }

    func test_718_2_duplicateKeepsTheSwitch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "OverlayLayerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }
        let store = ProfileStore(directory: directory, calendar: DateFixture.taipei, now: { Date() },
                                 defaults: defaults, scheduler: ProfileStore.immediateScheduler)
        var profile = sampleProfile()
        profile.showOverlay = false
        let added = try store.add(profile)
        XCTAssertFalse(try store.duplicate(id: added.id).showOverlay)
    }

    // MARK: - 718-3: what is drawn and baked

    /// 718-3: off draws and bakes no text; the sub-settings are kept, and on
    /// again the text is what it was.
    func test_718_3_offGivesNoTextAndOnRestoresIt() throws {
        let renderer = TemplateRenderer()
        let date = try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 8))
        var profile = sampleProfile()
        let before = renderer.overlayText(profile: profile, capturedAt: date, calendar: DateFixture.taipei, moment: .photo)
        XCTAssertFalse(before.isEmpty)

        profile.showOverlay = false
        XCTAssertEqual(renderer.overlayText(profile: profile, capturedAt: date, calendar: DateFixture.taipei, moment: .photo), "")
        XCTAssertEqual(profile.displayUnits, sampleProfile().displayUnits)
        XCTAssertTrue(profile.showDayCount && profile.showDate && profile.showName)
        XCTAssertEqual(profile.style, sampleProfile().style)
        XCTAssertEqual(profile.position, sampleProfile().position)
        XCTAssertEqual(renderer.render(profile: profile, capturedAt: date, calendar: DateFixture.taipei, moment: .photo), before,
                       "the panel's own preview still shows what the switches print")

        profile.showOverlay = true
        XCTAssertEqual(renderer.overlayText(profile: profile, capturedAt: date, calendar: DateFixture.taipei, moment: .photo), before)
    }

    /// The film date is its own layer: it stays with the text layer off.
    func test_718_3_filmDateFollowsItsOwnSwitch() throws {
        var profile = sampleProfile()
        profile.showOverlay = false
        let date = try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 8))
        XCTAssertNotNil(PhotoDetailModel.filmDateStamp(for: profile, creationDate: date, calendar: DateFixture.taipei))
        profile.showFilmDate = false
        XCTAssertNil(PhotoDetailModel.filmDateStamp(for: profile, creationDate: date, calendar: DateFixture.taipei))
    }

    /// The switch writes through `DisplaySettingsModel` and touches nothing else.
    func test_718_3_settingTheSwitchWritesOnlyThatField() {
        var written: [CameraProfile] = []
        let model = DisplaySettingsModel(profile: sampleProfile()) { written.append($0) }
        model.setShowOverlay(false)
        model.setShowOverlay(false)
        XCTAssertEqual(written.count, 1, "no write when nothing changes")
        var expected = sampleProfile()
        expected.showOverlay = false
        XCTAssertEqual(written.first, expected)
        model.setShowOverlay(true)
        XCTAssertEqual(written.last, sampleProfile())
    }

    // MARK: - 718-4: summaries and routes

    func test_718_4_overlaySummaryListsStyleContentsAndPosition() {
        XCTAssertEqual(LayerSummary.overlay(styleName: "經典", showDayCount: true, showDate: true, showName: false,
                                            positionName: "右下"), "經典 · 天數、日期 · 右下")
        XCTAssertEqual(LayerSummary.overlay(styleName: "海報", showDayCount: true, showDate: true, showName: true,
                                            positionName: "中上"), "海報 · 天數、日期、名稱 · 中上")
        XCTAssertEqual(LayerSummary.overlay(styleName: nil, showDayCount: false, showDate: false, showName: false,
                                            positionName: "自訂位置"), "自訂 · 無內容 · 自訂位置")
    }

    func test_718_4_filmDateSummaryNamesTheCorner() {
        XCTAssertEqual(LayerSummary.filmDate(corner: .bottomLeading), "左下角")
        XCTAssertEqual(LayerSummary.filmDate(corner: .topTrailing), "右上角")
    }

    /// 718-5, 7: the panel opens on the layer list, or on the layer the caller
    /// means, and a pushed page goes back to the list.
    func test_718_5_routes() {
        let model = OverlayPanelModel()
        XCTAssertEqual(model.route, .root)
        model.open(at: .overlay)
        XCTAssertEqual(model.route, .overlay)
        model.goBack()
        XCTAssertEqual(model.route, .root)
        model.route = .filmDate
        model.close()
        model.open()
        XCTAssertEqual(model.route, .root, "opening again starts on the list")
        XCTAssertEqual(OverlayPanelModel.Route.allTitles, ["文字樣式", "疊字", "底片日期"])
    }
}

extension OverlayPanelModel.Route {
    static var allTitles: [String] { [Self.root, .overlay, .filmDate].map(\.title) }
}
