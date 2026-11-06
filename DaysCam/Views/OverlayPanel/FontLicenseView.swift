import SwiftUI

/// What the read-only license page shows (PRD 0.3 FR-16.13, A-5).
struct FontLicenseModel {
    /// One license text of a font.
    struct License: Identifiable, Equatable {
        /// "SIL Open Font License 1.1" or "Apache License 2.0".
        let title: String
        /// The full text from `Resources/FontLicenses/`; empty if the file is
        /// missing from the bundle.
        let text: String
        var id: String { title }
    }

    /// One downloadable font file (one weight) and its own notice.
    struct FileNotice: Identifiable, Equatable {
        /// "NotoSerifTC-Black.otf".
        let fileName: String
        /// The weight it carries, e.g. "特粗".
        let weightName: String
        let version: String
        /// The copyright notice, verbatim from the catalog.
        let copyright: String
        var id: String { fileName }
    }

    /// One open-source font and its notices.
    struct Entry: Identifiable, Equatable {
        let fontID: OverlayFontID
        let name: String
        /// The default face's version and copyright.
        let version: String
        let copyright: String
        /// Every file the font ships, one per weight (TASK-89).
        let files: [FileNotice]
        /// Each license text once, even when several files share it.
        let licenses: [License]
        /// Where the font comes from and who must be named, for fonts whose
        /// license asks for it (TASK-142); `nil` for the rest.
        let sourceNote: String?
        var id: OverlayFontID { fontID }
    }

    /// The page title, and the note about system fonts (A-5).
    static let pageTitle = "字型授權"
    static let systemFontNote = "其餘字型為 Apple 提供的系統字型，由 iOS 管理，只用來在 App 內畫出疊字，不提供匯出。"

    let entries: [Entry]

    /// Builds the page from the catalog's open-source fonts, reading each
    /// license file with `loadText` (a file name such as `huninn-OFL.txt`).
    init(catalog: [FontCatalogEntry] = FontCatalog.entries,
         loadText: (String) -> String? = FontLicenseModel.bundleText) {
        entries = catalog.compactMap { entry in
            guard let asset = entry.openSource else { return nil }
            // One notice per weight file; a license shared by several files
            // is listed (and read) once.
            let weights = entry.weights.filter { $0.openSource != nil }
            let files = weights.compactMap { weight in
                weight.openSource.map {
                    FileNotice(fileName: $0.fileName, weightName: weight.displayName,
                               version: $0.version, copyright: $0.copyright)
                }
            }
            var seen = Set<String>()
            let licenseNames = (weights.isEmpty ? [asset] : weights.compactMap(\.openSource))
                .flatMap(\.licenseFileNames)
                .filter { seen.insert($0).inserted }
            return Entry(fontID: entry.fontID,
                         name: entry.displayName,
                         version: asset.version,
                         copyright: asset.copyright,
                         files: files,
                         licenses: licenseNames.map { fileName in
                             License(title: Self.licenseTitle(forFileName: fileName), text: loadText(fileName) ?? "")
                         },
                         sourceNote: FontCatalog.downloadFamiliesByID[entry.fontID]?.sourceNote)
        }
    }

    /// The heading of a license file, from the suffix its name carries
    /// (`<fontID>-OFL.txt`, `-MIT`, `-OGDL`, `-CCBYND`, `-APL`).
    static func licenseTitle(forFileName fileName: String) -> String {
        if fileName.contains("Apache") { return "Apache License 2.0" }
        if fileName.hasSuffix("-MIT.txt") { return "MIT License" }
        if fileName.hasSuffix("-OGDL.txt") { return "政府資料開放授權條款－第1版" }
        if fileName.hasSuffix("-CCBYND.txt") { return "創用 CC 姓名標示─禁止改作 3.0 台灣（CC BY-ND 3.0 TW）" }
        if fileName.hasSuffix("-APL.txt") { return "Arphic Public License" }
        return "SIL Open Font License 1.1"
    }

    /// Reads a license file from the App bundle.
    static func bundleText(_ fileName: String) -> String? {
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        guard let url = Bundle.main.url(forResource: base, withExtension: ext) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
