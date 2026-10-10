import Combine
import Foundation

/// The app-wide list of recently picked custom colors (PRD 0.2 FR-10.7, A-8).
///
/// Shared by text and outline colors and across profiles. Stored in
/// `UserDefaults` as `hexString` strings (`#RRGGBB`, or `#RRGGBBAA` for a
/// translucent color), newest first. Colors are compared by their 8-bit hex
/// value, alpha included, so two picker results that round to the same hex
/// count as the same color.
final class RecentColorsStore: ObservableObject {
    /// Maximum number of colors kept (FR-10.7).
    static let capacity = 7
    /// `UserDefaults` key holding the list.
    static let defaultsKey = "recentCustomColors"

    /// Recently picked custom colors, newest first, at most `capacity`.
    @Published private(set) var recentCustomColors: [OverlayColor]

    private let defaults: UserDefaults

    /// Creates a store reading from `defaults`; tests pass their own suite.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.stringArray(forKey: Self.defaultsKey) ?? []
        recentCustomColors = Array(stored.compactMap(OverlayColor.init(hex:)).prefix(Self.capacity))
    }

    /// Records a color chosen with the system color picker (FR-10.7).
    ///
    /// Moves it to the front, dropping any earlier copy; drops the oldest when
    /// more than `capacity` remain. A color equal to one of the preset
    /// swatches is ignored, since it is already one tap away.
    func add(_ color: OverlayColor) {
        let hex = color.hexString
        guard !OverlayStyle.swatches.contains(where: { $0.hexString == hex }),
              let normalized = OverlayColor(hex: hex) else { return }

        var updated = recentCustomColors.filter { $0.hexString != hex }
        updated.insert(normalized, at: 0)
        recentCustomColors = Array(updated.prefix(Self.capacity))
        defaults.set(recentCustomColors.map(\.hexString), forKey: Self.defaultsKey)
    }
}
