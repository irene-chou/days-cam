// Generates DaysCam/Resources/Settings.bundle: the 致謝 → 字型授權 pages of the
// iOS Settings app (#677). The pages are built from `FontLicenseModel`, so the
// text can never drift from what the model lists; `SettingsAcknowledgementsTests`
// fails when the committed plists differ from it.
//
// Run again after changing the font catalog or any file in
// DaysCam/Resources/FontLicenses (macOS, from the repo root):
//
//   swiftc -parse-as-library -o /tmp/generate-settings-acknowledgements \
//     scripts/generate-settings-acknowledgements.swift DaysCam/Models/*.swift \
//     DaysCam/Views/Theme/CameraTheme.swift DaysCam/Views/OverlayPanel/FontLicenseView.swift \
//   && /tmp/generate-settings-acknowledgements
//
// The script exits non-zero if a license file is missing, so an empty license
// can never be written silently.

import Foundation

@main
struct GenerateSettingsAcknowledgements {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let resources = root.appendingPathComponent("DaysCam/Resources", isDirectory: true)
        let licenses = resources.appendingPathComponent("FontLicenses", isDirectory: true)
        let bundle = resources.appendingPathComponent("Settings.bundle", isDirectory: true)

        var missing: [String] = []
        let model = FontLicenseModel(loadText: { fileName in
            let text = try? String(contentsOf: licenses.appendingPathComponent(fileName), encoding: .utf8)
            if text == nil { missing.append(fileName) }
            return text
        })
        guard missing.isEmpty else {
            FileHandle.standardError.write(Data("missing license files: \(missing.joined(separator: ", "))\n".utf8))
            exit(1)
        }

        try? FileManager.default.removeItem(at: bundle)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)

        try write(Plists.rootPlist(), named: "Root", to: bundle)
        try write(Plists.acknowledgementsPlist(for: model), named: "Acknowledgements", to: bundle)
        for entry in model.entries {
            try write(Plists.fontPlist(for: entry),
                      named: Plists.fileName(for: entry), to: bundle)
        }
        print("wrote \(2 + model.entries.count) plists to \(bundle.path)")
    }

    private static func write(_ plist: [String: Any], named name: String, to directory: URL) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: directory.appendingPathComponent("\(name).plist"))
    }
}

/// The three kinds of page, in the shape Settings.bundle expects.
enum Plists {
    static func fileName(for entry: FontLicenseModel.Entry) -> String { "Font-\(entry.fontID.rawValue)" }

    private static func group(_ title: String, footer: String? = nil) -> [String: Any] {
        var item: [String: Any] = ["Type": "PSGroupSpecifier", "Title": title]
        if let footer { item["FooterText"] = footer }
        return item
    }

    private static func pane(_ title: String, file: String) -> [String: Any] {
        ["Type": "PSChildPaneSpecifier", "Title": title, "File": file]
    }

    private static func page(_ title: String, _ items: [[String: Any]]) -> [String: Any] {
        ["Title": title, "PreferenceSpecifiers": items]
    }

    /// 致謝 → 字型授權. No preference switches, only acknowledgements.
    static func rootPlist() -> [String: Any] {
        page("設定", [group("致謝"), pane(FontLicenseModel.pageTitle, file: "Acknowledgements")])
    }

    /// One row per open-source font, then the note about system fonts.
    static func acknowledgementsPlist(for model: FontLicenseModel) -> [String: Any] {
        page(FontLicenseModel.pageTitle,
             model.entries.map { pane($0.name, file: fileName(for: $0)) }
                 + [group("", footer: FontLicenseModel.systemFontNote)])
    }

    /// One font: a group per weight file (file name in the title, version and
    /// copyright in the footer), the source note, then every license text.
    static func fontPlist(for entry: FontLicenseModel.Entry) -> [String: Any] {
        var items: [[String: Any]] = []
        if entry.files.isEmpty {
            items.append(group(entry.name, footer: "版本 \(entry.version)\n\(entry.copyright)"))
        }
        for file in entry.files {
            items.append(group("\(file.fileName)（\(file.weightName)）",
                               footer: "版本 \(file.version)\n\(file.copyright)"))
        }
        if let note = entry.sourceNote { items.append(group("來源", footer: note)) }
        for license in entry.licenses { items.append(group(license.title, footer: license.text)) }
        return page(entry.name, items)
    }
}
