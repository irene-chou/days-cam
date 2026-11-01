import Combine
import Foundation
import Photos
import UIKit

/// Drives the photo wall of one record (PRD 2.0 FR-17, D-7 screen 2).
///
/// Reads the record's photos from a `RecordAlbumLibrary`, groups them by month
/// oldest to newest and marks each with its day count, computed on the spot
/// from the photo's own `creationDate` (§6.1). Nothing here reads EXIF or file
/// times, and nothing is written to a photo.
@MainActor
final class PhotoWallModel: ObservableObject {
    /// One square of the grid.
    struct Cell: Identifiable, Equatable {
        /// `PHAsset.localIdentifier`.
        let id: String
        /// "第 N 天", "前 N 天" or "日期不明" (FR-17.4, §6.1.3, §6.2).
        let dayText: String
        /// The photo was taken before the start date: the mark uses the
        /// warm `inkOnPhotoBeforeStart` color.
        let isBeforeStart: Bool
    }

    /// One month of the wall under its "YYYY 年 M 月" heading.
    struct Section: Identifiable, Equatable {
        let id: String
        let title: String
        let cells: [Cell]
    }

    /// What the wall shows for the current permission and content.
    enum Content: Equatable {
        /// Access was never asked: the permission intro shows, and only its
        /// "繼續" asks (§7.1).
        case permissionIntro
        /// Access is denied or restricted: the wall gives way to the
        /// permission page (§7.4). The record itself stays editable.
        case needsPermission
        /// Full access, nothing to show (FR-17.10).
        case empty
        case photos
    }

    /// Heading of the photos that have no `creationDate`.
    static let unknownMonthTitle = "日期不明"

    let profileID: UUID
    @Published private(set) var profile: CameraProfile?
    @Published private(set) var sections: [Section] = []
    @Published private(set) var status: PHAuthorizationStatus
    /// Set when adding, removing or deleting failed; the view surfaces it
    /// and clears it.
    @Published var errorMessage: String?
    /// The title of the alert for `errorMessage`.
    private(set) var errorTitle = PhotoWallModel.addFailedTitle
    /// The asset ids on the wall, oldest first.
    private(set) var photoIDs: [String] = []
    /// The photos on the wall, oldest first.
    private var photos: [RecordPhoto] = []
    /// Photos without a `creationDate`: they can be removed or deleted but
    /// not exported (FR-17.12, FR-22.6).
    private var undatedIDs: Set<String> = []
    /// The batch export sheet while it is up (FR-22.4).
    @Published private(set) var batchExport: BatchExportModel?

    /// Selection mode is on (FR-17.11).
    @Published private(set) var isSelecting = false
    /// The ticked photos (FR-17.12).
    @Published private(set) var selectedIDs: Set<String> = []
    /// The "已從紀錄移除 N 張" / "已刪除 N 張" toast while it shows.
    @Published private(set) var toastState: ToastState?
    /// A slide selection in progress: where it started and what was ticked
    /// before it.
    private var drag: (anchor: Int, original: Set<String>)?

    static let addFailedTitle = "無法加入照片"
    static let removeFailedTitle = "無法從紀錄移除"
    static let deleteFailedTitle = "無法刪除照片"
    /// How long the toast stays.
    static let toastDuration: TimeInterval = 1.6

