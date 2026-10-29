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
        /// Access is still being asked for.
        case waiting
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
    /// Set when adding photos failed; the view surfaces it and clears it.
    @Published var errorMessage: String?
    /// The asset ids on the wall, oldest first.
    private(set) var photoIDs: [String] = []

    private let store: ProfileStore
    private let library: any RecordAlbumLibrary
    private let calendar: Calendar
    private let todayText: (CameraProfile) -> String
    private let presentLimitedPicker: () -> Void
    private var subscription: AnyCancellable?
    private var changesTask: Task<Void, Never>?

    /// Creates the wall of `profileID`.
    ///
    /// - Parameter todayText: "今天第 N 天" for the header, supplied by the
    ///   list so both screens read the same clock and wording.
    /// - Parameter presentLimitedPicker: Opens the system "select more photos"
    ///   sheet; injected so tests can count the calls.
    init(profileID: UUID,
         store: ProfileStore,
         library: any RecordAlbumLibrary,
         calendar: Calendar = .autoupdatingCurrent,
         todayText: @escaping (CameraProfile) -> String,
         presentLimitedPicker: @escaping () -> Void = { LimitedLibraryPicker.present() }) {
        self.profileID = profileID
        self.store = store
        self.library = library
        self.calendar = calendar
        self.todayText = todayText
        self.presentLimitedPicker = presentLimitedPicker
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

    /// "YYYY/M/D 起 · 今天第 N 天" (FR-17.1).
    var subtitle: String {
        guard let profile else { return "" }
        let start = profile.startDate
        let date = "\(start.year ?? 0)/\(start.month ?? 0)/\(start.day ?? 0)"
        return "\(date) 起 · \(todayText(profile))"
    }

    // MARK: - State

    /// Limited access: the wall shows the "not synced with Photos" notice and
    /// "加入照片" opens the system picker (§7.3).
    var isLimited: Bool { status == .limited }

    var content: Content {
        switch status {
        case .authorized, .limited: return photoIDs.isEmpty ? .empty : .photos
        case .notDetermined: return .waiting
        default: return .needsPermission
        }
    }

    /// Asks for `.readWrite` the first time any record is opened (§7.1), then
    /// reads the photos.
    func prepare() async {
        if library.authorizationStatus() == .notDetermined {
            status = await library.requestReadWriteAccess()
        }
        reload()
    }

    /// Re-reads the photos and recomputes every mark.
    func reload() {
        status = library.authorizationStatus()
        guard let profile, RecordReadMode(status: status) != .none else {
            photoIDs = []
            sections = []
            return
        }
        let photos = library.photos(albumIdentifier: profile.albumIdentifier,
                                    fallbackIDs: profile.fallbackAssetIDs)
        photoIDs = photos.map(\.id)
        sections = Self.sections(for: photos, profile: profile, calendar: calendar)
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
    /// more photos" sheet itself and returns `false`: the photos the user
    /// ticks there are the record's photos, so no `PHPicker` and no album
    /// write follow (§7.3). Otherwise returns `true` for the caller to show
    /// its own picker.
    func beginAddingPhotos() -> Bool {
        guard isLimited else { return true }
        presentLimitedPicker()
        return false
    }

    /// Adds the picked assets to the record's album, creating the album when
    /// the record has none, and stores the album id if it changed (FR-17.7).
    /// A failure sets `errorMessage` and leaves the wall as it was.
    func addPhotos(ids: [String]) async {
        guard !ids.isEmpty, let profile else { return }
        do {
            let albumID = try await library.addAssets(ids,
                                                     albumIdentifier: profile.albumIdentifier,
                                                     albumTitle: profile.name)
            if albumID != profile.albumIdentifier, var latest = store.profiles.first(where: { $0.id == profileID }) {
                latest.albumIdentifier = albumID
                try store.updateAndWait(latest)
            }
            reload()
        } catch let error as RecordAlbumError {
            errorMessage = Self.message(for: error)
        } catch let error as ProfileStoreError {
            errorMessage = error.displayMessage
        } catch {
            errorMessage = "無法加入照片，請再試一次。"
        }
    }

    /// The text of the failure alert for `error`.
    static func message(for error: RecordAlbumError) -> String {
        switch error {
        case .permissionDenied: return "需要相簿權限才能加入照片。"
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
    @MainActor
    static func present() {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        guard let top else { return }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: top)
    }
}
