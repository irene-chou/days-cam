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
    /// Starts downloading one exact face (TASK-89); `false` when none was
    /// started. The default does nothing.
    @discardableResult
    func download(_ fontID: OverlayFontID, weightID: String?) -> Bool
    /// Fires with the exact face only after it is verified and usable
    /// (TASK-89). The default never fires.
    var weightDownloadDidFinish: PassthroughSubject<FontDownloadID, Never> { get }
}

extension FontListControlling {
    @discardableResult
    func download(_ fontID: OverlayFontID, weightID: String?) -> Bool { false }
    var weightDownloadDidFinish: PassthroughSubject<FontDownloadID, Never> { PassthroughSubject() }
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
    /// The state of a non-default face; faces not listed are `.notDownloaded`
    /// (PingFang's are always available).
    var weightStates: [FontDownloadID: FontState]

    init(states: [OverlayFontID: FontState] = [:],
         weightStates: [FontDownloadID: FontState] = [:]) {
        self.states = states
        self.weightStates = weightStates
    }

    func state(for fontID: OverlayFontID, weightID: String?) -> FontState {
        let entry = FontCatalog.entry(for: fontID)
        let weight = entry.weight(for: weightID)
        if entry.source == .builtIn || weight.id == entry.defaultWeight.id { return state(for: fontID) }
        return weightStates[FontDownloadID(fontID: fontID, weightID: weight.id)] ?? .notDownloaded
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

    /// "<字型>　<字重>" as a weight is named in messages.
    static func weightName(fontID: OverlayFontID, weightID: String) -> String {
        let entry = FontCatalog.entry(for: fontID)
        return "\(entry.displayName)　\(entry.weight(for: weightID).displayName)"
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
        /// The weight buttons of a multi-weight font (TASK-89, design A):
        /// filled for the selected font and for the expanded one; empty for
        /// every other row and for single-weight fonts. Shown only while
        /// `isExpanded` (TASK-112, TASK-115).
        let weights: [WeightCell]
        /// How many faces the font has.
        let weightCount: Int
        /// The weight the row's name is drawn in (the profile's, when selected).
        let nameWeightID: String
        /// The stored weight's name, shown on the selected multi-weight row
        /// (TASK-112, #437); `nil` for every other row.
        let currentWeightName: String?
        /// Whether the row's weight buttons are showing (TASK-112, TASK-115):
        /// any multi-weight font can expand, selected or not, and every row
        /// starts collapsed. At most one row is expanded at a time.
        let isExpanded: Bool
        /// A weight download in progress for this row while it is collapsed
        /// (TASK-112, 112.8): the ring beside the weight name.
        let pendingWeightStatus: Status?
        var id: OverlayFontID { fontID }
        /// Whether the row can expand: any font with several weights
        /// (TASK-115); it then shows the trailing chevron.
        var canExpand: Bool { weightCount > 1 }
        /// The VoiceOver custom action that replaces the chevron (115.9).
        var expandActionName: String { isExpanded ? "收合字重" : "展開字重" }

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
        /// VoiceOver value of the selected multi-weight row: the current
        /// weight (TASK-112, 112.9). An unselected row has none (TASK-115).
        var accessibilityValue: String? { canExpand ? currentWeightName : nil }
        /// VoiceOver hint of the selected multi-weight row (112.9).
        var accessibilityHint: String? {
            guard canExpand, isSelected else { return nil }
            return isExpanded ? "點兩下收合字重" : "點兩下展開字重"
        }
    }
    /// One weight button of the expanded card.
    struct WeightCell: Identifiable, Equatable {
        let fontID: OverlayFontID
        let weightID: String
        let name: String
        /// Whether it is the profile's weight (the yellow frame).
        let isSelected: Bool
        /// `.none` when usable; otherwise the download icon, ring or failure.
        let status: Status
        var id: String { weightID }

        /// What VoiceOver reads for the button.
        var accessibilityLabel: String {
            switch status {
            case .none, .justCompleted: return name
            case .notDownloaded: return "\(name)，未下載，點兩下下載"
            case .downloading(let progress): return "\(name)，下載中，\(FontStateText.percent(progress))"
            case .preparing: return "\(name)，準備中"
            case .failed: return "\(name)，下載失敗，點兩下重試"
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
    static let weightSaveFailedMessage = "無法儲存字重設定"
    static let deleteFailedMessage = "無法刪除，請再試一次"
    /// How long the check of a just-finished download stays.
    static let completionCheckDuration: TimeInterval = 1.5

    /// The profile fonts are applied to (the one the panel is editing).
    private(set) var profileID: UUID
    @Published private(set) var currentFontID: OverlayFontID
    /// The profile's stored weight ID; `nil` or unknown means the default face.
    @Published private(set) var currentWeightID: String?
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
    /// Writes an already usable weight to the profile and returns whether it
    /// was saved; never called for a face that is still being downloaded.
    var applyWeight: (OverlayFontID, String) -> Bool
    /// Writes another font together with one of its usable weights in a
    /// single save (TASK-115); returns whether it was saved.
    var applyFontWithWeight: (OverlayFontID, String) -> Bool
    private var knownStates: [OverlayFontID: FontState]
    /// States of the non-default faces of the current font, as last seen.
    private var knownWeightStates: [FontDownloadID: FontState] = [:]
    /// The face (of the current font, or of another one, TASK-115) the user
    /// chose that is still downloading; applied, with its font, only when
    /// `weightDownloadDidFinish` reports exactly this face (TASK-89).
    private(set) var pendingWeight: FontDownloadID?
    /// The multi-weight font whose weight buttons are showing, at most one
    /// (TASK-115, replacing TASK-112's single flag). In memory only: reset
    /// whenever the list appears, and when another font becomes the selected
    /// one; toggled by the chevron or by tapping the selected row.
    @Published private(set) var expandedFontID: OverlayFontID?
    private var weightCancellable: AnyCancellable?
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
    ///   - currentWeightID: the profile's stored weight ID.
    ///   - applyWeight: writes an already usable weight to the profile
    ///     (`applyWeight(fontID, weightID)`); never called for a face that
    ///     is still being downloaded.
    ///   - applyFontWithWeight: writes a font and one usable weight of it
    ///     with one save (TASK-115); never called for a face still downloading.
    init(profileID: UUID,
         currentFontID: OverlayFontID,
         currentWeightID: String? = nil,
         library: any FontListControlling,
         profiles: @escaping () -> [CameraProfile],
         applyFont: @escaping (OverlayFontID, UUID) -> Void,
         applyWeight: @escaping (OverlayFontID, String) -> Bool = { _, _ in true },
         applyFontWithWeight: @escaping (OverlayFontID, String) -> Bool = { _, _ in true }) {
        self.profileID = profileID
        self.currentFontID = currentFontID
        self.currentWeightID = currentWeightID
        self.library = library
        self.profiles = profiles
        self.applyFont = applyFont
        self.applyWeight = applyWeight
        self.applyFontWithWeight = applyFontWithWeight
        self.knownStates = Dictionary(uniqueKeysWithValues: OverlayFontID.allCases.map { ($0, library.state(for: $0)) })
        refreshLayout()

        cancellable = library.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
                // The state has not changed yet when this fires.
                DispatchQueue.main.async { [weak self] in self?.libraryDidChange() }
            }
        weightCancellable = library.weightDownloadDidFinish
            .sink { [weak self] unit in self?.weightDownloadDidFinish(unit) }
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

    /// The row title: the full face name, except that a font with several
    /// weights shows the family name alone, since the weight is read from the
    /// buttons below it once the row is expanded (TASK-89, design A; the
    /// collapsed "N 種字重" text was dropped by TASK-111, #425).
    static func listName(of entry: FontCatalogEntry) -> String {
        guard entry.weights.count > 1 else { return entry.fullName }
        switch entry.fontID {
        case .pingFang: return "蘋方-繁"
        case .notoSerifTC: return "Noto Serif TC"
        case .hiraginoSans: return "冬青黑體繁體中文"
        case .songti: return "宋體-繁"
        case .kaiti: return "楷體-繁"
        case .yuanti: return "圓體-繁"
        case .hannotate: return "手札體-繁"
        default: return entry.displayName
        }
    }

    private func cell(for entry: FontCatalogEntry) -> Cell {
        let isSelected = entry.fontID == currentFontID
        let selectedWeight = entry.weight(for: isSelected ? currentWeightID : nil)
        // The selected font is drawn in its stored face, which may be usable
        // even when the default face is not (TASK-115).
        let state = isSelected ? library.state(for: entry.fontID, weightID: selectedWeight.id)
                               : library.state(for: entry.fontID)
        let isMultiWeight = entry.weights.count > 1
        let isMultiWeightSelected = isSelected && isMultiWeight
        let isExpanded = isMultiWeight && expandedFontID == entry.fontID
        let pendingStatus: Status? = {
            guard isMultiWeight, !isExpanded, let unit = pendingWeight, unit.fontID == entry.fontID else { return nil }
            let status = weightStatus(library.state(for: unit.fontID, weightID: unit.weightID))
            if case .downloading = status { return status }
            if case .preparing = status { return status }
            return nil
        }()
        return Cell(fontID: entry.fontID,
                    name: Self.listName(of: entry),
                    state: state,
                    isSelected: isSelected,
                    status: status(of: entry.fontID, state: state),
                    canDelete: entry.source == .openSource && hasDownloadedFace(entry),
                    weights: isMultiWeightSelected || isExpanded
                        ? weightCells(of: entry, selected: isSelected ? selectedWeight : nil) : [],
                    weightCount: entry.weights.count,
                    nameWeightID: selectedWeight.id,
                    currentWeightName: isMultiWeightSelected ? selectedWeight.displayName : nil,
                    isExpanded: isExpanded,
                    pendingWeightStatus: pendingStatus)
    }

    /// Whether any face of the font is on the device: deleting removes them all.
    private func hasDownloadedFace(_ entry: FontCatalogEntry) -> Bool {
        entry.weights.contains { library.state(for: entry.fontID, weightID: $0.id).isAvailable }
    }

    /// `selected` is `nil` for a font that is not the current one: none of its
    /// weights gets the yellow frame (TASK-115).
    private func weightCells(of entry: FontCatalogEntry, selected: FontWeightOption?) -> [WeightCell] {
        entry.weights.map { weight in
            WeightCell(fontID: entry.fontID,
                       weightID: weight.id,
                       name: weight.displayName,
                       isSelected: weight.id == selected?.id,
                       status: weightStatus(library.state(for: entry.fontID, weightID: weight.id)))
        }
    }

    private func weightStatus(_ state: FontState) -> Status {
        switch state {
        case .available: return .none
        case .notDownloaded: return .notDownloaded
        case .preparing: return .preparing
        case .downloading(let progress): return .downloading(progress: progress)
        case .failed: return .failed
        }
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
        // Every visit starts collapsed (TASK-112, 112.5).
        expandedFontID = nil
        knownStates = Dictionary(uniqueKeysWithValues: OverlayFontID.allCases.map { ($0, library.state(for: $0)) })
        dropStalePendingWeight()
        refreshLayout()
    }

    /// The list left the screen.
    func listDidDisappear() {
        isVisible = false
    }

    /// Called when the panel's profile copy changes (a font was applied), so
    /// the selection follows.
    func update(profileID: UUID, currentFontID: OverlayFontID, currentWeightID: String? = nil) {
        // A pending face belongs to one profile. It is dropped when the
        // profile changes, or when the current font really changed to
        // something other than the pending face's own font. An update that
        // leaves the font as it was (a color or position edit) keeps it, so a
        // download for an unselected font still applies (TASK-115).
        let fontChanged = self.currentFontID != currentFontID
        if self.profileID != profileID
            || (fontChanged && pendingWeight.map({ $0.fontID != currentFontID }) == true) {
            pendingWeight = nil
        }
        self.profileID = profileID
        if self.currentFontID != currentFontID {
            self.currentFontID = currentFontID
            // A newly applied font shows collapsed (TASK-112, 112.4), except
            // the font the user just expanded and picked a weight of.
            if expandedFontID != currentFontID { expandedFontID = nil }
        }
        if self.currentWeightID != currentWeightID {
            self.currentWeightID = currentWeightID
        }
    }

    // MARK: Tapping

    /// A tap on a cell. Available, not-downloaded and failed fonts go to
    /// `applyFont` (which downloads when needed); a download in progress is
    /// never cancelled, and a font still preparing does nothing.
    func didTap(_ fontID: OverlayFontID) {
        // The selected multi-weight font's row toggles its weight buttons
        // instead of re-applying the font (TASK-112, 112.2); a single-weight
        // font keeps the old behaviour (112.7).
        if fontID == currentFontID, FontCatalog.entry(for: fontID).weights.count > 1 {
            toggleExpansion(of: fontID)
            return
        }
        // Choosing another font is the newer intent: a face still downloading
        // for the current font must not be applied after it (TASK-89).
        if fontID != currentFontID {
            pendingWeight = nil
            expandedFontID = nil
        }
        switch library.state(for: fontID) {
        case .available, .notDownloaded, .failed:
            applyFont(fontID, profileID)
        case .downloading, .preparing:
            break
        }
    }

    /// A tap on a row's chevron (TASK-115): expands or collapses that row's
    /// weight buttons without applying the font. Expanding one row collapses
    /// the one that was open. Single-weight fonts have no chevron.
    func toggleExpansion(of fontID: OverlayFontID) {
        guard FontCatalog.entry(for: fontID).weights.count > 1 else { return }
        expandedFontID = expandedFontID == fontID ? nil : fontID
    }

    /// A tap on a weight button of an expanded card (TASK-89). A usable
    /// face is applied at once. Any other face keeps the old setting: it is
    /// downloaded, remembered as pending, and applied only when the library
    /// reports exactly that face finished; a failed download drops it.
    ///
    /// `fontID` defaults to the current font. For any other font (TASK-115)
    /// the font and the weight are applied together with one save, never the
    /// font's default weight first.
    func didTapWeight(_ weightID: String, of tappedFontID: OverlayFontID? = nil) {
        let fontID = tappedFontID ?? currentFontID
        let entry = FontCatalog.entry(for: fontID)
        guard entry.weights.count > 1 else { return }
        let weight = entry.weight(for: weightID)
        let unit = FontDownloadID(fontID: fontID, weightID: weight.id)
        switch library.state(for: fontID, weightID: weight.id) {
        case .available:
            pendingWeight = nil
            if !applyUsable(fontID, weight.id) { post(Self.weightSaveFailedMessage) }
        case .notDownloaded, .failed:
            pendingWeight = unit
            if !library.download(fontID, weightID: weight.id) { pendingWeight = nil }
            knownWeightStates[unit] = library.state(for: fontID, weightID: weight.id)
            objectWillChange.send()
        case .downloading, .preparing:
            pendingWeight = unit
        }
    }

    /// Saves a usable face: just the weight for the current font, the font
    /// together with the weight for another one (one write, TASK-115).
    private func applyUsable(_ fontID: OverlayFontID, _ weightID: String) -> Bool {
        fontID == currentFontID ? applyWeight(fontID, weightID) : applyFontWithWeight(fontID, weightID)
    }

    /// The library finished a face: applies it only if it is the pending one.
    func weightDownloadDidFinish(_ unit: FontDownloadID) {
        guard pendingWeight == unit else { return }
        pendingWeight = nil
        guard applyUsable(unit.fontID, unit.weightID) else {
            // Saving failed: the old weight stays and the failure is shown.
            if isVisible { post(Self.weightSaveFailedMessage) }
            return
        }
        if isVisible {
            post("已套用「\(FontStateText.weightName(fontID: unit.fontID, weightID: unit.weightID))」")
        }
    }

    /// A face that failed or was cancelled while the list was off screen no
    /// longer waits for a download.
    private func dropStalePendingWeight() {
        guard let unit = pendingWeight else { return }
        knownWeightStates = [:]
        switch library.state(for: unit.fontID, weightID: unit.weightID) {
        case .downloading, .preparing: break
        case .available: weightDownloadDidFinish(unit)
        case .notDownloaded, .failed: pendingWeight = nil
        }
    }

    /// Reports a failed download of the pending face, reading only that
    /// face's own state, and drops the pending request.
    private func noteWeightStates() {
        // A face that settled by preparing (no download event) still applies.
        if let unit = pendingWeight, library.state(for: unit.fontID, weightID: unit.weightID).isAvailable {
            weightDownloadDidFinish(unit)
        }
        // The current font's faces, and the pending face's font (TASK-115).
        var watched = [currentFontID]
        if let pending = pendingWeight, pending.fontID != currentFontID { watched.append(pending.fontID) }
        for fontID in watched {
            let entry = FontCatalog.entry(for: fontID)
            guard entry.weights.count > 1 else { continue }
            for weight in entry.weights {
                let unit = FontDownloadID(fontID: entry.fontID, weightID: weight.id)
                let old = knownWeightStates[unit]
                let new = library.state(for: entry.fontID, weightID: weight.id)
                knownWeightStates[unit] = new
                guard old != new, case .failed(let reason) = new, pendingWeight == unit else { continue }
                pendingWeight = nil
                post(reason == .noNetwork
                     ? FontStateText.offlineMessage
                     : FontStateText.failedMessage(name: FontStateText.weightName(fontID: unit.fontID, weightID: unit.weightID)))
            }
        }
    }

    // MARK: Delete

    /// Opens the delete confirmation of `fontID`; only a downloaded
    /// open-source font has one.
    func requestDeletion(of fontID: OverlayFontID) {
        let entry = FontCatalog.entry(for: fontID)
        guard entry.source == .openSource, hasDownloadedFace(entry) else { return }
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
        noteWeightStates()
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