    /// Speaks `message` to VoiceOver. Replaceable so tests can observe it.
    var announce: (String) -> Void = { message in
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    private let store: ProfileStore
    private let library: any RecordAlbumLibrary
    private let calendar: Calendar
    private let todayText: (CameraProfile) -> String
    private let backfillAlbums: () async -> Void
    private let saveCoordinator: CaptureSaveCoordinator
    private let presentLimitedPicker: () async -> [String]
    private let openSettings: (URL) -> Void
    private let defaults: UserDefaults
    private let scheduleAfter: (TimeInterval, @escaping () -> Void) -> Void
    private let makeBatchExport: (([RecordPhoto]) -> BatchExportModel)?
    /// App-wide flag behind the dismissed notice; cleared once the status is
    /// seen to be anything but limited, so a later return to limited shows it
    /// again (#642).
    static let noticeDismissedKey = "limitedNoticeDismissed"
    @Published private(set) var noticeDismissed: Bool
    private var subscription: AnyCancellable?
    private var changesTask: Task<Void, Never>?

    /// Creates the wall of `profileID`.
    ///
    /// - Parameter todayText: "今天第 N 天" for the header, supplied by the
    ///   list so both screens read the same clock and wording.
    /// - Parameter saveCoordinator: the app's queue of writes that may
    ///   create an album; "加入照片" joins it (#651).
    /// - Parameter backfillAlbums: creates the albums of records that have
    ///   none, run when the intro's prompt comes back with full access
    ///   (FR-21.6).
    /// - Parameter presentLimitedPicker: Opens the system "select more photos"
    ///   sheet and returns the ids the user newly selected there; injected so
    ///   tests can stand in for the sheet.
    /// - Parameter openSettings: Opens the app's Settings page from the
    ///   limited access notice; injected so tests can capture the URL.
    /// - Parameter makeBatchExport: Builds the batch export sheet's model for
    ///   the ticked photos (wall order); `nil` leaves 匯出 doing nothing.
    init(profileID: UUID,
         store: ProfileStore,
         library: any RecordAlbumLibrary,
         calendar: Calendar = .autoupdatingCurrent,
         saveCoordinator: CaptureSaveCoordinator? = nil,
         todayText: @escaping (CameraProfile) -> String,
         backfillAlbums: @escaping () async -> Void = {},
         presentLimitedPicker: (() async -> [String])? = nil,
         openSettings: ((URL) -> Void)? = nil,
         defaults: UserDefaults = .standard,
         scheduleAfter: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, action in
             DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
         },
         makeBatchExport: (([RecordPhoto]) -> BatchExportModel)? = nil) {
        self.makeBatchExport = makeBatchExport
        self.profileID = profileID
        self.store = store
        self.library = library
        self.calendar = calendar
        self.todayText = todayText
        self.backfillAlbums = backfillAlbums
        self.saveCoordinator = saveCoordinator ?? CaptureSaveCoordinator()
        self.presentLimitedPicker = presentLimitedPicker ?? { await LimitedLibraryPicker.present() }
        self.openSettings = openSettings ?? { UIApplication.shared.open($0) }
        self.defaults = defaults
        self.scheduleAfter = scheduleAfter
        self.noticeDismissed = defaults.bool(forKey: Self.noticeDismissedKey)
        self.status = library.authorizationStatus()
        self.profile = store.profiles.first { $0.id == profileID }
        subscription = store.$profiles
            .dropFirst()
            .sink { [weak self] profiles in
                guard let self else { return }
                self.profile = profiles.first { $0.id == self.profileID }
                self.reload()
            }
        reload()
    }

    deinit {
        changesTask?.cancel()
    }

    // MARK: - Header

    /// The record's name.
    var title: String { profile?.name ?? "" }

    /// "YYYY/M/D 起" (FR-17.1).
    var subtitle: String {
        guard let profile else { return "" }
        let start = profile.startDate
        let date = "\(start.year ?? 0)/\(start.month ?? 0)/\(start.day ?? 0)"
        return "\(date) 起"
    }

    // MARK: - State

    /// Limited access: the wall shows the "not synced with Photos" notice and
    /// "加入照片" opens the system picker; the wall lists only this record's
    /// `fallbackAssetIDs` (§7.3).
    var isLimited: Bool { status == .limited }

    /// Whether the notice shows: limited and not dismissed since it last
    /// became limited.
    var showsLimitedNotice: Bool { isLimited && !noticeDismissed }

    /// Hides the notice until the status leaves limited and comes back.
    func dismissLimitedNotice() {
        defaults.set(true, forKey: Self.noticeDismissedKey)
        noticeDismissed = true
    }

