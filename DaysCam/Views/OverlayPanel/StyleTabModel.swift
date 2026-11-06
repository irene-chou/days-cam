import Combine
import Foundation
import UIKit

/// Drives the overlay panel's 樣式 (style) tab (D-10, #678): a row of ten
/// named looks (`OverlayStylePreset`), the text color, the box button and the
/// size. A look sets the font, outline and shadow as one; only the color, the
/// box state and the size are adjusted on their own.
///
/// Follows the same shape as `DisplaySettingsModel`: it holds a working copy
/// of one `CameraProfile` and an injected `updateProfile` closure, so it is
/// constructible and unit-testable without a real `ProfileStore` or panel
/// shell. Every mutating method writes through immediately; there is no
/// separate save step (FR-8.6).
@MainActor
final class StyleTabModel: ObservableObject {
    /// The profile as currently configured. Read-only from outside: every
    /// change goes through one of this model's setters so it is always
    /// persisted (FR-8.6).
    @Published private(set) var profile: CameraProfile {
        // Keeps the font list's selection on the profile's font.
        didSet {
            fontList.update(profileID: profile.id,
                            currentFontID: profile.style.fontID,
                            currentWeightID: profile.style.fontWeight)
        }
    }
    /// The most recent `updateProfile` failure, if any, for the view to surface.
    @Published var lastError: Error?

    /// The font list of the former 字型 page (TASK-56). No longer shown
    /// (#678); kept because `StyleEditingCenter` still reads its pending
    /// weight. Lives as long as this model.
    let fontList: FontLibraryModel

    /// The font list while it is on screen: always `nil` since the list left
    /// the panel (#678), so "已套用" and failures go to the toast.
    var fontLibraryModel: FontLibraryModel? { nil }

    private let updateProfile: (CameraProfile) throws -> Void
    private let recentColorsStore: RecentColorsStore
    private let fontLibrary: any FontListControlling
    private let applyFont: (OverlayFontID, UUID) -> Void
    private var cancellables: Set<AnyCancellable> = []

    /// Creates a style tab model for `profile`.
    ///
    /// - Parameters:
    ///   - recentColorsStore: Shared across profiles (PRD A-8). Defaults to a real store backed by
    ///     `UserDefaults.standard`; tests inject their own instance.
    ///   - fontLibrary: Where each font's availability comes from and what
    ///     the font list can cancel or delete (PRD 0.3). The default has only
    ///     PingFang usable (previews, tests); the camera screen injects the
    ///     real `FontLibrary`.
    ///   - applyFont: Downloads a font and writes it once usable
    ///     (`applyFont(fontID, profileID)`, FR-5.18), provided by
    ///     `StyleEditingCenter`. `selectPreset` writes the look's font itself
    ///     and calls this only to download a font that is not usable yet.
    ///   - allProfiles: Every profile, to count who uses a font before it is
    ///     deleted.
    ///   - updateProfile: Forwarded to the real persistence layer by the
    ///     caller, called after every change. Throws to report a failure;
    ///     this model does not interpret the error, it only surfaces it.
    init(profile: CameraProfile,
         recentColorsStore: RecentColorsStore = RecentColorsStore(),
         fontLibrary: (any FontListControlling)? = nil,
         applyFont: @escaping (OverlayFontID, UUID) -> Void,
         allProfiles: @escaping () -> [CameraProfile],
         updateProfile: @escaping (CameraProfile) throws -> Void) {
        self.profile = profile
        self.recentColorsStore = recentColorsStore
        self.fontLibrary = fontLibrary ?? StaticFontLibrary()
        self.applyFont = applyFont
        self.updateProfile = updateProfile
        self.fontList = FontLibraryModel(profileID: profile.id,
                                         currentFontID: profile.style.fontID,
                                         currentWeightID: profile.style.fontWeight,
                                         library: self.fontLibrary,
                                         profiles: allProfiles,
                                         applyFont: applyFont)
        // The weight goes through this model's own saving path, so the
        // closure can only be set once `self` is complete.
        fontList.applyWeight = { [weak self] fontID, weightID in
            self?.applyFontWeight(weightID, for: fontID) ?? false
        }
        fontList.applyFontWithWeight = { [weak self] fontID, weightID in
            self?.applyFontWithWeight(fontID, weightID: weightID) ?? false
        }

        // Forward the store's changes so a view observing only this model
        // (not the store separately) still redraws when the recent-colors
        // row changes.
        recentColorsStore.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // A font changing state redraws the previews that use the font.
        self.fontLibrary.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    /// Takes over the fields other writers own, from the latest copy of this
    /// profile (PRD 0.3 FR-5.18; same idea as `RulesTabModel`).
    ///
    /// Only `style.fontID` and `style.fontWeight` are taken: `applyFont`
    /// writes them outside this tab, and this tab's own copy must not write
    /// the old font or weight back the next time it changes a color.
    /// Everything else in the style is this tab's own. Does not persist
    /// anything; ignores another profile.
    func applyExternalChanges(from latest: CameraProfile) {
        guard latest.id == profile.id else { return }
        guard latest.style.fontID != profile.style.fontID
                || latest.style.fontWeight != profile.style.fontWeight else { return }
        var style = profile.style
        // Changing `fontID` resets the weight, so the weight is set after it.
        style.fontID = latest.style.fontID
        style.fontWeight = latest.style.fontWeight
        profile.style = style
    }

    /// Recently picked custom text colors, newest first (FR-10.7, A-8).
    var recentColors: [OverlayColor] {
        recentColorsStore.recentCustomColors
    }

    /// - Returns: whether the change was saved.
    @discardableResult
    private func mutate(_ change: (inout OverlayStyle) -> Void) -> Bool {
        var style = profile.style
        change(&style)
        profile.style = style
        do {
            try updateProfile(profile)
            return true
        } catch {
            lastError = error
            return false
        }
    }
}

// MARK: - 樣式列 (D-10, #678)

extension StyleTabModel {
    /// The ten looks, in the order the row shows them.
    var presets: [OverlayStylePreset] { OverlayStylePreset.allCases }

