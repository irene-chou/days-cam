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
        didSet { fontList.update(profileID: profile.id, currentFontID: profile.style.fontID) }
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
                                         library: self.fontLibrary,
                                         profiles: allProfiles,
                                         applyFont: applyFont)

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
    /// Only `style.fontID` is taken: `applyFont` writes it
    /// outside this tab, and this tab's own copy must not write the old font
    /// back the next time it changes a color. Everything else in the style is
    /// this tab's own. Does not persist anything; ignores another profile.
    func applyExternalChanges(from latest: CameraProfile) {
        guard latest.id == profile.id else { return }
        if latest.style.fontID != profile.style.fontID {
            profile.style.fontID = latest.style.fontID
        }
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
        OverlayMetrics.resolvedFont(for: fontID ?? profile.style.fontID, availability: fontLibrary)
            .font(ofSize: size)
    }

    /// Applies `fontID` to this profile through `applyFont` (FR-5.18).
    func selectFont(_ fontID: OverlayFontID) {
        applyFont(fontID, profile.id)
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
    func selectTextColor(_ color: OverlayColor) {
        guard color != profile.style.textColor else { return }
        mutate { $0.textColor = color }
    }

    /// Selects `color` as the outline color from a swatch or the recent row;
    /// `nil` selects "automatic" (FR-10.6).
    func selectOutlineColor(_ color: OverlayColor?) {
        guard color != profile.style.outlineColor else { return }
        mutate { $0.outlineColor = color }
    }

    /// Applies a text color dragged in the custom color picker. Does not touch
    /// the recent list, so intermediate colors never land there (TASK-53);
    /// call `commitCustomColor` once when the picker closes.
    func applyCustomTextColor(_ color: OverlayColor) {
        mutate { $0.textColor = color }
    }

    /// Applies an outline color dragged in the custom color picker, mirroring
    /// `applyCustomTextColor`.
    func applyCustomOutlineColor(_ color: OverlayColor) {
        mutate { $0.outlineColor = color }
    }

    /// Adds the final color of a closed custom color picker to the shared
    /// recent-colors list (FR-10.7). Preset swatches are ignored by the store.
    func commitCustomColor(_ color: OverlayColor) {
        recentColorsStore.add(color)
    }
}

// MARK: - 外框、陰影 (FR-10.5, FR-10.8, FR-10.10)

extension StyleTabModel {
    /// The five outline options, in display order (FR-10.5).
    var outlineOptions: [OverlayOutline] { OverlayOutline.allCases }

    /// The four shadow options, in display order (FR-10.8).
    var shadowOptions: [OverlayShadow] { OverlayShadow.allCases }

    /// Selects `outline` and persists. Both outline and shadow may be `.none`
    /// at once; nothing here warns about it (FR-10.10, overturning 0.1 FR-4.6).
    func selectOutline(_ outline: OverlayOutline) {
        guard outline != profile.style.outline else { return }
        mutate { $0.outline = outline }
    }

    /// Selects `shadow` and persists, mirroring `selectOutline`.
    func selectShadow(_ shadow: OverlayShadow) {
        guard shadow != profile.style.shadow else { return }
        mutate { $0.shadow = shadow }
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
