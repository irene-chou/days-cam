import SwiftUI

@main
struct DaysCamApp: App {
    @StateObject private var recordListModel: RecordListModel
    /// Fonts and the export page's style editors, for the app's lifetime: a
    /// font still downloading for a record lands whatever screen is up.
    private let styleCenter: StyleEditingCenter
    /// Builds the camera of a record each time it opens from the photo wall
    /// (#621). One `CameraService` serves every camera, so a switched lens
    /// or a granted permission survives closing and reopening it; the
    /// camera's own model stops the session when it closes.
    private let makeCameraModel: @MainActor (UUID) -> CameraScreenModel

    init() {
        let profileStore = Self.makeProfileStore()
        let library = Self.makeRecordAlbumLibrary(for: profileStore)
        styleCenter = StyleEditingCenter(profileStore: profileStore,
                                         fontLibrary: Self.uiTestFontLibrary ?? FontLibrary())
        let recordListModel = RecordListModel(store: profileStore, library: library, exportSave: Self.exportSave)
        makeCameraModel = Self.cameraModelFactory(profileStore: profileStore, library: library,
                                                  listModel: recordListModel, styleCenter: styleCenter)
        _recordListModel = StateObject(wrappedValue: recordListModel)
    }

    var body: some Scene {
        WindowGroup {
            RecordListView(model: recordListModel,
                           styleCenter: styleCenter,
                           makeCameraModel: makeCameraModel,
                           opensFirstRecordAtLaunch: Self.opensFirstRecordAtLaunch)
        }
    }

    /// Debug UI tests pass `-UITestOpenFirstRecord` to enter the first
    /// record's photo wall at launch instead of stopping on the list (#617,
    /// #618); they tap `wallCameraButton` to reach the camera. Debug builds
    /// only.
    private static var opensFirstRecordAtLaunch: Bool {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-UITestOpenFirstRecord") || arguments.contains("-UITestOpenExport")
        #else
        return false
        #endif
    }

    /// The photo library behind the list. Debug UI tests with
    /// `-UITestRecordPhotos <n>` get an in-memory one holding an album
    /// "測試相簿" with all `n` photos; `-UITestBindAlbum` (and
    /// `-UITestOpenExport`, #620) also binds every record to it.
    /// `-UITestUndatedPhotos <k>` takes the date off the oldest `k` (#650).
    private static func makeRecordAlbumLibrary(for profileStore: ProfileStore) -> any RecordAlbumLibrary {
        #if DEBUG
        if let fake = FakeRecordAlbumLibrary.forUITests() {
            let arguments = ProcessInfo.processInfo.arguments
            var assets = fake.assets
            if let index = arguments.firstIndex(of: "-UITestUndatedPhotos"), arguments.indices.contains(index + 1),
               let undated = Int(arguments[index + 1]) {
                for offset in assets.indices.prefix(undated) { assets[offset].creationDate = nil }
            }
            let album = FakeRecordAlbumLibrary.Album(id: "uitest-album", title: "測試相簿",
                                                     assetIDs: assets.map(\.id))
            let library = FakeRecordAlbumLibrary(status: fake.status, assets: assets, albums: [album])
            if arguments.contains("-UITestBindAlbum") || arguments.contains("-UITestOpenExport") {
                for var profile in profileStore.profiles {
                    profile.albumIdentifier = album.id
                    _ = try? profileStore.update(profile)
                }
            }
            // Limited access shows only a record's fallback ids (#640): the
            // generated photos belong to the last used record, as after the
            // legacy migration.
            if fake.status == .limited,
               let lastUsed = profileStore.lastUsedProfileID,
               var profile = profileStore.profiles.first(where: { $0.id == lastUsed }) {
                profile.fallbackAssetIDs = PhotoWallModel.appendingNew(fake.assets.map(\.id), to: profile.fallbackAssetIDs)
                _ = try? profileStore.update(profile)
            }
            return library
        }
        // Entering a record asks for photo access; an empty in-memory library
        // keeps that system alert out of the tests that only want the camera.
        if ProcessInfo.processInfo.arguments.contains("-UITestOpenFirstRecord") {
            return FakeRecordAlbumLibrary()
        }
        #endif
        return SystemRecordAlbumLibrary()
    }

