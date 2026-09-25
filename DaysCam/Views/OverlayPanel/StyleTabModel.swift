import Combine
import Foundation

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
        case font, color, outline, shadow, size

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
    @Published private(set) var profile: CameraProfile
    /// Which second-layer item is selected. In-memory only — not part of the
    /// profile and not persisted, matching `lastPanelTab`'s sibling state.
    @Published var selectedSubTab: SubTab = .font
    /// The most recent `updateProfile` failure, if any, for the view to surface.
    @Published var lastError: Error?

    private let updateProfile: (CameraProfile) throws -> Void
    private let recentColorsStore: RecentColorsStore
    private var cancellables: Set<AnyCancellable> = []

    /// Creates a style tab model for `profile`.
    ///
    /// - Parameters:
    ///   - recentColorsStore: Shared across text and outline color, and across
    ///     profiles (PRD A-8). Defaults to a real store backed by
    ///     `UserDefaults.standard`; tests inject their own instance.
    ///   - updateProfile: Forwarded to the real persistence layer by the
    ///     caller, called after every change. Throws to report a failure;
    ///     this model does not interpret the error, it only surfaces it.
    init(profile: CameraProfile,
         recentColorsStore: RecentColorsStore = RecentColorsStore(),
         updateProfile: @escaping (CameraProfile) throws -> Void) {
        self.profile = profile
        self.recentColorsStore = recentColorsStore
        self.updateProfile = updateProfile

        // Forward the store's changes so a view observing only this model
        // (not the store separately) still redraws when the recent-colors
        // row changes.
        recentColorsStore.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
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

// MARK: - 字型 (FR-10.2, FR-10.3)

extension StyleTabModel {
    /// The ten fonts, in the order the font row lists them (same order as
    /// `OverlayFontID.allCases`, PRD 0.2 §4.1).
    var fontOptions: [OverlayFontID] { OverlayFontID.allCases }

    /// Selects `fontID` and persists.
    func selectFont(_ fontID: OverlayFontID) {
        guard fontID != profile.style.fontID else { return }
        mutate { $0.fontID = fontID }
    }
}

// MARK: - 顏色 (FR-10.4, FR-10.6, FR-10.7)

extension StyleTabModel {
    /// The first row of the text-color palette: the seven swatches (FR-10.4).
    /// The view appends its own rainbow `ColorPicker` entry after these, for
    /// eight items total.
    var textColorSwatches: [OverlayColor] { OverlayStyle.swatches }

    /// The first row of the outline-color palette: the first six swatches
    /// (FR-10.6). The view prepends its own "automatic" button (represented
    /// here by `outlineColor == nil`) and appends the rainbow `ColorPicker`,
    /// for eight items total.
    var outlineColorSwatches: [OverlayColor] { Array(OverlayStyle.swatches.prefix(6)) }

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

    /// Records a text color chosen with the rainbow `ColorPicker`: applies it
    /// and adds it to the shared recent-colors list (FR-10.7).
    func pickCustomTextColor(_ color: OverlayColor) {
        mutate { $0.textColor = color }
        recentColorsStore.add(color)
    }

    /// Records an outline color chosen with the rainbow `ColorPicker`,
    /// mirroring `pickCustomTextColor` (FR-10.7).
    func pickCustomOutlineColor(_ color: OverlayColor) {
        mutate { $0.outlineColor = color }
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
}
