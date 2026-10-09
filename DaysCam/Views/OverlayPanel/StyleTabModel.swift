import Combine
import Foundation
import UIKit

/// Drives the overlay panel's 樣式 (style) tab: font, color, outline, shadow
/// and size (PRD 0.2 FR-10). Replaces 0.1's fixed theme picker — there is no
/// preset or template, every attribute is adjusted independently (FR-10.1,
/// FR-10.10).
///
/// Follows the same shape as `DisplaySettingsModel`: it holds a working copy
/// of one `CameraProfile` and an injected `updateProfile` closure, so it is
/// constructible and unit-testable without a real `ProfileStore` or panel
/// shell (TASK-22 has not landed yet — this model does not depend on it).
/// Every mutating method writes through immediately; there is no separate
/// save step (FR-8.6).
@MainActor
final class StyleTabModel: ObservableObject {
    /// The five second-layer items (FR-10.1). Case order is display order and
    /// matches the accessibility-label order acceptance 23.1 checks.
    enum SubTab: CaseIterable {
        case color, size, outline, shadow, font

        /// The only user-visible name — these are icon-only buttons, so this
        /// is surfaced purely through the accessibility label (FR-10.1).
        var accessibilityLabel: String {
            switch self {
            case .font: return "字型"
            case .color: return "顏色"
            case .outline: return "外框"
            case .shadow: return "陰影"
            case .size: return "字級"
            }
        }
    }

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
    /// Which second-layer item is selected. In-memory only — not part of the
    /// profile and not persisted, matching `lastPanelTab`'s sibling state.
    @Published var selectedSubTab: SubTab = .color
    /// The most recent `updateProfile` failure, if any, for the view to surface.
    @Published var lastError: Error?

    /// The font list of the 字型 page (TASK-56). Lives as long as this model.
    let fontList: FontLibraryModel

    /// The font list while it is on screen, `nil` otherwise:
    /// `CameraScreenModel` announces "已套用" in it when there is one and on
    /// the camera screen when there is not.
    var fontLibraryModel: FontLibraryModel? { fontList.isVisible ? fontList : nil }

    private let updateProfile: (CameraProfile) throws -> Void
    private let recentColorsStore: RecentColorsStore
    private let fontLibrary: any FontListControlling
    private let applyFont: (OverlayFontID, UUID) -> Void
    private var cancellables: Set<AnyCancellable> = []

    /// Creates a style tab model for `profile`.
    ///
    /// - Parameters:
    ///   - recentColorsStore: Shared across text and outline color, and across
    ///     profiles (PRD A-8). Defaults to a real store backed by
    ///     `UserDefaults.standard`; tests inject their own instance.
    ///   - fontLibrary: Where each font's availability comes from and what
    ///     the font list can cancel or delete (PRD 0.3). The default has only
    ///     PingFang usable (previews, tests); the camera screen injects the
    ///     real `FontLibrary`.
    ///   - applyFont: The one way a font gets written to a profile
    ///     (`applyFont(fontID, profileID)`, FR-5.18), provided by
    ///     `CameraScreenModel`. This model never writes `fontID` itself.
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
            self?.applyFontWeight(weightID, for: fontID)
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

    /// Recently picked custom colors, newest first, shared by text and
    /// outline color (FR-10.4, FR-10.6, FR-10.7, A-8).
    var recentColors: [OverlayColor] {
        recentColorsStore.recentCustomColors
    }

    private func mutate(_ change: (inout OverlayStyle) -> Void) {
        var style = profile.style
        change(&style)
        profile.style = style
        do {
            try updateProfile(profile)
        } catch {
            lastError = error
        }
    }
}

// MARK: - 字型 (PRD 0.3 FR-16, TASK-56)

extension StyleTabModel {
    /// `fontID` (default: the profile's font) at `size`, resolved the way the
    /// viewfinder and the photo resolve it (FR-5.14): the font itself when it
    /// is available, PingFang otherwise. For the font cells and the
    /// outline/shadow previews.
    func resolvedFont(ofSize size: CGFloat, for fontID: OverlayFontID? = nil) -> UIFont {
        guard let fontID, fontID != profile.style.fontID else {
            // The profile's own font keeps its chosen weight (TASK-89).
            return OverlayMetrics.resolvedFont(for: profile.style, availability: fontLibrary).font(ofSize: size)
        }
        return OverlayMetrics.resolvedFont(for: fontID, availability: fontLibrary).font(ofSize: size)
    }

    /// Applies `fontID` to this profile through `applyFont` (FR-5.18).
    func selectFont(_ fontID: OverlayFontID) {
        applyFont(fontID, profile.id)
    }

    /// Writes `weightID` of the profile's current font and saves it. Only a
    /// face the library can already draw reaches here (`FontLibraryModel`
    /// downloads the others first); a weight of another font, an unknown ID
    /// or the weight already set is ignored.
    func applyFontWeight(_ weightID: String, for fontID: OverlayFontID) {
        let entry = FontCatalog.entry(for: fontID)
        guard fontID == profile.style.fontID,
              entry.weights.contains(where: { $0.id == weightID }),
              profile.style.resolvedFontWeight.id != weightID else { return }
        mutate { $0.fontWeight = weightID }
    }
}