    /// The look the profile shows as; `nil` for a custom style, which the
    /// row marks with an extra 自訂 capsule. The text color and the size do
    /// not count (`OverlayStyle.preset`).
    var selectedPreset: OverlayStylePreset? { profile.style.preset }

    /// The box button's state; `nil` for a custom style, when the button is
    /// disabled.
    var boxState: OverlayBoxState? {
        profile.style.preset.flatMap { profile.style.boxState(for: $0) }
    }

    /// The state of the exact face `preset` uses, for the capsule's badge.
    func fontState(for preset: OverlayStylePreset) -> FontState {
        let look = preset.style
        return fontLibrary.state(for: look.fontID, weightID: look.fontWeight)
    }

    /// `preset`'s own face at `size` when it is usable, PingFang otherwise
    /// (FR-5.14), for the capsule's name.
    func nameFont(for preset: OverlayStylePreset, ofSize size: CGFloat) -> UIFont {
        OverlayMetrics.resolvedFont(for: preset.style, availability: fontLibrary).font(ofSize: size)
    }

    /// Applies `preset` with one save: font, weight, outline and shadow; the
    /// text color only when it is still the old look's default (#676). This
    /// writes `fontID` itself, past FR-5.18's single writer, so the capsule
    /// is selected while the font downloads; until then the text falls back
    /// to PingFang (A-4).
    ///
    /// A face that is not usable yet starts downloading: the font's default
    /// face through `applyFont`, which announces it when done; another face
    /// (思源黑體 特粗) straight from the library, since `applyFont` only fetches
    /// default faces. Tapping the selected look again retries a failed
    /// download.
    func selectPreset(_ preset: OverlayStylePreset) {
        var style = profile.style
        style.apply(preset)
        if style != profile.style {
            guard mutate({ $0 = style }) else { return }
        }
        downloadFontIfNeeded(for: preset)
    }

    /// Moves the box button to its next state (base, solid, translucent) and
    /// saves. Does nothing for a custom style.
    func cycleBoxState() {
        guard let preset = selectedPreset else { return }
        mutate { $0.cycleBoxState(for: preset) }
    }

    private func downloadFontIfNeeded(for preset: OverlayStylePreset) {
        let look = preset.style
        let state = fontState(for: preset)
        switch state {
        case .available, .downloading: return
        case .notDownloaded, .failed, .preparing: break
        }
        let entry = FontCatalog.entry(for: look.fontID)
        if entry.weight(for: look.fontWeight).id == entry.defaultWeight.id {
            applyFont(look.fontID, profile.id)
        } else if state != .preparing {
            fontLibrary.download(look.fontID, weightID: look.fontWeight)
        }
    }
}

// MARK: - 字重 (TASK-89, the hidden font list's write path)

private extension StyleTabModel {
    /// Writes `weightID` of the profile's current font and saves it. Only a
    /// face the library can already draw reaches here; a weight of another
    /// font or an unknown ID is ignored.
    ///
    /// - Returns: whether the profile now has `weightID` saved. When saving
    ///   fails the old weight is put back (and `lastError` is set).
    func applyFontWeight(_ weightID: String, for fontID: OverlayFontID) -> Bool {
        let entry = FontCatalog.entry(for: fontID)
        guard fontID == profile.style.fontID,
              entry.weights.contains(where: { $0.id == weightID }) else { return false }
        guard profile.style.resolvedFontWeight.id != weightID else { return true }
        let previous = profile
        guard mutate({ $0.fontWeight = weightID }) else {
            profile = previous
            return false
        }
        return true
    }

