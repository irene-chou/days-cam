import XCTest
@testable import DaysCam

/// TASK-86 independent QA (86.1 to 86.4, read from #353's 82.x): the shadow
/// type and the shadow color do not touch each other. Uses colors the PR's own
/// tests do not: text-following at alpha 0.25 and a custom green.
final class ShadowDecoupleAcceptanceTests: XCTestCase {
    private let greenQuarter = OverlayColor(red8: 0x00, green8: 0xC8, blue8: 0x50, opacity: 64.0 / 255)
    private let geometry: [OverlayShadowPreset: (Double, Double, Double)] = [
        .soft: (0, 2, 4), .hard: (2, 2, 0), .glow: (0, 0, 8)
    ]

    private func assertGeometry(_ style: OverlayStyle, _ preset: OverlayShadowPreset,
                                file: StaticString = #filePath, line: UInt = #line) throws {
        let expected = try XCTUnwrap(geometry[preset], file: file, line: line)
        XCTAssertTrue(style.showsShadow, file: file, line: line)
        XCTAssertEqual(style.shadowOffsetX, expected.0, file: file, line: line)
        XCTAssertEqual(style.shadowOffsetY, expected.1, file: file, line: line)
        XCTAssertEqual(style.shadowBlur, expected.2, file: file, line: line)
        XCTAssertEqual(style.shadowPreset, preset, file: file, line: line)
    }

    /// 86.1 with a custom green at alpha 0.25.
    func test861CustomGreenSurvivesEveryTypeSwitch() throws {
        var style = OverlayStyle()
        style.shadowColorSource = .custom
        style.shadowColor = greenQuarter
        for preset in [OverlayShadowPreset.hard, .glow, .soft, .glow, .hard, .soft] {
            style.applyShadowPreset(preset)
            XCTAssertEqual(style.shadowColorSource, .custom)
            XCTAssertEqual(style.shadowColor, greenQuarter, "86.1 color and alpha untouched by \(preset)")
            XCTAssertEqual(style.resolvedShadowColor, greenQuarter)
            try assertGeometry(style, preset)
        }
    }

    /// 86.1 with the follow-text source at alpha 0.25, including a custom
    /// RGB stored behind it.
    func test861FollowTextSurvivesEveryTypeSwitch() throws {
        var style = OverlayStyle(textColor: OverlayColor(red8: 0xFF, green8: 0x6B, blue8: 0x9D))
        style.shadowColorSource = .textColor
        style.shadowColor = greenQuarter
        let resolved = style.resolvedShadowColor
        for preset in [OverlayShadowPreset.glow, .hard, .soft, .glow] {
            style.applyShadowPreset(preset)
            XCTAssertEqual(style.shadowColorSource, .textColor, "86.1 follow-text kept by \(preset)")
            XCTAssertEqual(style.shadowColor, greenQuarter)
            XCTAssertEqual(style.resolvedShadowColor, resolved)
            XCTAssertEqual(style.shadowOpacity, 64.0 / 255)
            try assertGeometry(style, preset)
        }
        style.textColor = .white
        XCTAssertEqual(style.resolvedShadowColor, OverlayColor.white.withOpacity(64.0 / 255), "still follows text")
    }

    /// 86.2: color source, color and alpha changes never move the selection.
    func test862ColorAndOpacityChangesKeepSelection() throws {
        for preset in [OverlayShadowPreset.soft, .hard, .glow] {
            var style = OverlayStyle()
            style.applyShadowPreset(preset)
            style.shadowColorSource = .textColor
            XCTAssertEqual(style.shadowPreset, preset)
            style.shadowColorSource = .custom
            style.shadowColor = greenQuarter
            XCTAssertEqual(style.shadowPreset, preset)
            style.shadowColor = OverlayColor(red8: 0xFF, green8: 0, blue8: 0)
            XCTAssertEqual(style.shadowPreset, preset)
            for opacity in [0.05, 0.25, 1.0] {
                style.shadowOpacity = opacity
                XCTAssertEqual(style.shadowPreset, preset, "86.2 opacity \(opacity)")
            }
            try assertGeometry(style, preset)
        }
    }

    /// 86.3: leaving and re-entering a preset's geometry.
    func test863OffPresetThenBack() {
        var style = OverlayStyle()
        style.applyShadowPreset(.hard)
        style.shadowOffsetX = 3
        XCTAssertNil(style.shadowPreset)
        style.shadowOffsetX = 2
        XCTAssertEqual(style.shadowPreset, .hard)
        style.shadowBlur = 4
        XCTAssertNil(style.shadowPreset)
        style.shadowBlur = 0
        style.shadowOffsetY = 0
        XCTAssertNil(style.shadowPreset)
        style.shadowOffsetX = 0
        style.shadowBlur = 4
        style.shadowOffsetY = 2
        XCTAssertEqual(style.shadowPreset, .soft, "geometry alone decides")
    }

