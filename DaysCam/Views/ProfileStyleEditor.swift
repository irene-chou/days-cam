import Foundation

/// The overlay panel's tab models for one profile, wired to write back to the
/// store (PRD 0.2 FR-10–FR-12, 2.0 FR-19.3／FR-19.4).
///
/// Extracted from `CameraScreenModel` (#620) so the camera (until #621) and
/// the export page edit a record through the same models: the 樣式 tab, the
/// 內容 tab's switches and the 位置 row plus the drag adapter. Every tab
/// writes through its own `TabProfileWriter`, which merges only that tab's
/// changes onto the store's current record (#70).
///
/// Font *application* is not done here: `applyFont` is handed in, so a font
/// downloading for this profile still lands through the one shared path
/// (`CameraScreenModel.applyFont`, PRD 0.3 FR-5.18).
@MainActor
final class ProfileStyleEditor {
    /// The record these models edit.
    let profileID: UUID
    /// The 樣式 tab's model (PRD 0.2 FR-10).
    let styleTabModel: StyleTabModel
    /// The 內容 tab's model (PRD 0.2 FR-11).
    let formatTabModel: FormatTabModel
    /// The 位置 row's model, also what a drag on the overlay writes to (FR-12).
    let positionTabModel: PositionTabModel
    /// Bridges overlay drags to `positionTabModel` (`OverlayDragHandling`).
    let dragAdapter: PositionDragAdapter

    /// The content tab's writer, kept so its baseline can follow the store
    /// when the tab takes over an external change (TASK-109).
    private let formatWriter: TabProfileWriter

    /// Builds the three tab models for `profile`.
    ///
    /// - Parameters:
    ///   - applyFont: The one way a font is written to a profile (FR-5.18).
    ///   - allProfiles: Every profile, for the font list's usage count.
    ///   - didWriteStyle: Called after each successful style write with the
    ///     store's record from just before it and the tab's new copy.
    init(profile: CameraProfile,
         profileStore: ProfileStore,
         fontLibrary: any FontShellControlling,
         calendar: Calendar,
         calculator: DayCountCalculator,
         renderer: TemplateRenderer,
         applyFont: @escaping (OverlayFontID, UUID) -> Void,
         allProfiles: @escaping () -> [CameraProfile],
         didWriteStyle: @escaping (_ previous: CameraProfile?, _ updated: CameraProfile) -> Void) {
        profileID = profile.id

        let styleWriter = TabProfileWriter(baseline: profile, profileStore: profileStore)
        styleTabModel = StyleTabModel(
            profile: profile,
            fontLibrary: fontLibrary,
            applyFont: applyFont,
            allProfiles: allProfiles,
            updateProfile: { [weak profileStore] updated in
                let previous = profileStore?.profiles.first { $0.id == updated.id }
                try styleWriter.write(updated)
                didWriteStyle(previous, updated)
            })

        formatWriter = TabProfileWriter(baseline: profile, profileStore: profileStore)
        let displaySettings = DisplaySettingsModel(profile: profile,
                                                   calendar: calendar,
                                                   calculator: calculator,
                                                   renderer: renderer,
                                                   updateProfile: formatWriter.write)
        formatTabModel = FormatTabModel(displaySettings: displaySettings)

        let positionWriter = TabProfileWriter(baseline: profile, profileStore: profileStore)
        positionTabModel = PositionTabModel(profile: profile, updateProfile: positionWriter.write)
        dragAdapter = PositionDragAdapter(positionTabModel: positionTabModel)
    }

    /// Hands the tabs the fields other writers changed in the store's latest
    /// copy of this profile: the font for the style tab (FR-5.18), the name
    /// switch for the content tab (TASK-109). Another profile is ignored.
    func applyExternalChanges(from profiles: [CameraProfile]) {
        guard let latest = profiles.first(where: { $0.id == profileID }) else { return }
        styleTabModel.applyExternalChanges(from: latest)
        formatWriter.adopt(latest)
        formatTabModel.displaySettings.applyExternalChanges(from: latest)
    }
}
