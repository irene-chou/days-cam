import Combine
import Foundation

// MARK: - What the font UI needs from the font library

/// The part of TASK-33's `FontLibrary` the font list uses (PRD 0.3 FR-16,
/// TASK-56): the availability of every font, plus cancelling a download and
/// deleting an open-source font. The list never cancels a download (TASK-56);
/// `cancel` stays for `FontLibrary`'s own callers.
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

/// Messages the font list shows (PRD 0.3 FR-16.10; TASK-56 shows no state
/// text in the cells themselves).
enum FontStateText {
    /// "38%" for a progress of 0.38.
    static func percent(_ progress: Double) -> String {
        let clamped = min(max(progress, 0), 1)
        return "\(Int((clamped * 100).rounded()))%"
    }

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

/// Drives the font list inside the style tab's 字型 page (TASK-56): which fonts
/// sit in which section, each cell's state icon, taps, the long-press delete
/// menu and the messages shown at the top.
///
/// It never writes `fontID` itself and does not start downloads or wait for
/// them to finish: picking a font calls the injected `applyFont`
/// (`CameraScreenModel.applyFont`), which downloads, remembers what to apply
/// when the download finishes (FR-5.18) and drops the request when the user
/// picks another font meanwhile.
@MainActor
final class FontLibraryModel: ObservableObject {
    /// The icon in a cell's top-right corner; the list shows no state text.
    enum Status: Equatable {
        /// Nothing: an available font, or a built-in one.
        case none
        /// `notDownloaded`: a gray download arrow.
        case notDownloaded
        /// `downloading`: a progress ring.
        case downloading(progress: Double)
        /// `preparing`: a spinner.
        case preparing
        /// `failed`: a red retry icon.
        case failed
        /// Just finished downloading: a check for about 1.5 seconds.
        case justCompleted
    }

    /// One font in the list.
    struct Cell: Identifiable, Equatable {
        let fontID: OverlayFontID
        let name: String
        let state: FontState
        /// Whether it is the current profile's font.
        let isSelected: Bool
        let status: Status
        /// Whether the long-press menu offers "刪除字型": a downloaded
        /// open-source font (PingFang and system fonts cannot be deleted).
        let canDelete: Bool
        var id: OverlayFontID { fontID }

        /// Whether the name is drawn with the font itself; otherwise with its
        /// preview image.
        var usesRealFont: Bool { state.isAvailable }

        /// What VoiceOver reads; the percentage is spoken, never shown.
        var accessibilityLabel: String {
            switch status {
            case .notDownloaded: return "\(name)，未下載，點兩下下載"
            case .downloading(let progress): return "\(name)，下載中，\(FontStateText.percent(progress))"
            case .preparing: return "\(name)，準備中"
            case .failed: return "\(name)，下載失敗，點兩下重試"
            case .justCompleted: return "\(name)，已下載"
            case .none: return name
            }
        }
    }

    /// One section of the list: the downloaded fonts (no title) first, then
    /// one per category that still has fonts to download.
    struct Section: Identifiable, Equatable {
        /// `nil` for the downloaded section.
        let category: FontSection?
        let cells: [Cell]
        var id: String { category?.rawValue ?? "downloaded" }
        var title: String? { category?.title }
    }

    /// The long-press "刪除字型" confirmation.
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
    /// How long the check of a just-finished download stays.
    static let completionCheckDuration: TimeInterval = 1.5

    /// The profile fonts are applied to (the one the panel is editing).
    private(set) var profileID: UUID
    @Published private(set) var currentFontID: OverlayFontID
    @Published private(set) var toast: Toast?
    @Published var deletePrompt: DeletePrompt?
    /// Fonts that finished downloading a moment ago and still show the check.
    @Published private(set) var completedFonts: Set<OverlayFontID> = []
    /// Whether the list is on screen. `CameraScreenModel` announces "已套用"
    /// in the list while it is, and on the camera screen otherwise.
    private(set) var isVisible = false