    /// 86.4: none turns off only; the next type reuses the old color.
    func test864NoneKeepsColorAndGeometry() throws {
        var style = OverlayStyle()
        style.shadowColorSource = .textColor
        style.shadowColor = greenQuarter
        style.applyShadowPreset(.hard)
        let before = style
        style.applyShadowPreset(.none)
        XCTAssertFalse(style.showsShadow)
        XCTAssertEqual(style.shadowPreset, OverlayShadowPreset.none)
        XCTAssertEqual(style.shadowColorSource, before.shadowColorSource)
        XCTAssertEqual(style.shadowColor, before.shadowColor)
        XCTAssertEqual(style.shadowOffsetX, before.shadowOffsetX)
        XCTAssertEqual(style.shadowOffsetY, before.shadowOffsetY)
        XCTAssertEqual(style.shadowBlur, before.shadowBlur)
        style.applyShadowPreset(.glow)
        XCTAssertEqual(style.shadowColorSource, .textColor)
        XCTAssertEqual(style.shadowColor, greenQuarter)
        try assertGeometry(style, .glow)

        var custom = OverlayStyle()
        custom.shadowColorSource = .custom
        custom.shadowColor = greenQuarter
        custom.applyShadowPreset(.none)
        custom.applyShadowPreset(.soft)
        XCTAssertEqual(custom.shadowColor, greenQuarter)
        XCTAssertEqual(custom.shadowColorSource, .custom)
    }

    /// 86.1 and 86.4 through the real file: the chosen color survives a
    /// type switch, a save and a reload.
    func test861ColorSurvivesSaveAndReload() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ShadowDecouple-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "ShadowDecouple-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }
        let instant = try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 10))
        func makeStore() -> ProfileStore {
            ProfileStore(directory: directory, calendar: DateFixture.taipei, now: { instant }, defaults: defaults, scheduler: ProfileStore.immediateScheduler)
        }
        let store = makeStore()
        store.load()
        var profile = try XCTUnwrap(store.profiles.first)
        profile.style.shadowColorSource = .custom
        profile.style.shadowColor = greenQuarter
        profile.style.applyShadowPreset(.glow)
        profile.style.applyShadowPreset(.none)
        _ = try store.update(profile)
        var reopened = try XCTUnwrap(makeStore().load().first)
        XCTAssertFalse(reopened.style.showsShadow)
        XCTAssertEqual(reopened.style.shadowColor, greenQuarter)
        reopened.style.applyShadowPreset(.hard)
        XCTAssertEqual(reopened.style.shadowColor, greenQuarter)
        XCTAssertEqual(reopened.style.shadowPreset, .hard)
    }

    /// The branch's constants equal origin/main's old values after loading
    /// (read from fca680c: soft black 153/255, hard black 191/255, glow
    /// follow-text 230/255).
    func test865LegacyDecodedColorsEqualOriginMainConstants() throws {
        func decode(_ name: String) throws -> OverlayStyle {
            let json = """
            {"fontID":"pingFang","textColor":"#FFFFFF","outline":"none","shadow":"\(name)","sizeScale":100}
            """
            return try JSONDecoder().decode(OverlayStyle.self, from: Data(json.utf8))
        }
        let soft = try decode("soft")
        XCTAssertEqual(soft.shadowColorSource, .custom)
        XCTAssertEqual(soft.shadowColor, OverlayColor.black.withOpacity(153.0 / 255))
        let hard = try decode("hard")
        XCTAssertEqual(hard.shadowColorSource, .custom)
        XCTAssertEqual(hard.shadowColor, OverlayColor.black.withOpacity(191.0 / 255))
        let glow = try decode("glow")
        XCTAssertEqual(glow.shadowColorSource, .textColor)
        XCTAssertEqual(glow.shadowColor, OverlayColor.black.withOpacity(230.0 / 255))
        let none = try decode("none")
        XCTAssertFalse(none.showsShadow)
        XCTAssertEqual(none.shadowColorSource, .custom)
        XCTAssertEqual(none.shadowColor, OverlayColor.black.withOpacity(153.0 / 255))
        XCTAssertEqual(none.shadowBlur, 4)
        XCTAssertEqual(none.shadowOffsetY, 2)
    }
}
