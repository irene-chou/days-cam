import Combine
import Foundation
import UIKit

/// The app-wide owner of the overlay style editing that outlives any one
/// screen (#621): the font library, the overlay panel's tab models for the
/// export page (`makeStyleEditor(for:)`), and the one path a font is written
/// to a record through (`applyFont`, PRD 0.3 FR-5.18).
///
/// Lived in `CameraScreenModel` while the camera hosted the panel. The camera
/// no longer draws or bakes an overlay (PRD 2.0 FR-20), and its model is now
/// built each time the camera opens, so a font still downloading for a record
/// would be dropped with it; this object is built once by `DaysCamApp`.
@MainActor
final class StyleEditingCenter {
    /// Where each overlay font's availability, download and launch
    /// preparation come from (PRD 0.3). The real `FontLibrary` in the app;
    /// tests inject a fake.
    let fontLibrary: any FontShellControlling
    private let profileStore: ProfileStore
    private let calendar: Calendar
    private let calculator: DayCountCalculator
    private let renderer: TemplateRenderer
    /// Tells the user something when no font list is open to show it, e.g.
    /// "已套用" for a download that finished after the list was closed.
    /// Defaults to a VoiceOver announcement.
    private let notify: (String) -> Void

    /// "Profile → font" the user asked for that is still downloading; the
    /// download finishing writes it (PRD 0.3 FR-5.18, A-8). One entry per
    /// profile, the last request wins. Owned here, not by the font list, so
    /// closing the list changes nothing (FR-16.11).
    private var pendingFontApplications: [UUID: OverlayFontID] = [:]
    /// Every editor handed out, so a font that finishes downloading is
    /// announced in, and does not overtake a newer weight chosen in, their
    /// font list. Held weakly.
    private let styleEditors = NSHashTable<ProfileStyleEditor>.weakObjects()
    private var cancellables = Set<AnyCancellable>()

    init(profileStore: ProfileStore,
         fontLibrary: (any FontShellControlling)? = nil,
         calendar: Calendar = .autoupdatingCurrent,
         calculator: DayCountCalculator? = nil,
         renderer: TemplateRenderer = TemplateRenderer(),
         notify: @escaping (String) -> Void = { message in
             UIAccessibility.post(notification: .announcement, argument: message)
         }) {
        self.profileStore = profileStore
        self.fontLibrary = fontLibrary ?? InertFontLibrary()
        self.calendar = calendar
        self.calculator = calculator ?? DayCountCalculator(calendar: calendar)
        self.renderer = renderer
        self.notify = notify
        bindToProfileStore()
        bindToFontLibrary()
    }