    private let library: any FontListControlling
    private let profiles: () -> [CameraProfile]
    private let applyFont: (OverlayFontID, UUID) -> Void
    private var knownStates: [OverlayFontID: FontState]
    /// Fonts that went from `downloading` to `preparing` and are not yet
    /// available, so the check shows when they are.
    private var finishingFonts: Set<OverlayFontID> = []
    /// The fonts the downloaded section holds. Taken when the list appears
    /// and not moved while it is on screen, so a font that finishes
    /// downloading stays where it was until the next time.
    private var downloadedLayout: Set<OverlayFontID> = []
    private var cancellable: AnyCancellable?

    /// - Parameters:
    ///   - profiles: every profile, to count who uses a font before deleting.
    ///   - applyFont: the only way a font gets written to a profile
    ///     (`applyFont(fontID, profileID)`, PRD FR-5.18).
    init(profileID: UUID,
         currentFontID: OverlayFontID,
         library: any FontListControlling,
         profiles: @escaping () -> [CameraProfile],
         applyFont: @escaping (OverlayFontID, UUID) -> Void) {
        self.profileID = profileID
        self.currentFontID = currentFontID
        self.library = library
        self.profiles = profiles
        self.applyFont = applyFont
        self.knownStates = Dictionary(uniqueKeysWithValues: OverlayFontID.allCases.map { ($0, library.state(for: $0)) })
        refreshLayout()

        cancellable = library.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
                // The state has not changed yet when this fires.
                DispatchQueue.main.async { [weak self] in self?.libraryDidChange() }
            }
    }

    /// Font availability for drawing the names with the fonts themselves.
    var availability: any FontAvailabilityProviding { library }

    // MARK: Sections

    /// Re-sorts the list: every downloaded font, and the current one, go to
    /// the downloaded section. Called when the list appears, i.e. when the
    /// panel opens or the 字型 page is selected again.
    func refreshLayout() {
        downloadedLayout = Set(OverlayFontID.allCases.filter { library.state(for: $0).isAvailable })
        downloadedLayout.insert(currentFontID)
        objectWillChange.send()
    }

    /// The downloaded section first (PingFang, then the catalog order), then
    /// the fonts still to download by category; a category without any is
    /// left out, title included.
    var sections: [Section] {
        let entries = FontCatalog.entries
        var result: [Section] = []
        let downloaded = entries.filter { downloadedLayout.contains($0.fontID) }.map(cell(for:))
        if !downloaded.isEmpty { result.append(Section(category: nil, cells: downloaded)) }
        for category in FontSection.allCases {
            let cells = entries
                .filter { $0.section == category && !downloadedLayout.contains($0.fontID) }
                .map(cell(for:))
            if !cells.isEmpty { result.append(Section(category: category, cells: cells)) }
        }
        return result
    }

    private func cell(for entry: FontCatalogEntry) -> Cell {
        let state = library.state(for: entry.fontID)
        return Cell(fontID: entry.fontID,
                    name: entry.displayName,
                    state: state,
                    isSelected: entry.fontID == currentFontID,
                    status: status(of: entry.fontID, state: state),
                    canDelete: state.isAvailable && entry.source == .openSource)
    }

    private func status(of fontID: OverlayFontID, state: FontState) -> Status {
        switch state {
        case .available: return completedFonts.contains(fontID) ? .justCompleted : .none
        case .notDownloaded: return .notDownloaded
        case .preparing: return .preparing
        case .downloading(let progress): return .downloading(progress: progress)
        case .failed: return .failed
        }
    }

    // MARK: Visibility and following the profile

    /// The list came on screen: re-sorts it and starts announcing in it.
    func listDidAppear() {
        isVisible = true
        knownStates = Dictionary(uniqueKeysWithValues: OverlayFontID.allCases.map { ($0, library.state(for: $0)) })
        refreshLayout()
    }

    /// The list left the screen.
    func listDidDisappear() {
        isVisible = false
    }

    /// Called when the panel's profile copy changes (a font was applied), so
    /// the selection follows.
    func update(profileID: UUID, currentFontID: OverlayFontID) {
        self.profileID = profileID
        if self.currentFontID != currentFontID {
            self.currentFontID = currentFontID
        }
    }

    // MARK: Tapping

    /// A tap on a cell. Available, not-downloaded and failed fonts go to
    /// `applyFont` (which downloads when needed); a download in progress is
    /// never cancelled, and a font still preparing does nothing.
    func didTap(_ fontID: OverlayFontID) {
        switch library.state(for: fontID) {
        case .available, .notDownloaded, .failed:
            applyFont(fontID, profileID)
        case .downloading, .preparing:
            break
        }
    }