// MARK: - 顏色 (FR-10.4, FR-10.6, FR-10.7)

extension StyleTabModel {
    /// The first row of the text-color palette: the nine swatches (FR-10.4).
    /// The view appends its own rainbow `ColorPicker` entry after these, for
    /// ten items total.
    var textColorSwatches: [OverlayColor] { OverlayStyle.swatches }

    /// The first row of the outline-color palette: all nine swatches
    /// (FR-10.6). The view prepends its own "automatic" button (represented
    /// here by `outlineColor == nil`) and appends the rainbow `ColorPicker`,
    /// for eleven items total.
    var outlineColorSwatches: [OverlayColor] { OverlayStyle.swatches }

    /// Whether the outline-color section should be disabled: there is no
    /// outline to color while `outline` is `.none` (FR-10.6).
    var isOutlineColorSectionDisabled: Bool {
        profile.style.outline == .none
    }

    /// Selects `color` as the text color from a swatch or the recent row.
    /// Only the RGB changes; the current opacity is kept (TASK-69).
    func selectTextColor(_ color: OverlayColor) {
        let picked = color.withOpacity(profile.style.textColor.opacity)
        guard picked != profile.style.textColor else { return }
        mutate { $0.textColor = picked }
    }

    /// Selects `color` as the outline color from a swatch or the recent row;
    /// `nil` selects "automatic" (FR-10.6). Only the RGB changes; the current
    /// outline opacity is kept, and "automatic" is fully opaque.
    func selectOutlineColor(_ color: OverlayColor?) {
        let picked = color.map { $0.withOpacity(profile.style.outlineColor?.opacity ?? 1) }
        guard picked != profile.style.outlineColor else { return }
        mutate { $0.outlineColor = picked }
    }

    /// Applies a text color dragged in the custom color picker. Does not touch
    /// the recent list, so intermediate colors never land there (TASK-53);
    /// call `commitCustomColor` once when the picker closes. The picker's
    /// alpha is raised to the storable minimum (TASK-69).
    func applyCustomTextColor(_ color: OverlayColor) {
        let picked = Self.clampingOpacity(color)
        mutate { $0.textColor = picked }
    }

    /// Applies an outline color dragged in the custom color picker, mirroring
    /// `applyCustomTextColor`.
    func applyCustomOutlineColor(_ color: OverlayColor) {
        let picked = Self.clampingOpacity(color)
        mutate { $0.outlineColor = picked }
    }

    /// Adds the final color of a closed custom color picker to the shared
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

// MARK: - 透明度 (TASK-69, #297)

extension StyleTabModel {
    /// Slider bounds, in percent: the storable minimum up to fully opaque.
    static let opacityPercentRange =
        Int((OverlayColor.minimumStorableOpacity * 100).rounded(.up))...100

    /// `color`'s opacity as a whole percent, for the label and the slider.
    static func opacityPercent(of color: OverlayColor) -> Int {
        min(max(Int((color.opacity * 100).rounded()), opacityPercentRange.lowerBound),
            opacityPercentRange.upperBound)
    }

    /// The text color's opacity in percent.
    var textOpacityPercent: Int { Self.opacityPercent(of: profile.style.textColor) }

    /// The outline color's opacity in percent ("automatic" is 100).
    var outlineOpacityPercent: Int {
        Self.opacityPercent(of: profile.style.outlineColor ?? profile.style.resolvedOutlineColor)
    }

    /// Sets the text color's opacity from a slider value in percent, clamped
    /// to `opacityPercentRange`.
    func setTextOpacityPercent(_ percent: Int) {
        let clamped = min(max(percent, Self.opacityPercentRange.lowerBound), Self.opacityPercentRange.upperBound)
        guard clamped != textOpacityPercent else { return }
        mutate { $0.textColor = $0.textColor.withOpacity(Double(clamped) / 100) }
    }

    /// Sets the outline color's opacity. While the outline color is
    /// "automatic", this turns it into the explicit automatic color
    /// (`resolvedOutlineColor`) with that opacity, since "automatic" itself
    /// has no opacity.
    func setOutlineOpacityPercent(_ percent: Int) {
        let clamped = min(max(percent, Self.opacityPercentRange.lowerBound), Self.opacityPercentRange.upperBound)
        guard clamped != outlineOpacityPercent else { return }
        mutate { $0.outlineColor = $0.resolvedOutlineColor.withOpacity(Double(clamped) / 100) }
    }
}

// MARK: - 外框、陰影 (FR-10.5, FR-10.8, FR-10.10)

extension StyleTabModel {
    /// The four outline options, in display order (FR-10.5, TASK-70, TASK-81).
    var outlineOptions: [OverlayOutline] { [.none, .stroke, .box, .squareBox] }

    /// The four shadow options, in display order (FR-10.8).
    var shadowOptions: [OverlayShadowPreset] { OverlayShadowPreset.allCases }

