import Foundation

/// How a photo is exported from the browse screen (PRD 2.0 §4.1).
///
/// An unknown raw value decodes to `.overlay` rather than failing, so a file
/// written by a newer version never costs the profile that carries it.
enum ExportFormat: String, Codable, CaseIterable {
    /// The overlay is printed straight onto the photo.
    case overlay
    /// The photo is framed as a Polaroid with the text on its border.
    case polaroid

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ExportFormat(rawValue: raw) ?? .overlay
    }
}