    /// Where an exported photo is saved: 「最近項目」 only (PRD 2.0 FR-19.9).
    /// Debug UI tests with the in-memory library (`-UITestRecordPhotos`)
    /// pretend the save worked, so no system permission alert comes up (#620).
    /// For the batch export (#650), `-UITestExportDelay <seconds>` slows each
    /// save and `-UITestExportFailures <n,m>` fails the n-th and m-th saves.
    private static var exportSave: PhotoExportPipeline.Save {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-UITestRecordPhotos") {
            func value(after flag: String) -> String? {
                guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
                return arguments[index + 1]
            }
            let delay = value(after: "-UITestExportDelay").flatMap(Double.init) ?? 0
            let failing = Set((value(after: "-UITestExportFailures") ?? "").split(separator: ",").compactMap { Int($0) })
            var count = 0
            return { _, completion in
                count += 1
                let fails = failing.contains(count)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    completion(fails ? .failure(.saveFailed("uitest")) : .success("uitest-export"))
                }
            }
        }
        #endif
        return { image, completion in PhotoSaver().saveToRecentsOnly(image, completion: completion) }
    }

    /// Builds the one `ProfileStore` shared by the list and the camera.
    ///
    /// `ProfileStore.load()` runs here, before the first frame: a fresh
    /// install seeds one default profile, an existing install applies
    /// `lastUsedProfileID` (falling back to the first profile when it no
    /// longer exists). The app lands on the 紀錄 list (PRD 2.0 FR-16).
    private static func makeProfileStore() -> ProfileStore {
        let profileStore = ProfileStore(directory: uiTestProfileDirectory)
        profileStore.load()
        applyUITestSecondRecord(to: profileStore)
        applyUITestFilmDate(to: profileStore)
        return profileStore
    }

    /// Builds the camera for record `id` over the one `CameraService`.
    ///
    /// Opening the camera makes the record the last opened one (PRD 2.0
    /// §4.2). The corner button shows the newest photo of whichever record
    /// the camera's switcher has selected (#655). A save
    /// that fails after the camera closed, and a failed write of the record,
    /// are shown by the 紀錄 list, which outlives every camera.
    private static func cameraModelFactory(profileStore: ProfileStore,
                                           library: any RecordAlbumLibrary,
                                           listModel: RecordListModel,
                                           styleCenter: StyleEditingCenter) -> @MainActor (UUID) -> CameraScreenModel {
        let cameraService = CameraService()
        // One count and one save queue for every camera opened, so closing
        // and reopening cannot pass the in-flight limit or create a second
        // album for a record (#636 review).
        let saveCoordinator = CaptureSaveCoordinator()
        let save = cameraSave(library: library)
        return { id in
            profileStore.select(id: id)
            return CameraScreenModel(
                cameraService: cameraService,
                profileStore: profileStore,
                profileID: id,
                saveCoordinator: saveCoordinator,
                save: save,
                loadLatestPhoto: { recordID in
                    guard let profile = profileStore.profiles.first(where: { $0.id == recordID }),
                          let newest = library.photos(albumIdentifier: profile.albumIdentifier,
                                                      fallbackIDs: profile.fallbackAssetIDs).last else { return nil }
                    return await library.thumbnail(id: newest.id, targetSize: CGSize(width: 200, height: 200))
                },
                reportFailureAfterClose: { [weak listModel] error, count in
                    listModel?.reportCaptureFailure(error, count: count)
                },
                reportRecordWriteFailure: { [weak listModel] error in listModel?.lastError = error },
                captureRotationAngleOverride: uiTestCaptureRotationAngle,
                styleCenter: styleCenter)
        }
    }

    /// Where a camera photo is saved: the record's album (PRD 2.0 FR-20.4).
    /// Debug UI tests with the in-memory library (`-UITestRecordPhotos`)
    /// add it to that library instead, dated `DAYSCAM_FAKE_TODAY`, so the
    /// wall shows it without touching the real one (#621).
    private static func cameraSave(library: any RecordAlbumLibrary) -> CameraScreenModel.Save {
        #if DEBUG
        if let fake = library as? FakeRecordAlbumLibrary,
           ProcessInfo.processInfo.arguments.contains("-UITestRecordPhotos") {
            var count = 0
            return { _, albumIdentifier, albumTitle, completion in
                count += 1
                let id = "uitest-capture-\(count)"
                fake.addAsset(FakeRecordAlbumLibrary.Asset(id: id, creationDate: DayCountCalculator().now()))
                Task { @MainActor in
                    if fake.status == .authorized,
                       let album = try? await fake.addAssets([id], albumIdentifier: albumIdentifier, albumTitle: albumTitle) {
                        completion(.success(RecordSaveOutcome(assetID: id, albumID: album)))
                    } else {
                        completion(.success(RecordSaveOutcome(assetID: id, albumID: nil)))
                    }
                }
            }
        }
        #endif
        return { image, albumIdentifier, albumTitle, completion in
            PhotoSaver().saveToRecordAlbum(image, albumIdentifier: albumIdentifier,
                                           albumTitle: albumTitle, completion: completion)
        }
    }

    /// UI tests pass `-UITestCaptureRotationAngle <0|90|180|270>` to pretend
    /// the phone is held that way (#572). Debug builds only.
    private static var uiTestCaptureRotationAngle: CGFloat? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-UITestCaptureRotationAngle"),
              arguments.indices.contains(flag + 1),
              let angle = Double(arguments[flag + 1]) else { return nil }
        return CGFloat(angle)
        #else
        return nil
        #endif
    }

    /// UI tests pass `-UITestSecondRecord <name>` to add a second record of
    /// that name, starting the same day as the first, when there is only
    /// one, for the camera's record switcher (#655). `-UITestRecordCount <n>`
    /// with it keeps adding records 「<name> 3」… until there are `n`.
    /// Debug builds only.
    private static func applyUITestSecondRecord(to profileStore: ProfileStore) {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-UITestSecondRecord"),
              arguments.indices.contains(flag + 1),
              profileStore.profiles.count == 1,
              let first = profileStore.profiles.first else { return }
        let name = arguments[flag + 1]
        _ = try? profileStore.add(CameraProfile(name: name, startDate: first.startDate))
        guard let countFlag = arguments.firstIndex(of: "-UITestRecordCount"),
              arguments.indices.contains(countFlag + 1),
              let count = Int(arguments[countFlag + 1]) else { return }
        while profileStore.profiles.count < min(count, ProfileStore.profileLimit) {
            let added = try? profileStore.add(CameraProfile(name: "\(name) \(profileStore.profiles.count + 1)",
                                                            startDate: first.startDate))
            if added == nil { break }
        }
        #endif
    }

    /// UI tests pass `-UITestFilmDate <corner>` (a `FilmDateCorner` raw value)
    /// to turn the film date on in that corner for every saved profile, the
    /// stand-in for the panel switch of TASK-152 (TASK-153). Debug builds only.
    private static func applyUITestFilmDate(to profileStore: ProfileStore) {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-UITestFilmDate"),
              arguments.indices.contains(flag + 1),
              let corner = FilmDateCorner(rawValue: arguments[flag + 1]) else { return }
        for var profile in profileStore.profiles {
            profile.showFilmDate = true
            profile.filmDateCorner = corner
            _ = try? profileStore.update(profile)
        }
        #endif
    }

    /// Debug builds only: a stand-in font library for UI tests (TASK-150).
    private static var uiTestFontLibrary: (any FontShellControlling)? {
        #if DEBUG
        return UITestFontLibrary.fromLaunchArguments(ProcessInfo.processInfo.arguments)
        #else
        return nil
        #endif
    }

    /// UI tests pass `-UITestFreshProfiles <name>` to start from an empty
    /// profile directory instead of the app's saved one (TASK-70). The same
    /// name reaches the same directory, so a test can relaunch and find its
    /// profile; different names stay apart. Debug builds only.
    private static var uiTestProfileDirectory: URL? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-UITestFreshProfiles"),
              arguments.indices.contains(flag + 1) else { return nil }
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("DaysCamUITest-\(arguments[flag + 1])", isDirectory: true)
        #else
        return nil
        #endif
    }
}
