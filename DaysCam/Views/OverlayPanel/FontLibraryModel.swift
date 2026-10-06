import Combine
import Foundation

// MARK: - What the font UI needs from the font library

/// The part of TASK-33's `FontLibrary` the font grid and the font list use
/// (PRD 0.3 FR-10.2′, FR-16): the availability of every font, plus cancelling
/// a download and deleting an open-source font.
///
/// Starting a download is deliberately not here: applying a font goes through
/// the injected `applyFont` closure, which is the one place that downloads
/// and remembers what to apply when the download finishes (FR-5.18, TASK-35).
///
/// `FontLibrary` conforms as is: it already has `objectWillChange`, `cancel`
/// and a `Bool`-returning `delete`.
@MainActor
protocol FontListControlling: FontAvailabilityProviding {
    /// Fires before any font's state changes; the models re-publish it.
    var objectWillChange: ObservableObjectPublisher { get }
    /// Cancels a download in progress (FR-16.7).
    func cancel(_ fontID: OverlayFontID)
    /// Removes a downloaded open-source font; `false` when it could not be
    /// removed (FR-16.12).
    func delete(_ fontID: OverlayFontID) -> Bool
}

/// A library in which only PingFang is usable and nothing can be downloaded.
///
/// The default for `StyleTabModel` until TASK-35 injects the real
/// `FontLibrary`; also the stand-in the `#Preview`s configure with `states`.
@MainActor
final class StaticFontLibrary: FontListControlling {
    let objectWillChange = ObservableObjectPublisher()
    /// The state of each font; fonts not listed are `.notDownloaded`.
    var states: [OverlayFontID: FontState]

    init(states: [OverlayFontID: FontState] = [:]) {
        self.states = states
    }

    func state(for fontID: OverlayFontID) -> FontState {
        fontID == .pingFang ? .available : (states[fontID] ?? .notDownloaded)
    }

    func cancel(_ fontID: OverlayFontID) {}

    func delete(_ fontID: OverlayFontID) -> Bool { false }
}

// MARK: - Shared wording

/// Text the font grid and list derive from a `FontState` (PRD 0.3 FR-10.2′.4,
/// FR-16.5).
enum FontStateText {
    /// "38%" for a progress of 0.38.
    static func percent(_ progress: Double) -> String {
        let clamped = min(max(progress, 0), 1)
        return "\(Int((clamped * 100).rounded()))%"
    }

    /// The grid cell's caption (FR-10.2′.4).
    static let needsRedownload = "需重新下載"
    /// FR-16.10 for a download that failed without a network.
    static let offlineMessage = "沒有網路，連上後再點一次"
    /// FR-16.7.
    static let cancelledMessage = "已取消下載"

    /// FR-16.10 for any other failure.
    static func failedMessage(name: String) -> String {
        "「\(name)」下載失敗，點一下重試"
    }
}

// MARK: - FontLibraryModel

/// Drives the full-screen font list (PRD 0.3 FR-16, design D-6 option C):
/// the nine sections, each row's state, tapping, the ⋯ delete menu and the
/// messages shown at the top.
///
/// It never writes `fontID` itself and does not start downloads or wait for
/// them to finish: picking a font calls the injected `applyFont` (TASK-35),
/// which keeps working after this list is closed (FR-16.11).
@MainActor
final class FontLibraryModel: ObservableObject {
    /// What a row shows on its right (FR-16.5).
    enum Trailing: Equatable {
        /// `available` PingFang or system font: nothing.
        case none
        /// `notDownloaded`: the size, e.g. "43.7 MB", with a download icon.
        case download(sizeText: String)
        /// `downloading`: the percentage with a progress ring.
        case downloading(percentText: String, progress: Double)
        /// `preparing`: a progress ring without text.
        case preparing
        /// `failed`: "重試" with a warning icon.
        case retry
        /// `available` open-source font: the ⋯ button.
        case menu
    }

    /// One font in the list (FR-16.3).
    struct Row: Identifiable, Equatable {
        let fontID: OverlayFontID
        let name: String
        /// Whether it is the current profile's font (the leading checkmark).
        let isCurrent: Bool
        let trailing: Trailing
        var id: OverlayFontID { fontID }

