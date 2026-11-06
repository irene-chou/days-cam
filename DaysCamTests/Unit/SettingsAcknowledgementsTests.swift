import XCTest
@testable import DaysCam

/// #677: the Settings.bundle in the app carries the same 字型授權 text as
/// `FontLicenseModel`. A failure means a font or a license file changed
/// without regenerating the plists.
final class SettingsAcknowledgementsTests: XCTestCase {
    private static let regenerate = "Run scripts/generate-settings-acknowledgements.swift again (usage in docs/WORKFLOW.md)."

    private typealias Item = [String: String]

    private func load(_ name: String) throws -> (title: String, items: [Item]) {
        let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "plist",
                                                subdirectory: "Settings.bundle"),
                                "\(name).plist is not in Settings.bundle")
        let plist = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: Any])
        let items = try XCTUnwrap(plist["PreferenceSpecifiers"] as? [Item])
        return (try XCTUnwrap(plist["Title"] as? String), items)
    }

    /// 1: Root has the 致謝 group and the one 字型授權 row, nothing else.
    func testRootHasOnlyTheAcknowledgementsGroupAndOneRow() throws {
        let root = try load("Root")
        XCTAssertEqual(root.items.count, 2)
        XCTAssertEqual(root.items[0]["Type"], "PSGroupSpecifier")
        XCTAssertEqual(root.items[0]["Title"], "致謝")
        XCTAssertEqual(root.items[1]["Type"], "PSChildPaneSpecifier")
        XCTAssertEqual(root.items[1]["Title"], FontLicenseModel.pageTitle)
        XCTAssertEqual(root.items[1]["File"], "Acknowledgements")
    }

    /// 2: the index lists every font in model order and ends with the system font note.
    func testAcknowledgementsListEveryFontInOrderWithTheSystemFontNote() throws {
        let model = FontLicenseModel()
        XCTAssertFalse(model.entries.isEmpty)
        let page = try load("Acknowledgements")
        XCTAssertEqual(page.items.count, model.entries.count + 1, Self.regenerate)
        for (item, entry) in zip(page.items, model.entries) {
            XCTAssertEqual(item["Type"], "PSChildPaneSpecifier")
            XCTAssertEqual(item["Title"], entry.name, Self.regenerate)
            XCTAssertEqual(item["File"], "Font-\(entry.fontID.rawValue)", Self.regenerate)
        }
        let last = try XCTUnwrap(page.items.last)
        XCTAssertEqual(last["Type"], "PSGroupSpecifier")
        XCTAssertEqual(last["FooterText"], FontLicenseModel.systemFontNote, Self.regenerate)
    }

    /// 2: each font page repeats every file's version and copyright, the
    /// source note (CC BY-ND authorship) and the full license texts.
    func testEveryFontPageMatchesTheModel() throws {
        for entry in FontLicenseModel().entries {
            let page = try load("Font-\(entry.fontID.rawValue)")
            let footers = page.items.compactMap { $0["FooterText"] }
            XCTAssertEqual(page.title, entry.name, Self.regenerate)
            if entry.files.isEmpty {
                XCTAssertTrue(footers.contains("版本 \(entry.version)\n\(entry.copyright)"), "\(entry.name): \(Self.regenerate)")
            }
            for file in entry.files {
                let item = page.items.first { $0["Title"] == "\(file.fileName)（\(file.weightName)）" }
                XCTAssertEqual(item?["FooterText"], "版本 \(file.version)\n\(file.copyright)",
                               "\(entry.name) \(file.fileName): \(Self.regenerate)")
            }
            if let note = entry.sourceNote {
                XCTAssertTrue(page.items.contains { $0["Title"] == "來源" && $0["FooterText"] == note },
                              "\(entry.name) source note: \(Self.regenerate)")
            }
            for license in entry.licenses {
                XCTAssertFalse(license.text.isEmpty, "\(entry.name) \(license.title) has no text")
                let item = page.items.first { $0["Title"] == license.title }
                XCTAssertEqual(item?["FooterText"], license.text, "\(entry.name) \(license.title): \(Self.regenerate)")
            }
            let expected = entry.files.count + (entry.files.isEmpty ? 1 : 0) + (entry.sourceNote == nil ? 0 : 1)
                + entry.licenses.count
            XCTAssertEqual(page.items.count, expected, "\(entry.name): \(Self.regenerate)")
        }
    }

    /// The CC BY-ND font names its author.
    func testTheCCBYNDFontCarriesItsSourceNote() {
        let notes = FontLicenseModel().entries.filter { $0.licenses.contains { $0.title.contains("CC BY-ND") } }
        XCTAssertFalse(notes.isEmpty)
        for entry in notes { XCTAssertNotNil(entry.sourceNote, entry.name) }
    }
}