    // MARK: Delete

    /// Opens the delete confirmation of `fontID`; only a downloaded
    /// open-source font has one.
    func requestDeletion(of fontID: OverlayFontID) {
        let entry = FontCatalog.entry(for: fontID)
        guard entry.source == .openSource, library.state(for: fontID).isAvailable else { return }
        deletePrompt = DeletePrompt(fontID: fontID,
                                    title: "\(entry.displayName)　\(entry.downloadSizeText ?? "")",
                                    usage: usageText(of: fontID))
    }

    private func usageText(of fontID: OverlayFontID) -> String {
        let users = profiles().filter { $0.style.fontID == fontID }
        switch users.count {
        case 0: return "沒有設定檔在用這套字型"
        case 1: return "「\(users[0].name)」正在使用，刪除後暫以蘋方顯示"
        default: return "「\(users[0].name)」等 \(users.count) 個設定檔正在使用，刪除後暫以蘋方顯示"
        }
    }

    /// Confirms the open prompt: deletes the font file. A profile using the
    /// font keeps it selected and draws with PingFang until it is downloaded
    /// again (TASK-56 56.13; FR-5.14 already resolves an unavailable font to
    /// PingFang). The cell moves to its category with a download arrow,
    /// unless it is the current font, which stays in the downloaded section.
    func confirmDeletion() {
        guard let prompt = deletePrompt else { return }
        deletePrompt = nil
        let entry = FontCatalog.entry(for: prompt.fontID)
        guard library.delete(prompt.fontID) else {
            post(Self.deleteFailedMessage)
            return
        }
        if prompt.fontID != currentFontID {
            downloadedLayout.remove(prompt.fontID)
        }
        completedFonts.remove(prompt.fontID)
        post("已刪除「\(entry.displayName)」，釋放 \(entry.downloadSizeText ?? "")")
    }

    /// Closes the open prompt without deleting.
    func cancelDeletion() {
        deletePrompt = nil
    }

    // MARK: Messages

    /// Shows `text` at the top of the page. `CameraScreenModel` uses this for
    /// "已套用".
    func post(_ text: String) {
        toast = Toast(text: text)
    }

    /// Clears the message `toast`, if it is still the one showing.
    func dismissToast(_ toast: Toast) {
        if self.toast == toast { self.toast = nil }
    }

    /// Compares the library with what was last seen: reports a download that
    /// has just failed (FR-16.10) and starts the check of one that has just
    /// finished. Called after every library change; does nothing while the list
    /// is off screen, so a closed panel never reads font availability (the
    /// bake path relies on no reads after the shutter).
    func libraryDidChange() {
        guard isVisible else { return }
        for fontID in OverlayFontID.allCases {
            let old = knownStates[fontID]
            let new = library.state(for: fontID)
            knownStates[fontID] = new
            guard old != new else { continue }
            noteCompletion(of: fontID, from: old, to: new)
            guard case .failed(let reason) = new else { continue }
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

    private func noteCompletion(of fontID: OverlayFontID, from old: FontState?, to new: FontState) {
        switch new {
        case .downloading:
            finishingFonts.remove(fontID)
        case .preparing:
            if case .downloading? = old { finishingFonts.insert(fontID) }
        case .available:
            var finished = finishingFonts.remove(fontID) != nil
            if case .downloading? = old { finished = true }
            guard finished else { return }
            completedFonts.insert(fontID)
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Self.completionCheckDuration * 1_000_000_000))
                self?.expireCompletionCheck(of: fontID)
            }
        case .notDownloaded, .failed:
            finishingFonts.remove(fontID)
        }
    }

    /// Removes the check of `fontID`; the cell turns into a plain downloaded
    /// one but stays where it is.
    func expireCompletionCheck(of fontID: OverlayFontID) {
        completedFonts.remove(fontID)
    }
}

/// TASK-33's library already provides everything the font UI needs:
/// `objectWillChange`, `cancel` and a `Bool`-returning `delete`.
extension FontLibrary: FontListControlling {}