        /// What VoiceOver reads, as the design's `aria-label` does.
        var accessibilityLabel: String {
            switch trailing {
            case .download(let sizeText): return "\(name)，未下載，\(sizeText)"
            case .downloading: return "\(name)，下載中"
            case .preparing: return "\(name)，準備中"
            case .retry: return "\(name)，下載失敗"
            case .none, .menu: return name
            }
        }
    }

    /// One headed section of the list (FR-16.2).
    struct Section: Identifiable, Equatable {
        let section: FontSection
        let rows: [Row]
        var id: FontSection { section }
        var title: String { section.title }
    }

    /// The ⋯ menu of an open-source font (FR-16.12).
    struct DeletePrompt: Identifiable, Equatable {
        let fontID: OverlayFontID
        /// "<名稱>　<大小>"
        let title: String
        /// How many profiles use it, and what happens to them.
        let usage: String
        var id: OverlayFontID { fontID }
    }

    /// A transient message; `id` lets the same text show twice in a row.
    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let text: String
    }

    static let licenseRowTitle = "字型授權"
    static let deleteFailedMessage = "無法刪除，請再試一次"

    /// The profile fonts are applied to (the one the panel is editing).
    private(set) var profileID: UUID
    /// The font to scroll to when the list opens (FR-10.2′.4); `nil` for none.
    let scrollTarget: OverlayFontID?
    @Published private(set) var currentFontID: OverlayFontID
    @Published private(set) var toast: Toast?
    @Published var deletePrompt: DeletePrompt?

    private let library: any FontListControlling
    private let profiles: () -> [CameraProfile]
    private let applyFont: (OverlayFontID, UUID) -> Void
    private let replaceFont: (OverlayFontID, OverlayFontID) throws -> [UUID]
    private var knownStates: [OverlayFontID: FontState]
    private var cancellable: AnyCancellable?

    /// - Parameters:
    ///   - profiles: every profile, to count who uses a font before deleting.
    ///   - applyFont: the only way a font gets written to a profile
    ///     (`applyFont(fontID, profileID)`, PRD FR-5.18).
    ///   - replaceFont: switches every profile using the first font to the
    ///     second and returns the changed profile IDs
    ///     (`ProfileStore.replaceFont`).
    init(profileID: UUID,
         currentFontID: OverlayFontID,
         library: any FontListControlling,
         scrollTarget: OverlayFontID? = nil,
         profiles: @escaping () -> [CameraProfile],
         applyFont: @escaping (OverlayFontID, UUID) -> Void,
         replaceFont: @escaping (OverlayFontID, OverlayFontID) throws -> [UUID]) {
        self.profileID = profileID
        self.currentFontID = currentFontID
        self.library = library
        self.scrollTarget = scrollTarget
        self.profiles = profiles
        self.applyFont = applyFont
        self.replaceFont = replaceFont
        self.knownStates = Dictionary(uniqueKeysWithValues: OverlayFontID.allCases.map { ($0, library.state(for: $0)) })

        cancellable = library.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
                // The state has not changed yet when this fires.
                DispatchQueue.main.async { [weak self] in self?.libraryDidChange() }
            }
    }

    // MARK: Sections

    /// The sections in §4.1 order, every font in each (FR-16.2).
    var sections: [Section] {
        FontSection.allCases.map { section in
            Section(section: section,
                    rows: FontCatalog.entries.filter { $0.section == section }.map(row(for:)))
        }
    }

    private func row(for entry: FontCatalogEntry) -> Row {
        Row(fontID: entry.fontID,
            name: entry.displayName,
            isCurrent: entry.fontID == currentFontID,
            trailing: trailing(for: entry))
    }

    private func trailing(for entry: FontCatalogEntry) -> Trailing {
        switch library.state(for: entry.fontID) {
        case .available:
            return entry.source == .openSource ? .menu : .none
        case .notDownloaded:
            return .download(sizeText: entry.downloadSizeText ?? "")
        case .preparing:
            return .preparing
        case .downloading(let progress):
            return .downloading(percentText: FontStateText.percent(progress), progress: progress)
        case .failed:
            return .retry
        }
    }

    // MARK: Following the profile

    /// Called when the panel's profile copy changes (a font was applied, or a
    /// deleted font was replaced), so the checkmark follows.
    func update(profileID: UUID, currentFontID: OverlayFontID) {
        self.profileID = profileID
        if self.currentFontID != currentFontID {
            self.currentFontID = currentFontID
        }
    }

    // MARK: Tapping (FR-16.6 to FR-16.8)

    /// A tap on a row. Not-downloaded, failed and available fonts go to
    /// `applyFont`; a download in progress is cancelled; a font that is still
    /// preparing does nothing.
    func didTapRow(_ fontID: OverlayFontID) {
        switch library.state(for: fontID) {
        case .notDownloaded, .failed, .available:
            applyFont(fontID, profileID)
        case .downloading:
            library.cancel(fontID)
            post(FontStateText.cancelledMessage)
        case .preparing:
            break
        }
    }

    // MARK: Delete (FR-16.12)

    /// Opens the ⋯ menu of `fontID`; only open-source fonts have one.
    func requestDeletion(of fontID: OverlayFontID) {
        let entry = FontCatalog.entry(for: fontID)
        guard entry.source == .openSource else { return }
        deletePrompt = DeletePrompt(fontID: fontID,
                                    title: "\(entry.displayName)　\(entry.downloadSizeText ?? "")",
                                    usage: usageText(of: fontID))
    }

    private func usageText(of fontID: OverlayFontID) -> String {
        let users = profiles().filter { $0.style.fontID == fontID }
        switch users.count {
        case 0: return "沒有設定檔在用這套字型"
        case 1: return "「\(users[0].name)」正在使用，刪除後改回蘋方"
        default: return "「\(users[0].name)」等 \(users.count) 個設定檔正在使用，刪除後改回蘋方"
        }
    }

    /// Confirms the open menu: first moves the profiles using the font to
    /// PingFang and saves, only then deletes the font (FR-16.12).
    func confirmDeletion() {
        guard let prompt = deletePrompt else { return }
        deletePrompt = nil
        let entry = FontCatalog.entry(for: prompt.fontID)
        do {
            let changed = try replaceFont(prompt.fontID, .pingFang)
            if changed.contains(profileID), currentFontID == prompt.fontID {
                currentFontID = .pingFang
            }
        } catch {
            post(Self.deleteFailedMessage)
            return
        }
        guard library.delete(prompt.fontID) else {
            post(Self.deleteFailedMessage)
            return
        }
        post("已刪除「\(entry.displayName)」，釋放 \(entry.downloadSizeText ?? "")")
    }

    /// Closes the open menu without deleting.
    func cancelDeletion() {
        deletePrompt = nil
    }

    // MARK: Messages (FR-16.10)

    /// Shows `text` at the top of the list. TASK-35 uses this for "已套用".
    func post(_ text: String) {
        toast = Toast(text: text)
    }

    /// Clears the message `toast`, if it is still the one showing.
    func dismissToast(_ toast: Toast) {
        if self.toast == toast { self.toast = nil }
    }

    /// Compares the library with what was last seen and reports a download
    /// that has just failed (FR-16.10). Called after every library change.
    func libraryDidChange() {
        for fontID in OverlayFontID.allCases {
            let old = knownStates[fontID]
            let new = library.state(for: fontID)
            knownStates[fontID] = new
            guard case .failed(let reason) = new, old != new else { continue }
            // Only a download the user started: a font that failed while
            // preparing at launch (FR-5.15) is not announced here.
            switch old {
            case .notDownloaded, .downloading, .failed:
                post(reason == .noNetwork
                     ? FontStateText.offlineMessage
                     : FontStateText.failedMessage(name: fontID.displayName))
            default:
                break
            }
        }
    }
}

/// TASK-33's library already provides everything the font UI needs:
/// `objectWillChange`, `cancel` and a `Bool`-returning `delete`.
extension FontLibrary: FontListControlling {}
