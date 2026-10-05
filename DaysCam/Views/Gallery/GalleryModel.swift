import Combine
import Foundation
import Photos
import UIKit

/// State and text of the photo browsing screen (PRD 0.2 FR-15.4～15.9,
/// design D-5). `GalleryView` only lays out what this model says.
@MainActor
final class GalleryModel: ObservableObject {
    enum Phase: Equatable {
        /// Permission not answered / list not read yet.
        case loading
        /// `.denied` or `.restricted` (FR-15.8).
        case denied
        /// Permitted but nothing to show (FR-15.7).
        case empty
        case photos
    }

    @Published private(set) var phase: Phase = .loading
    /// Newest first.
    @Published private(set) var photos: [GalleryPhoto] = []
    /// Index into `photos` of the photo on screen.
    @Published var selectedIndex = 0
    /// Set while a system delete is in flight, so the trash cannot be hit twice.
    @Published private(set) var isDeleting = false

    private let library: GalleryLibrary
    private let formatter: DateFormatter

    init(library: GalleryLibrary, timeZone: TimeZone = .autoupdatingCurrent) {
        self.library = library
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        self.formatter = formatter
    }

    // MARK: - Text

    /// The photo on screen, if any.
    var currentPhoto: GalleryPhoto? {
        photos.indices.contains(selectedIndex) ? photos[selectedIndex] : nil
    }

    /// Capture date and time of the photo on screen (FR-15.5); a plain
    /// "照片" outside the photo state or when the date is unknown.
    var titleText: String {
        guard phase == .photos, let date = currentPhoto?.creationDate else { return "照片" }
        return formatter.string(from: date)
    }

    /// "第幾張 / 共幾張", newest = 1; `nil` outside the photo state.
    var subtitleText: String? {
        guard phase == .photos else { return nil }
        return "\(selectedIndex + 1) / \(photos.count)"
    }

    // MARK: - Loading

    /// Asks for read access when still undecided, then reads the list
    /// (FR-15.3). Safe to call again; the library never re-prompts.
    func requestAccessAndLoad() async {
        let status = await library.requestReadAccess()
        apply(status: status)
        startObservingLibraryChanges()
    }

    /// Re-reads the list — e.g. coming back from the Photos app, where a
    /// photo may have been deleted (FR-15.4, acceptance 29.10). Keeps the
    /// same photo selected when it still exists.
    func reload() {
        guard phase == .photos || phase == .empty else { return }
        let keptID = currentPhoto?.id
        let latest = library.photos()
        // Unrelated library changes must not republish (and redraw) the list.
        guard latest != photos || (phase == .empty) != latest.isEmpty else { return }
        setPhotos(latest, preferring: keptID)
    }

    private var observationTask: Task<Void, Never>?

    /// Starts re-reading the list whenever the library changes (issue #192:
    /// limited selection edited in Settings, photo deleted elsewhere).
    /// Idempotent; does nothing unless read access is granted. Called after
    /// every successful load, so denied → authorized while open also starts it.
    func startObservingLibraryChanges() {
        guard observationTask == nil, phase == .photos || phase == .empty else { return }
        let changes = library.changes()
        observationTask = Task { @MainActor [weak self] in
            for await _ in changes {
                if Task.isCancelled { break }
                self?.reload()
            }
        }
    }

    /// Stops observing (gallery closed); unregisters the system observer.
    func stopObservingLibraryChanges() {
        observationTask?.cancel()
        observationTask = nil
    }

    private func apply(status: PHAuthorizationStatus) {
        switch status {
        case .authorized, .limited:
            selectedIndex = 0
            setPhotos(library.photos(), preferring: nil)
        case .notDetermined:
            phase = .loading
        default:
            photos = []
            phase = .denied
        }
    }

    private func setPhotos(_ newPhotos: [GalleryPhoto], preferring id: String?) {
        photos = newPhotos
        if let id, let index = newPhotos.firstIndex(where: { $0.id == id }) {
            selectedIndex = index
        } else {
            selectedIndex = min(selectedIndex, max(newPhotos.count - 1, 0))
        }
        phase = newPhotos.isEmpty ? .empty : .photos
    }

    // MARK: - Deleting

    /// Deletes the photo on screen through the system confirmation
    /// (FR-15.6). Afterwards the next photo takes its place, or the previous
    /// one when it was the last, or the empty state when none is left. A
    /// cancelled confirmation changes nothing.
    func deleteCurrent() async {
        guard phase == .photos, !isDeleting, let photo = currentPhoto else { return }
        isDeleting = true
        defer { isDeleting = false }
        guard await library.deletePhoto(id: photo.id) else { return }
        guard let index = photos.firstIndex(where: { $0.id == photo.id }) else { return }
        var remaining = photos
        remaining.remove(at: index)
        photos = remaining
        selectedIndex = min(index, max(remaining.count - 1, 0))
        phase = remaining.isEmpty ? .empty : .photos
    }

    /// Image for the large view or the strip.
    func image(for photo: GalleryPhoto, targetSize: CGSize) async -> UIImage? {
        await library.image(id: photo.id, targetSize: targetSize)
    }
}