    /// Selects `outline` and persists. Both outline and shadow may be `.none`
    /// at once; nothing here warns about it (FR-10.10, overturning 0.1 FR-4.6).
    func selectOutline(_ outline: OverlayOutline) {
        guard outline != profile.style.outline else { return }
        mutate { $0.outline = outline }
    }

    /// Slider step of the stroke width, in points at a 17pt font.
    static let strokeWidthStep = 0.5
    /// Slider step of the box padding, in points at a 17pt font.
    static let boxPaddingStep = 1.0

    /// Sets `strokeWidth` from a raw slider value, snapped to
    /// `strokeWidthStep` and clamped to `OverlayStyle.strokeWidthRange`
    /// (TASK-70); writes through at once.
    func setStrokeWidth(_ rawValue: Double) {
        let snapped = (rawValue / Self.strokeWidthStep).rounded() * Self.strokeWidthStep
        let range = OverlayStyle.strokeWidthRange
        let clamped = min(max(snapped, range.lowerBound), range.upperBound)
        guard clamped != profile.style.strokeWidth else { return }
        mutate { $0.strokeWidth = clamped }
    }

    /// Sets `boxPadding` from a raw slider value, snapped to `boxPaddingStep`
    /// and clamped to `OverlayStyle.boxPaddingRange` (TASK-70).
    func setBoxPadding(_ rawValue: Double) {
        let snapped = (rawValue / Self.boxPaddingStep).rounded() * Self.boxPaddingStep
        let range = OverlayStyle.boxPaddingRange
        let clamped = min(max(snapped, range.lowerBound), range.upperBound)
        guard clamped != profile.style.boxPadding else { return }
        mutate { $0.boxPadding = clamped }
    }

    /// Selects `shadow` and persists, mirroring `selectOutline`.
    func selectShadow(_ shadow: OverlayShadowPreset) {
        guard shadow != profile.style.shadowPreset else { return }
        mutate { $0.applyShadowPreset(shadow) }
    }

    /// Whether the shadow parameter rows are disabled: there is no shadow to
    /// tune while it is off (preset 無, TASK-71).
    var isShadowParametersDisabled: Bool { !profile.style.showsShadow }

    /// Slider step of the shadow offsets and blur, in points at a 17pt font.
    static let shadowStep = 1.0

    /// Selects the shadow color from a swatch or the recent row: a custom
    /// color at the current shadow opacity. `nil` follows the text color
    /// ("跟隨文字色"). Presets never touch the color (TASK-86).
    func selectShadowColor(_ color: OverlayColor?) {
        mutate { style in
            guard let color else {
                style.shadowColorSource = .textColor
                return
            }
            style.shadowColorSource = .custom
            style.shadowColor = color.withOpacity(style.shadowOpacity)
        }
    }

    /// Applies a color dragged in the custom color picker (alpha included,
    /// clamped to the storable range) as a custom shadow color.
    func applyCustomShadowColor(_ color: OverlayColor) {
        let picked = Self.clampingOpacity(color)
        mutate {
            $0.shadowColorSource = .custom
            $0.shadowColor = picked
        }
    }

    /// The shadow color's opacity in percent.
    var shadowOpacityPercent: Int { Self.opacityPercent(of: profile.style.shadowColor) }

    /// Sets the shadow's opacity from a slider value in percent, clamped to
    /// `opacityPercentRange`.
    func setShadowOpacityPercent(_ percent: Int) {
        let clamped = min(max(percent, Self.opacityPercentRange.lowerBound), Self.opacityPercentRange.upperBound)
        guard clamped != shadowOpacityPercent else { return }
        mutate { $0.shadowOpacity = Double(clamped) / 100 }
    }

    /// Sets `shadowOffsetX` from a raw slider value, snapped to `shadowStep`
    /// and clamped to `OverlayStyle.shadowOffsetRange`.
    func setShadowOffsetX(_ rawValue: Double) {
        let clamped = Self.snappedShadow(rawValue, in: OverlayStyle.shadowOffsetRange)
        guard clamped != profile.style.shadowOffsetX else { return }
        mutate { $0.shadowOffsetX = clamped }
    }

    /// Sets `shadowOffsetY`, like `setShadowOffsetX`.
    func setShadowOffsetY(_ rawValue: Double) {
        let clamped = Self.snappedShadow(rawValue, in: OverlayStyle.shadowOffsetRange)
        guard clamped != profile.style.shadowOffsetY else { return }
        mutate { $0.shadowOffsetY = clamped }
    }

    /// Sets `shadowBlur` from a raw slider value, snapped to `shadowStep` and
    /// clamped to `OverlayStyle.shadowBlurRange`.
    func setShadowBlur(_ rawValue: Double) {
        let clamped = Self.snappedShadow(rawValue, in: OverlayStyle.shadowBlurRange)
        guard clamped != profile.style.shadowBlur else { return }
        mutate { $0.shadowBlur = clamped }
    }

    private static func snappedShadow(_ rawValue: Double, in range: ClosedRange<Double>) -> Double {
        let snapped = (rawValue / shadowStep).rounded() * shadowStep
        return min(max(snapped, range.lowerBound), range.upperBound)
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
