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
                         })
        }
    }

    static func licenseTitle(forFileName fileName: String) -> String {
        fileName.contains("Apache") ? "Apache License 2.0" : "SIL Open Font License 1.1"
    }

    /// Reads a license file from the App bundle.
    static func bundleText(_ fileName: String) -> String? {
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        guard let url = Bundle.main.url(forResource: base, withExtension: ext) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

/// The 字型授權 page: the three open-source fonts with version, copyright
/// notice and full license text, and a note that system fonts come from Apple
/// (PRD 0.3 FR-16.13). Read-only; nothing here can be exported (§7).
struct FontLicenseView: View {
    let model: FontLicenseModel
    var onBack: () -> Void = {}

    init(model: FontLicenseModel = FontLicenseModel(), onBack: @escaping () -> Void = {}) {
        self.model = model
        self.onBack = onBack
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(model.entries) { entry in
                        entryView(entry)
                    }
                    Text(FontLicenseModel.systemFontNote)
                        .font(.footnote)
                        .foregroundColor(CameraTheme.inkSecondary)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color.white)
    }

    private var header: some View {
        HStack(spacing: 0) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(CameraTheme.active)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("返回")
            Text(FontLicenseModel.pageTitle)
                .font(CameraTheme.toolFont(.headline))
                .foregroundColor(CameraTheme.ink)
            Spacer()
        }
        .padding(.leading, 8)
        .padding(.top, 14)
    }

    private func entryView(_ entry: FontLicenseModel.Entry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if entry.files.count > 1 {
                Text(entry.name)
                    .font(CameraTheme.toolFont(.subheadline))
                    .foregroundColor(CameraTheme.ink)
                ForEach(entry.files) { file in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(file.fileName)　\(file.weightName)　版本 \(file.version)")
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(CameraTheme.ink)
                        Text(file.copyright)
                            .font(.footnote)
                            .foregroundColor(CameraTheme.inkSecondary)
                            .textSelection(.enabled)
                    }
                }
            } else {
                Text("\(entry.name)　版本 \(entry.version)")
                    .font(CameraTheme.toolFont(.subheadline))
                    .foregroundColor(CameraTheme.ink)
                Text(entry.copyright)
                    .font(.footnote)
                    .foregroundColor(CameraTheme.inkSecondary)
                    .textSelection(.enabled)
            }
            ForEach(entry.licenses) { license in
                VStack(alignment: .leading, spacing: 4) {
                    Text(license.title)
                        .font(.caption.weight(.bold))
                        .foregroundColor(CameraTheme.inkTertiary)
                    Text(license.text)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(CameraTheme.inkSecondary)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

#Preview("字型授權") {
    FontLicenseView(model: FontLicenseModel(), onBack: {})
}