    /// Opens the app's Settings page so the user can switch to full access
    /// (#642); the wall re-reads when the app returns to the foreground.
    func openLimitedAccessSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openSettings(url)
    }

    /// The line under "還沒有照片", by access (FR-17.10).
    var emptyMessage: String {
        isLimited ? "用相機拍一張，或按左下角加入照片"
            : "用相機拍一張，或在「照片」App 把照片加入「\(title)」相簿，會自動出現在這裡"
    }

    var content: Content {
        switch status {
        case .authorized, .limited: return photoIDs.isEmpty ? .empty : .photos
        case .notDetermined: return .permissionIntro
        default: return .needsPermission
        }
    }

    /// Reads the photos. Never asks: an undecided status shows the
    /// permission intro instead (§7.1).
    func prepare() async {
        reload()
    }

    /// True while the intro's prompt is up, so "繼續" asks only once.
    @Published private(set) var isRequestingAccess = false

    /// The intro's "繼續": asks for `.readWrite` once, then shows the wall
    /// (full access backfills the albums first, FR-21.6), the wall with the
    /// limited notice, or the permission page (§7.1).
    func continueFromIntro() async {
        guard !isRequestingAccess, library.authorizationStatus() == .notDetermined else {
            reload()
            return
        }
        isRequestingAccess = true
        let granted = await library.requestReadWriteAccess()
        if granted == .authorized { await backfillAlbums() }
        isRequestingAccess = false
        reload()
    }

    /// Re-reads the photos and recomputes every mark.
    func reload() {
        status = library.authorizationStatus()
        if status != .limited, noticeDismissed {
            defaults.set(false, forKey: Self.noticeDismissedKey)
            noticeDismissed = false
        }
        guard let profile, RecordReadMode(status: status) != .none else {
            photos = []
            photoIDs = []
            undatedIDs = []
            sections = []
            pruneSelection()
            return
        }
        photos = library.photos(albumIdentifier: profile.albumIdentifier,
                                fallbackIDs: profile.fallbackAssetIDs)
        photoIDs = photos.map(\.id)
        undatedIDs = Set(photos.filter { $0.creationDate == nil }.map(\.id))
        sections = Self.sections(for: photos, profile: profile, calendar: calendar)
        pruneSelection()
    }

    /// Drops ticks on photos no longer on the wall (FR-17.8), and leaves
    /// selection mode once the wall has nothing to select.
    private func pruneSelection() {
        let shown = Set(photoIDs)
        if !selectedIDs.isSubset(of: shown) { selectedIDs.formIntersection(shown) }
        if isSelecting, content != .photos { endSelecting() }
    }

    // MARK: - Selection (FR-17.11–17.13)

    /// 「選取」 is usable: there is at least one photo.
    var canSelect: Bool { content == .photos }

    /// "已選 N 張", or "選取照片" with nothing ticked.
    var selectionTitle: String {
        selectedIDs.isEmpty ? "選取照片" : "已選 \(selectedIDs.count) 張"
    }

    /// Every photo on the wall is ticked: the leading button reads 取消全選.
    var isAllSelected: Bool { !photoIDs.isEmpty && selectedIDs.count == photoIDs.count }

    /// 匯出 is usable: at least one ticked photo has a date (FR-17.13).
    var canExportSelection: Bool { selectedIDs.contains { !undatedIDs.contains($0) } }

    /// The ticked photos in wall order.
    var orderedSelection: [String] { photoIDs.filter(selectedIDs.contains) }

    func beginSelecting() {
        guard canSelect else { return }
        selectedIDs = []
        isSelecting = true
    }

    /// 取消: leaves selection mode and clears the ticks.
    func endSelecting() {
        isSelecting = false
        selectedIDs = []
        drag = nil
    }

    func toggle(_ id: String) {
        guard isSelecting, photoIDs.contains(id) else { return }
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
    }

    func selectAll() { selectedIDs = Set(photoIDs) }

    func deselectAll() { selectedIDs = [] }

    /// A finger went down on the photo at `index` (wall order) to slide.
    func beginDrag(at index: Int) {
        guard isSelecting, photoIDs.indices.contains(index) else { return }
        drag = (index, selectedIDs)
        dragSelection(to: index)
    }

    /// The finger is over the photo at `index`.
    func dragSelection(to index: Int) {
        guard let drag, photoIDs.indices.contains(index) else { return }
        selectedIDs = Self.slideSelection(anchor: drag.anchor, current: index,
                                          original: drag.original, ids: photoIDs)
    }

    func endDrag() { drag = nil }

    /// The ticks after sliding from `anchor` to `current` over `ids` (wall
    /// order), starting from `original` (FR-17.12). The whole range between
    /// them is ticked, or unticked when the anchor was already ticked; photos
    /// outside it keep their state from `original`, so sliding back shrinks
    /// the range and restores what it leaves.
    static func slideSelection(anchor: Int, current: Int, original: Set<String>, ids: [String]) -> Set<String> {
        guard ids.indices.contains(anchor), ids.indices.contains(current) else { return original }
        let ticking = !original.contains(ids[anchor])
        var result = original
        for id in ids[min(anchor, current)...max(anchor, current)] {
            if ticking { result.insert(id) } else { result.remove(id) }
        }
        return result
    }

    // MARK: - Batch export (FR-22.4–22.9)

    /// 匯出 in the selection bar: opens the preview sheet over the ticked
    /// photos in wall order, 日期不明 ones included so the sheet can say how
    /// many it skips.
    func beginBatchExport() {
        guard isSelecting, canExportSelection, batchExport == nil, let makeBatchExport else { return }
        let model = makeBatchExport(photos.filter { selectedIDs.contains($0.id) })
        model.onFinish = { [weak self] outcome in self?.finishBatchExport(outcome) }
        batchExport = model
    }

    /// The sheet ended: 取消 keeps the selection; all saved or stopped
    /// toasts the real count and ends selection; 好 after failures keeps
    /// selecting with only the failed photos ticked.
    func finishBatchExport(_ outcome: BatchExportModel.Outcome) {
        batchExport = nil
        switch outcome {
        case .cancelled:
            break
        case let .allSaved(count), let .stopped(count):
            endSelecting()
            showToast("已匯出 \(count) 張")
        case let .keptFailures(failedIDs):
            guard canSelect else { return }
            isSelecting = true
            selectedIDs = Set(failedIDs).intersection(photoIDs)
        }
    }

    // MARK: - Removing and deleting the selection (FR-17.14, FR-17.15)

    /// 從「<紀錄名>」移除, no further confirmation. With full access and an
    /// album, the ticked photos leave the album in one change; any listed in
    /// `fallbackAssetIDs` leave it in one profile write. Limited access only
    /// touches `fallbackAssetIDs`. The photos stay in 「照片」. On failure the
    /// selection stays and an error shows; on success a toast, and selection
    /// mode ends.
    func removeSelected() async {
        guard let profile, !selectedIDs.isEmpty else { return }
        let ids = orderedSelection
        let removing = Set(ids)
        do {
            if let albumID = profile.albumIdentifier, library.authorizationStatus() == .authorized {
                try await library.removeAssets(ids, fromAlbum: albumID)
            }
            if var latest = store.profiles.first(where: { $0.id == profileID }),
               latest.fallbackAssetIDs.contains(where: removing.contains) {
                latest.fallbackAssetIDs.removeAll(where: removing.contains)
                try store.updateAndWait(latest)
            }
        } catch let error as RecordAlbumError {
            report(Self.removalMessage(for: error), title: Self.removeFailedTitle)
            return
        } catch let error as ProfileStoreError {
            report(error.displayMessage, title: Self.removeFailedTitle)
            return
        } catch {
            report("無法從紀錄移除，請再試一次。", title: Self.removeFailedTitle)
            return
        }
        finish(ids, done: "已從紀錄移除", stillShown: { "有 \($0) 張照片無法從紀錄移除。" },
               title: Self.removeFailedTitle)
    }

    /// 刪除 N 張照片: one system confirmation for all of them. A cancel
    /// changes nothing and keeps the selection.
    func deleteSelected() async {
        let ids = orderedSelection
        guard !ids.isEmpty, await library.deleteAssets(ids) else { return }
        finish(ids, done: "已刪除", stillShown: { "有 \($0) 張照片無法刪除。" }, title: Self.deleteFailedTitle)
    }

    /// Re-reads the wall; reports the photos of `ids` still on it as a
    /// failure (ticks kept), else toasts "<done> N 張" and ends selection.
    private func finish(_ ids: [String], done: String, stillShown: (Int) -> String, title: String) {
        reload()
        let left = ids.filter(photoIDs.contains)
        guard left.isEmpty else {
            selectedIDs = Set(left)
            report(stillShown(left.count), title: title)
            return
        }
        endSelecting()
        showToast("\(done) \(ids.count) 張")
    }

    /// Shows `message` as the toast and speaks it to VoiceOver.
    private func showToast(_ message: String) {
        announce(message)
        let toast = ToastState(message: message)
        toastState = toast
        scheduleAfter(Self.toastDuration) { [weak self] in
            guard self?.toastState?.id == toast.id else { return }
            self?.toastState = nil
        }
    }

    private func report(_ message: String, title: String) {
        errorTitle = title
        errorMessage = message
    }

    /// The text of the removal failure alert for `error` (FR-17.15).
    static func removalMessage(for error: RecordAlbumError) -> String {
        switch error {
        case .permissionDenied: return "需要「照片」權限才能從紀錄移除。"
        case .notFound: return "找不到選取的照片，它們可能已被刪除。"
        case let .failed(reason): return reason.isEmpty ? "無法從紀錄移除，請再試一次。" : reason
        }
    }

    // MARK: - Following the library

    /// Starts following library changes (FR-17.8): photos added to or removed
    /// from the album, or dated again in the Photos app, reload the wall.
    func startObservingLibrary() {
        guard changesTask == nil else { return }
        let changes = library.changes()
        changesTask = Task { [weak self] in
            for await _ in changes {
                self?.reload()
            }
        }
    }

    func stopObservingLibrary() {
        changesTask?.cancel()
        changesTask = nil
    }

    // MARK: - Adding photos

    /// The 「加入照片」 tap. Under limited access it opens the system "select
    /// more photos" sheet itself (`addFromLimitedPicker`) and returns
    /// `false`: no `PHPicker` and no album write follow (§7.3). Otherwise
    /// returns `true` for the caller to show its own picker.
    func beginAddingPhotos() -> Bool {
        guard isLimited else { return true }
        Task { await addFromLimitedPicker() }
        return false
    }

    /// Limited access: opens the system sheet and appends the photos newly
    /// selected there to this record's `fallbackAssetIDs`, skipping ids it
    /// already has (§7.3, #640). Other records are untouched. A failed write
    /// sets `errorMessage`.
    func addFromLimitedPicker() async {
        let picked = await presentLimitedPicker()
        guard !picked.isEmpty, var latest = store.profiles.first(where: { $0.id == profileID }) else { return }
        let merged = Self.appendingNew(picked, to: latest.fallbackAssetIDs)
        guard merged != latest.fallbackAssetIDs else { return }
        latest.fallbackAssetIDs = merged
        do {
            try store.updateAndWait(latest)
            reload()
        } catch let error as ProfileStoreError {
            report(error.displayMessage, title: Self.addFailedTitle)
        } catch {
            report("無法加入照片，請再試一次。", title: Self.addFailedTitle)
        }
    }

    /// `existing` followed by the ids of `picked` it does not have yet, in
    /// order and without repeats.
    static func appendingNew(_ picked: [String], to existing: [String]) -> [String] {
        var seen = Set(existing)
        var result = existing
        for id in picked where seen.insert(id).inserted {
            result.append(id)
        }
        return result
    }

    /// Adds the picked assets to the record's album, creating the album when
    /// the record has none, and stores the album id if it changed (FR-17.7).
    /// Waits in `saveCoordinator`'s queue and reads the album there, so an
    /// album still being created is used rather than duplicated (#651).
    /// A failure sets `errorMessage` and leaves the wall as it was.
    func addPhotos(ids: [String]) async {
        guard !ids.isEmpty, profile != nil else { return }
        do {
            try await saveCoordinator.serialized {
                guard let current = store.profiles.first(where: { $0.id == profileID }) else { return }
                let albumID = try await library.addAssets(ids,
                                                         albumIdentifier: current.albumIdentifier,
                                                         albumTitle: current.name)
                if albumID != current.albumIdentifier, var latest = store.profiles.first(where: { $0.id == profileID }) {
                    latest.albumIdentifier = albumID
                    try store.updateAndWait(latest)
                }
            }
            reload()
        } catch let error as RecordAlbumError {
            report(Self.message(for: error), title: Self.addFailedTitle)
        } catch let error as ProfileStoreError {
            report(error.displayMessage, title: Self.addFailedTitle)
        } catch {
            report("無法加入照片，請再試一次。", title: Self.addFailedTitle)
        }
    }

    /// The text of the failure alert for `error`.
    static func message(for error: RecordAlbumError) -> String {
        switch error {
        case .permissionDenied: return "需要「照片」權限才能加入照片。"
        case .notFound: return "找不到選取的照片，它們可能已被刪除。"
        case let .failed(reason): return reason.isEmpty ? "無法加入照片，請再試一次。" : reason
        }
    }

    // MARK: - Marks and months

    /// The mark for a photo taken at `creationDate` (FR-17.4, §6.1.3, §6.2).
    ///
    /// Only the day count is shown, in the "第 N 天" wording whatever the
    /// record's format and units. The clock is the photo's own date, so the
    /// calculator never sees the current time.
    static func dayMark(creationDate: Date?, profile: CameraProfile, calendar: Calendar) -> (text: String, isBeforeStart: Bool) {
        guard let creationDate else { return (TemplateRenderer.unknownDateText, false) }
        let calculator = DayCountCalculator(calendar: calendar, now: { creationDate })
        let raw = calculator.rawDayDifference(from: profile.startDate)
        if raw < 0 {
            return (TemplateRenderer.daysBeforeStartText(days: -raw), true)
        }
        let count = calculator.dayCount(from: profile.startDate, rule: profile.countingRule)
        return (DayCountFormat.ordinal.elapsedText(count: count), false)
    }

    /// Groups `photos` (already oldest first) into months under "YYYY 年 M 月".
    /// Photos without a date lead under their own heading.
    static func sections(for photos: [RecordPhoto], profile: CameraProfile, calendar: Calendar) -> [Section] {
        var result: [Section] = []
        for photo in photos {
            let key: String
            let title: String
            if let date = photo.creationDate {
                let parts = calendar.dateComponents([.year, .month], from: date)
                key = String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
                title = "\(parts.year ?? 0) 年 \(parts.month ?? 0) 月"
            } else {
                key = "unknown"
                title = unknownMonthTitle
            }
            let mark = dayMark(creationDate: photo.creationDate, profile: profile, calendar: calendar)
            let cell = Cell(id: photo.id, dayText: mark.text, isBeforeStart: mark.isBeforeStart)
            if let last = result.last, last.id == key {
                result[result.count - 1] = Section(id: key, title: title, cells: last.cells + [cell])
            } else {
                result.append(Section(id: key, title: title, cells: [cell]))
            }
        }
        return result
    }
}

/// Opens the system limited-library picker over the topmost view controller.
enum LimitedLibraryPicker {
    /// Presents the picker and returns, once it is dismissed, the local
    /// identifiers the user newly selected (photos already in the selection
    /// are not reported, per `PHPhotoLibrary+PhotosUISupport.h`). Empty when
    /// there is nothing to present over.
    @MainActor
    static func present() async -> [String] {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        guard let top else { return [] }
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: top) { identifiers in
                continuation.resume(returning: identifiers)
            }
        }
    }
}