    /// Every editor still on screen picks up what other writers changed in
    /// its record: a font written by `applyFont` (FR-5.18), the name switch
    /// written by the editor page (TASK-109).
    private func bindToProfileStore() {
        profileStore.$profiles
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] profiles in
                self?.styleEditors.allObjects.forEach { $0.applyExternalChanges(from: profiles) }
            }
            .store(in: &cancellables)
    }

    /// The overlay panel's tab models for `profileID` (the export page,
    /// #620). Fonts are applied through `applyFont`, and announced in the
    /// editor's font list while it is open. `nil` when the profile does not
    /// exist.
    func makeStyleEditor(for profileID: UUID) -> ProfileStyleEditor? {
        guard let profile = profileStore.profiles.first(where: { $0.id == profileID }) else { return nil }
        let editor = ProfileStyleEditor(
            profile: profile,
            profileStore: profileStore,
            fontLibrary: fontLibrary,
            calendar: calendar,
            calculator: calculator,
            renderer: renderer,
            applyFont: { [weak self] fontID, profileID in
                self?.applyFont(fontID, profileID: profileID)
            },
            allProfiles: { [weak profileStore] in profileStore?.profiles ?? [] },
            didWriteStyle: { [weak self] previous, profile in
                // A weight chosen in the font list writes font and weight
                // without `applyFont`; it is the newest font choice for this
                // profile, so a download still pending for it must not land
                // afterwards (#458).
                if let previous,
                   previous.style.fontID != profile.style.fontID
                    || previous.style.fontWeight != profile.style.fontWeight {
                    self?.pendingFontApplications[profile.id] = nil
                }
            })
        styleEditors.add(editor)
        return editor
    }

    /// Every style tab model still on screen.
    private var allStyleTabModels: [StyleTabModel] {
        styleEditors.allObjects.map(\.styleTabModel)
    }

    /// Settles the fonts on the device after launch, the last opened
    /// record's font first (PRD 0.3 FR-5.15). Call once, at launch.
    func prepareFontsAtLaunch() async {
        let style = profileStore.profiles.first { $0.id == profileStore.selectedProfileID }?.style
        await fontLibrary.prepareAtLaunch(priority: style?.fontID, weightID: style?.resolvedFontWeight.id)
    }

    /// The app went to the background: pending downloads stop and nobody is
    /// left waiting to be applied (PRD 0.3 FR-16.11).
    func sceneDidEnterBackground() {
        pendingFontApplications.removeAll()
        fontLibrary.cancelAllDownloads()
    }

    /// The one way a font is written to a profile (PRD 0.3 FR-5.18).
    ///
    /// An `available` font is written to `profileID` at once, and any earlier
    /// request still pending for that profile is dropped. Anything else is
    /// downloaded, and written to **that** profile once the download finishes
    /// (A-8), even if the list was closed by then; a later request for the
    /// same profile replaces this one, and a cancelled, failed or interrupted
    /// download drops it.
    func applyFont(_ fontID: OverlayFontID, profileID: UUID) {
        switch fontLibrary.state(for: fontID) {
        case .available:
            pendingFontApplications[profileID] = nil
            writeFont(fontID, to: profileID)
        case .preparing:
            pendingFontApplications[profileID] = fontID
            Task { [weak self] in
                await self?.fontLibrary.prepare(fontID)
                self?.fontLibraryDidChange()
            }
        case .notDownloaded, .failed, .downloading:
            pendingFontApplications[profileID] = fontID
            fontLibrary.download(fontID)
            fontLibraryDidChange()
        }
    }

    /// Writes `fontID` into the stored profile and keeps the style tabs'
    /// copies in step. A profile that no longer exists is skipped.
    ///
    /// - Returns: whether the profile now has `fontID`; `false` for a missing
    ///   profile or a failed save (which shows its own message).
    @discardableResult
    private func writeFont(_ fontID: OverlayFontID, to profileID: UUID) -> Bool {
        guard var latest = profileStore.profiles.first(where: { $0.id == profileID }) else { return false }
        if latest.style.fontID != fontID {
            latest.style.fontID = fontID
            do {
                // Waits for the disk: "applied" must not be announced for a
                // save that then fails (#492).
                try profileStore.updateAndWait(latest)
            } catch {
                post("無法儲存字型設定")
                return false
            }
        }
        syncStyleTabModelsWithStore()
        return true
    }

    /// Hands every style tab on screen the store's latest copy of its profile
    /// (FR-5.18).
    private func syncStyleTabModelsWithStore() {
        for styleTabModel in allStyleTabModels {
            guard let latest = profileStore.profiles.first(where: { $0.id == styleTabModel.profile.id }) else { continue }
            styleTabModel.applyExternalChanges(from: latest)
        }
    }

    /// Follows the library: finishes or drops pending applications.
    private func bindToFontLibrary() {
        fontLibrary.objectWillChange
            .sink { [weak self] _ in
                // `objectWillChange` fires before the change lands.
                DispatchQueue.main.async { self?.fontLibraryDidChange() }
            }
            .store(in: &cancellables)
        fontLibrary.weightDownloadDidFinish
            .sink { [weak self] _ in self?.fontLibraryDidChange() }
            .store(in: &cancellables)
    }

    /// Settles every pending application against the font's current state.
    func fontLibraryDidChange() {
        for (profileID, fontID) in pendingFontApplications {
            switch fontLibrary.state(for: fontID) {
            case .available:
                pendingFontApplications[profileID] = nil
                guard profileStore.profiles.contains(where: { $0.id == profileID }) else { continue }
                // The user has since picked a weight of another font for this
                // profile and it is still downloading: that is the newer
                // choice, so this one must not land first (#458).
                if allStyleTabModels.contains(where: { model in
                    model.fontList.profileID == profileID
                        && model.fontList.pendingWeight.map({ $0.fontID != fontID }) == true
                }) { continue }
                if writeFont(fontID, to: profileID) { post("已套用「\(fontID.displayName)」") }
            case .notDownloaded, .failed:
                pendingFontApplications[profileID] = nil
            case .preparing, .downloading:
                break
            }
        }
    }

    /// Shows `text` in the open font list (FR-16.6), or hands it to `notify`
    /// when none is open.
    private func post(_ text: String) {
        if let list = allStyleTabModels.lazy.compactMap(\.fontLibraryModel).first {
            list.post(text)
        } else {
            notify(text)
        }
    }
}

// MARK: - Font library seam (PRD 0.3, TASK-35)

/// What the style editing needs from the font library: availability and the
/// list's cancel/delete (`FontListControlling`), plus download, preparation
/// and the background cancel. `FontLibrary` conforms; tests inject a fake.
@MainActor
protocol FontShellControlling: FontListControlling {
    /// Fires with the exact font and weight each time a download finishes
    /// successfully; the state is already `.available` by then. The older
    /// per-font event only speaks for the default weight.
    var weightDownloadDidFinish: PassthroughSubject<FontDownloadID, Never> { get }
    /// Starts a download; `false` when none was started.
    @discardableResult func download(_ fontID: OverlayFontID) -> Bool
    /// Settles one `.preparing` font now (FR-5.16).
    func prepare(_ fontID: OverlayFontID) async
    /// Settles one exact face.
    func prepare(_ fontID: OverlayFontID, weightID: String?) async
    /// Settles the fonts on the device after launch (FR-5.15).
    func prepareAtLaunch(priority: OverlayFontID?) async
    /// Same, with the priority font's exact weight first.
    func prepareAtLaunch(priority: OverlayFontID?, weightID: String?) async
    /// Cancels every download in progress (FR-16.11).
    func cancelAllDownloads()
}

extension FontLibrary: FontShellControlling {}

/// The library used when none is injected: only PingFang is usable and
/// nothing downloads. Keeps previews and unrelated tests off the file system
/// and the network.
@MainActor
private final class InertFontLibrary: FontShellControlling {
    let objectWillChange = ObservableObjectPublisher()
    let weightDownloadDidFinish = PassthroughSubject<FontDownloadID, Never>()

    func state(for fontID: OverlayFontID) -> FontState {
        fontID == .pingFang ? .available : .notDownloaded
    }
    func cancel(_ fontID: OverlayFontID) {}
    func delete(_ fontID: OverlayFontID) -> Bool { false }
    func download(_ fontID: OverlayFontID) -> Bool { false }
    func prepare(_ fontID: OverlayFontID) async {}
    func prepare(_ fontID: OverlayFontID, weightID: String?) async {}
    func prepareAtLaunch(priority: OverlayFontID?) async {}
    func prepareAtLaunch(priority: OverlayFontID?, weightID: String?) async {}
    func cancelAllDownloads() {}
}