    /// Writes `fontID` and `weightID` together with one save (TASK-115).
    ///
    /// - Returns: whether the profile now has both. When saving fails the old
    ///   font and weight are both put back (and `lastError` is set).
    func applyFontWithWeight(_ fontID: OverlayFontID, weightID: String) -> Bool {
        guard FontCatalog.entry(for: fontID).weights.contains(where: { $0.id == weightID }) else { return false }
        if fontID == profile.style.fontID { return applyFontWeight(weightID, for: fontID) }
        let previous = profile
        guard mutate({
            // Changing `fontID` resets the weight, so the weight comes after.
            $0.fontID = fontID
            $0.fontWeight = weightID
        }) else {
            profile = previous
            return false
        }
        return true
    }
}

// MARK: - 顏色 (FR-10.4, FR-10.7)

extension StyleTabModel {
    /// The first row of the text-color palette: the nine swatches (FR-10.4).
    /// The view appends its own rainbow `ColorPicker` entry after these, for
    /// ten items total.
    var textColorSwatches: [OverlayColor] { OverlayStyle.swatches }

    /// The light row under the text-color swatches, column for column
    /// (TASK-149, #518).
    var textColorLightSwatches: [OverlayColor] { OverlayStyle.lightSwatches }

    /// Selects `color` as the text color from a swatch or the recent row,
    /// fully opaque: a swatch never carries a hidden opacity, which is set
    /// only in the color picker (TASK-113, replacing TASK-69's kept opacity).
    func selectTextColor(_ color: OverlayColor) {
        let picked = color.withOpacity(1)
        guard picked != profile.style.textColor else { return }
        mutate { $0.textColor = picked }
    }

    /// Applies a text color dragged in the custom color picker. Does not touch
    /// the recent list, so intermediate colors never land there (TASK-53);
    /// call `commitCustomColor` once when the picker closes. The picker's
    /// alpha is raised to the storable minimum (TASK-69).
    func applyCustomTextColor(_ color: OverlayColor) {
        let picked = Self.clampingOpacity(color)
        mutate { $0.textColor = picked }
    }

    /// Adds the final color of a closed custom color picker to the
    /// recent-colors list (FR-10.7). Preset swatches are ignored by the store.
    /// Only the RGB is remembered: opacity belongs to the current setting, not
    /// to the recent color (TASK-69).
    func commitCustomColor(_ color: OverlayColor) {
        recentColorsStore.add(color.withOpacity(1))
    }

    /// Whether `lhs` and `rhs` are the same color ignoring opacity, for the
    /// selection ring (a swatch stays selected at any opacity).
    static func hasSameRGB(_ lhs: OverlayColor, _ rhs: OverlayColor) -> Bool {
        let a = lhs.quantized, b = rhs.quantized
        return a.red == b.red && a.green == b.green && a.blue == b.blue
    }

    private static func clampingOpacity(_ color: OverlayColor) -> OverlayColor {
        color.withOpacity(min(max(color.opacity, OverlayColor.minimumStorableOpacity), 1))
    }
}

// MARK: - 字級 (FR-10.9)

extension StyleTabModel {
    /// Slider bounds, in percent (FR-10.9).
    static let sizeScaleRange = OverlayStyle.minimumSizeScale...OverlayStyle.maximumSizeScale
    /// Slider step, in percent (FR-10.9).
    static let sizeScaleStep = OverlayStyle.sizeScaleStep

    /// Sets `sizeScale` from a raw slider value, snapping to the nearest
    /// multiple of `sizeScaleStep` and clamping to `sizeScaleRange`.
    ///
    /// The slider itself is expected to already snap to steps of 5 (SwiftUI's
    /// `Slider(value:in:step:)` does), but a raw value in between (for example
    /// a value the view passed straight from a drag gesture) is rounded here
    /// rather than truncated, so 72 lands on 70 and not on some other value
    /// that happens to be a multiple of 5.
    func setSizeScale(_ rawValue: Int) {
        let step = Self.sizeScaleStep
        let snapped = Int((Double(rawValue) / Double(step)).rounded()) * step
        let clamped = min(max(snapped, OverlayStyle.minimumSizeScale), OverlayStyle.maximumSizeScale)
        guard clamped != profile.style.sizeScale else { return }
        mutate { $0.sizeScale = clamped }
    }

    /// Sets `sizeScale` back to `OverlayStyle`'s default (TASK-49 E). Goes
    /// through `setSizeScale`, so nothing is written when already default.
    func resetSizeScale() {
        setSizeScale(OverlayStyle().sizeScale)
    }
}
