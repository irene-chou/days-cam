import AVFoundation
import Combine
import Photos
import XCTest
@testable import DaysCam

/// A font library that records what the camera screen asks of it and lets a
/// test move font states by hand.
@MainActor
final class FakeShellFontLibrary: FontShellControlling {
    let objectWillChange = ObservableObjectPublisher()
    let downloadDidFinish = PassthroughSubject<OverlayFontID, Never>()
    private var states: [OverlayFontID: FontState]
    private(set) var downloads: [OverlayFontID] = []
    private(set) var prepared: [OverlayFontID] = []
    private(set) var launchPriorities: [OverlayFontID?] = []
    private(set) var cancelAllCount = 0
    /// How many times anyone asked for a font's state.
    private(set) var stateReadCount = 0

    init(_ states: [OverlayFontID: FontState] = [:]) {
        self.states = states
    }

    func state(for fontID: OverlayFontID) -> FontState {
        stateReadCount += 1
        return fontID == .pingFang ? .available : (states[fontID] ?? .notDownloaded)
    }

    /// Moves `fontID` to `state` the way `FontLibrary` does (announce, then change).
    func set(_ state: FontState, for fontID: OverlayFontID) {
        objectWillChange.send()
        states[fontID] = state
    }

    /// A download completing: `.available`, then `downloadDidFinish`.
    func finishDownload(_ fontID: OverlayFontID) {
        set(.available, for: fontID)
        downloadDidFinish.send(fontID)
    }

    func cancel(_ fontID: OverlayFontID) { set(.notDownloaded, for: fontID) }
    func delete(_ fontID: OverlayFontID) -> Bool { false }

    func download(_ fontID: OverlayFontID) -> Bool {
        downloads.append(fontID)
        set(.downloading(progress: 0), for: fontID)
        return true
    }

    /// Never answers, like a match that hangs.
    func prepare(_ fontID: OverlayFontID) async {
        prepared.append(fontID)
        try? await Task.sleep(nanoseconds: 30_000_000_000)
    }

    func prepareAtLaunch(priority: OverlayFontID?) async {
        launchPriorities.append(priority)
        try? await Task.sleep(nanoseconds: 30_000_000_000)
    }

    func cancelAllDownloads() {
        cancelAllCount += 1
        for (fontID, state) in states {
            if case .downloading = state { set(.failed(.other), for: fontID) }
        }
    }
}

/// TASK-35 acceptance 35.1 to 35.9a: what the camera screen does with the
/// font library (PRD 0.3 FR-5.14 to FR-5.16, FR-5.18, FR-16.6, FR-16.11,
/// FR-16.14).
@MainActor
final class CameraScreenModelFontTests: XCTestCase {
    private var directory = URL(fileURLWithPath: NSTemporaryDirectory())
    private var defaults = UserDefaults.standard
    private var suiteName = ""

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("CameraScreenModelFontTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "CameraScreenModelFontTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
        try super.tearDownWithError()
    }

    // MARK: - Doubles

    private final class StubAuthorizer: CameraAuthorizing {
        func authorizationStatus() -> AVAuthorizationStatus { .notDetermined }
        func requestAccess(completion: @escaping (Bool) -> Void) { completion(false) }
    }

    private final class EmptyDeviceProvider: CaptureDeviceProviding {
        func device(for facing: CameraFacing) -> AVCaptureDevice? { nil }
    }

    // MARK: - Helpers

    private struct Harness {
        let model: CameraScreenModel
        let store: ProfileStore
        let library: FakeShellFontLibrary
        let profileA: CameraProfile
        let profileB: CameraProfile
    }

    private func profile(_ name: String, font: OverlayFontID = .pingFang) -> CameraProfile {
        var profile = CameraProfile(name: name, startDate: DateFixture.components(2026, 1, 1))
        profile.style.fontID = font
        return profile
    }

    /// Two profiles, A selected.
    private func makeHarness(fontA: OverlayFontID = .pingFang,
                             fontB: OverlayFontID = .pingFang,
                             states: [OverlayFontID: FontState] = [:],
                             timeout: TimeInterval = 3,
                             bake: @escaping (UIImage, String, OverlayStyle, OverlayPlacement, ResolvedOverlayFont) -> UIImage? = { _, _, _, _, _ in UIImage() },
                             captureImage: ((FlashMode, @escaping (Result<UIImage, CameraCaptureError>) -> Void) -> Void)? = nil) throws -> Harness {
        let now = try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 8))
        let store = ProfileStore(directory: directory, calendar: DateFixture.taipei, now: { now }, defaults: defaults)
        let profileA = profile("A", font: fontA)
        let profileB = profile("B", font: fontB)
        _ = try store.add(profileA)
        _ = try store.add(profileB)
        store.select(id: profileA.id)
        let library = FakeShellFontLibrary(states)
        let service = CameraService(authorizer: StubAuthorizer(), deviceProvider: EmptyDeviceProvider(),
                                    flashCapabilityProvider: nil, isCaptureSupported: false)
        let model = CameraScreenModel(
            cameraService: service,
            profileStore: store,
            captureSettingsStore: CaptureSettingsStore(defaults: defaults),
            capturedPhotoStore: CapturedPhotoStore(directory: directory.appendingPathComponent("photos", isDirectory: true)),
            calendar: DateFixture.taipei,
            calculator: DayCountCalculator(calendar: DateFixture.taipei, now: { now }),
            crop: { image, _ in image },
            bake: bake,
            save: { _, completion in completion(.success("asset")) },
            captureImage: captureImage,
            scheduleToastDismiss: { _ in },
            makeThumbnailLibrary: { _ in EmptyThumbnailLibrary() },
            fontLibrary: library,
            fontPreparationTimeout: timeout,
            resolveFont: resolveWithStandIn)
        return Harness(model: model, store: store, library: library,
                       profileA: try XCTUnwrap(store.profiles.first { $0.id == profileA.id }),
                       profileB: try XCTUnwrap(store.profiles.first { $0.id == profileB.id }))
    }

    private final class EmptyThumbnailLibrary: GalleryLibrary {
        func readStatus() -> PHAuthorizationStatus { .denied }
        func requestReadAccess() async -> PHAuthorizationStatus { .denied }
        func latestVisiblePhotoIDs(limit: Int) -> [String] { [] }
        func photos() -> [GalleryPhoto] { [] }
        func deletePhoto(id: String) async -> Bool { false }
        func image(id: String, targetSize: CGSize) async -> UIImage? { nil }
    }

    /// Lets main-queue hops (store and library change delivery) run.
    private func settle() async {
        try? await Task.sleep(nanoseconds: 80_000_000)
    }

    private func storedFont(_ id: UUID, in store: ProfileStore) -> OverlayFontID? {
        store.profiles.first { $0.id == id }?.style.fontID
    }

    /// The catalog font the tests treat as downloaded, and the face standing
    /// in for it: none of the catalog's faces is installed on a simulator, so
    /// resolution maps this ID to a face that ships with iOS (the same
    /// stand-in TASK-32's tests use).
    private let font = OverlayFontID.huninn
    private let standInFace = "Georgia-Bold"

    private func loadableFont() throws -> OverlayFontID {
        XCTAssertNotNil(UIFont(name: standInFace, size: 20), "fixture sanity")
        return font
    }

    private var resolveWithStandIn: @MainActor (OverlayFontID, any FontAvailabilityProviding) -> ResolvedOverlayFont {
        let face = standInFace
        return { fontID, availability in
            guard fontID != .pingFang else { return .pingFang }
            return OverlayMetrics.resolvedFont(state: availability.state(for: fontID), postScriptName: face)
        }
    }

    // MARK: - 35.1, 35.2 shutter waits for a preparing font

    func testShutterWaitsWhileTheCurrentFontIsPreparingAndResumesWhenAvailable() throws {
        let harness = try makeHarness(fontA: .xingkai, states: [.xingkai: .preparing])
        XCTAssertTrue(harness.model.isWaitingForFont, "35.1")
        XCTAssertTrue(harness.model.isShutterDisabled, "35.1")

        harness.library.set(.available, for: .xingkai)
        XCTAssertFalse(harness.model.isWaitingForFont, "35.1")
    }

    func testAnotherProfilesPreparingFontDoesNotBlockTheShutter() throws {
        let harness = try makeHarness(fontB: .xingkai, states: [.xingkai: .preparing])
        XCTAssertFalse(harness.model.isWaitingForFont)
    }

    func testShutterResumesAfterThreeSecondsOfNoAnswerAndTheViewfinderUsesPingFang() async throws {
        let harness = try makeHarness(fontA: .xingkai, states: [.xingkai: .preparing], timeout: 0.1)
        XCTAssertTrue(harness.model.isWaitingForFont, "35.2: still waiting at first")

        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertFalse(harness.model.isWaitingForFont, "35.2")
        XCTAssertEqual(harness.model.overlayFont, .pingFang, "35.2")
    }

    func testLaunchPreparationPutsTheCurrentProfilesFontFirst() async throws {
        let harness = try makeHarness(fontA: .xingkai, states: [.xingkai: .preparing])
        let task = Task { await harness.model.prepareFontsAtLaunch() }
        await settle()
        task.cancel()
        XCTAssertEqual(harness.library.launchPriorities, [.xingkai], "FR-5.15")
    }

    // MARK: - FR-5.16 switching to a preparing profile

    func testSwitchingToAPreparingProfilePreparesItNowAndWaitsForItWithinTheTimeout() async throws {
        let harness = try makeHarness(fontB: .xingkai, states: [.xingkai: .preparing], timeout: 0.1)
        harness.model.selectProfile(id: harness.profileB.id)
        await settle()
        XCTAssertEqual(harness.library.prepared, [.xingkai], "FR-5.16")
        XCTAssertEqual(harness.model.selectedProfileID, harness.profileB.id)

        harness.model.selectProfile(id: harness.profileA.id)
        harness.model.selectProfile(id: harness.profileB.id)
        await settle()
        // The timer restarted from the switch, then runs out.
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertFalse(harness.model.isWaitingForFont, "FR-5.16: 3 seconds from the switch")
    }

    // MARK: - 35.3 re-download notice

    func testSwitchingToAnUnavailableFontProfileShowsTheNoticeOnceAtMost() async throws {
        let harness = try makeHarness(fontB: .xingkai, states: [.xingkai: .notDownloaded])
        harness.model.selectProfile(id: harness.profileB.id)
        await settle()
        XCTAssertEqual(harness.model.toastState?.message, "「行楷」需要重新下載，暫時用蘋方", "35.3")
        let shown = harness.model.toastState?.id

        harness.model.selectProfile(id: harness.profileA.id)
        await settle()
        harness.model.selectProfile(id: harness.profileB.id)
        await settle()
        harness.model.openOverlayPanel()
        XCTAssertEqual(harness.model.toastState?.id, shown, "35.3: the same launch shows it once")
    }

    func testOpeningThePanelOnAnUnavailableFontShowsTheNotice() throws {
        let harness = try makeHarness(fontA: .xingkai, states: [.xingkai: .failed(.other)])
        XCTAssertNil(harness.model.toastState)
        harness.model.openOverlayPanel()
        XCTAssertEqual(harness.model.toastState?.message, "「行楷」需要重新下載，暫時用蘋方", "FR-16.14")
    }

    func testNoNoticeForAvailablePreparingOrDownloadingFonts() throws {
        for state in [FontState.available, .preparing, .downloading(progress: 0.4)] {
            let harness = try makeHarness(fontA: .xingkai, states: [.xingkai: state])
            harness.model.openOverlayPanel()
            XCTAssertNil(harness.model.toastState, "\(state)")
        }
    }

    // MARK: - 35.4 the shutter fixes the font

    func testBakeGetsTheFontResolvedWhenTheShutterFiredEvenIfTheStateChangesAfter() async throws {
        let font = try loadableFont()
        let library = Box<FakeShellFontLibrary?>(nil)
        let readCountAfterContext = Box<Int?>(nil)
        let received = Box<ResolvedOverlayFont?>(nil)
        let baked = expectation(description: "baked")
        let harness = try makeHarness(
            fontA: font, states: [font: .available],
            bake: { _, _, _, _, resolved in
                received.value = resolved
                baked.fulfill()
                return UIImage()
            },
            captureImage: { _, completion in
                // The font disappears between the shutter and the bake.
                MainActor.assumeIsolated {
                    library.value?.set(.notDownloaded, for: font)
                    readCountAfterContext.value = library.value?.stateReadCount
                }
                completion(.success(UIImage()))
            })
        library.value = harness.library
        XCTAssertEqual(harness.model.overlayFont.postScriptName, standInFace, "fixture sanity")

        harness.model.beginCapture(profile: harness.profileA)
        await fulfillment(of: [baked], timeout: 3)

        XCTAssertEqual(received.value?.postScriptName, standInFace, "35.4: the font at the press")
        XCTAssertNotEqual(received.value, .pingFang, "35.4")
        await settle()
        XCTAssertEqual(harness.library.stateReadCount, readCountAfterContext.value,
                       "35.4: nothing reads availability after the shutter fired")
        XCTAssertEqual(harness.model.overlayFont, .pingFang, "the viewfinder follows the new state")
    }

    func testCaptureContextResolvesTheFontOnTheMainActorAtThatMoment() throws {
        let font = try loadableFont()
        let harness = try makeHarness(fontA: font, states: [font: .preparing])
        XCTAssertEqual(harness.model.captureContext(for: harness.profileA).font, .pingFang, "preparing → PingFang")
        harness.library.set(.available, for: font)
        XCTAssertEqual(harness.model.captureContext(for: harness.profileA).font.postScriptName, standInFace)
    }

    // MARK: - 35.4b viewfinder cache follows the font

    func testViewfinderPictureIsRedrawnWhenTheFontStateChangesBothWays() throws {
        let font = try loadableFont()
        let harness = try makeHarness(fontA: font, states: [font: .preparing])
        var drawnWith: [String] = []
        let cache = OverlayTextRenderCache { text, style, size, scale, resolved in
            drawnWith.append(resolved.postScriptName)
            return OverlayRenderer().renderText(text, style: style, fontSize: size, displayScale: scale, font: resolved)
        }
        let frame = CGSize(width: 300, height: 400)
        func picture() -> UIImage? {
            cache.image(text: "第 10 天", style: harness.model.overlayStyle, font: harness.model.overlayFont,
                        frameSize: frame, displayScale: 3)?.image
        }
        let preparing = picture()
        harness.library.set(.available, for: font)
        let available = picture()
        harness.library.set(.notDownloaded, for: font)
        let gone = picture()

        XCTAssertEqual(drawnWith, [FontCatalog.pingFangPostScriptName, standInFace, FontCatalog.pingFangPostScriptName],
                       "35.4b: PingFang → the font → PingFang")
        XCTAssertFalse(preparing === available, "35.4b")
        XCTAssertFalse(available === gone, "35.4b")
    }

    // MARK: - 35.4a background

    func testGoingToTheBackgroundCancelsAllDownloadsOnce() throws {
        let harness = try makeHarness()
        harness.model.sceneDidEnterBackground()
        XCTAssertEqual(harness.library.cancelAllCount, 1, "35.4a")
    }

    // MARK: - 35.6, 35.7, 35.9, 35.9a applyFont

    func testApplyFontDownloadsThenWritesTheProfileAndAnnouncesOnTheCameraScreenWhenTheListIsNotShown() async throws {
        let harness = try makeHarness(states: [.xingkai: .notDownloaded])
        harness.model.styleTabModel?.fontList.didTap(.xingkai)
        XCTAssertEqual(harness.library.downloads, [.xingkai], "35.6")
        XCTAssertEqual(storedFont(harness.profileA.id, in: harness.store), .pingFang, "35.6: nothing before the download ends")

        harness.library.finishDownload(.xingkai)
        XCTAssertEqual(storedFont(harness.profileA.id, in: harness.store), .xingkai, "35.6")
        XCTAssertEqual(harness.model.styleTabModel?.profile.style.fontID, .xingkai, "FR-5.18")
        XCTAssertEqual(harness.model.toastState?.message, "已套用「行楷」", "35.6")
    }

    func testApplyFontAnnouncesInTheOpenListWhenItIsOpen() throws {
        let harness = try makeHarness(states: [.xingkai: .notDownloaded])
        harness.model.styleTabModel?.fontList.listDidAppear()
        harness.model.applyFont(.xingkai, profileID: harness.profileA.id)
        harness.library.finishDownload(.xingkai)
        XCTAssertEqual(harness.model.styleTabModel?.fontLibraryModel?.toast?.text, "已套用「行楷」")
    }

    func testApplyFontWritesTheProfileThatStartedTheDownloadNotTheCurrentOne() async throws {
        let harness = try makeHarness(states: [.xingkai: .notDownloaded])
        harness.model.applyFont(.xingkai, profileID: harness.profileA.id)
        harness.model.selectProfile(id: harness.profileB.id)
        await settle()
        harness.library.finishDownload(.xingkai)

        XCTAssertEqual(storedFont(harness.profileA.id, in: harness.store), .xingkai, "35.7")
        XCTAssertEqual(storedFont(harness.profileB.id, in: harness.store), .pingFang, "35.7")
    }

    func testFailedSaveAfterTheDownloadKeepsTheErrorAndDoesNotAnnounceApplied() throws {
        let harness = try makeHarness(states: [.xingkai: .notDownloaded])
        harness.model.applyFont(.xingkai, profileID: harness.profileA.id)
        // Make the profile file unwritable so `ProfileStore.update` throws.
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
        harness.library.finishDownload(.xingkai)

        XCTAssertEqual(harness.model.toastState?.message, "無法儲存字型設定", "寫入失敗不可報成已套用")
        XCTAssertEqual(storedFont(harness.profileA.id, in: harness.store), .pingFang)
    }

    func testDownloadFinishingForADeletedProfileWritesNothing() throws {
        let harness = try makeHarness(states: [.xingkai: .notDownloaded])
        harness.model.applyFont(.xingkai, profileID: harness.profileB.id)
        try harness.store.delete(id: harness.profileB.id)
        harness.library.finishDownload(.xingkai)
        XCTAssertNil(storedFont(harness.profileB.id, in: harness.store), "A-8")
        XCTAssertEqual(storedFont(harness.profileA.id, in: harness.store), .pingFang)
    }

    func testApplyingAnAvailableFontClearsTheProfilesPendingDownload() async throws {
        let harness = try makeHarness(states: [.xingkai: .notDownloaded, .huninn: .available])
        harness.model.applyFont(.xingkai, profileID: harness.profileA.id)
        harness.model.applyFont(.huninn, profileID: harness.profileA.id)
        XCTAssertEqual(storedFont(harness.profileA.id, in: harness.store), .huninn)

        harness.library.finishDownload(.xingkai)
        XCTAssertEqual(storedFont(harness.profileA.id, in: harness.store), .huninn, "35.9")
        XCTAssertNil(harness.model.toastState, "35.9: nothing announced")
    }

    func testLastRequestForAProfileWins() throws {
        let harness = try makeHarness(states: [.xingkai: .notDownloaded, .songti: .notDownloaded])
        harness.model.applyFont(.xingkai, profileID: harness.profileA.id)
        harness.model.applyFont(.songti, profileID: harness.profileA.id)
        harness.library.finishDownload(.xingkai)
        XCTAssertEqual(storedFont(harness.profileA.id, in: harness.store), .pingFang, "FR-16.6: the replaced request is gone")
        harness.library.finishDownload(.songti)
        XCTAssertEqual(storedFont(harness.profileA.id, in: harness.store), .songti)
    }

    func testCancelledFailedOrInterruptedDownloadsDropTheirPendingApplication() async throws {
        let interruptions: [(String, (Harness) -> Void)] = [
            ("cancel", { $0.library.cancel(.xingkai) }),
            ("failure", { $0.library.set(.failed(.noNetwork), for: .xingkai) }),
            ("background", { $0.model.sceneDidEnterBackground() })
        ]
        for (name, interrupt) in interruptions {
            let harness = try makeHarness(states: [.xingkai: .notDownloaded])
            harness.model.applyFont(.xingkai, profileID: harness.profileA.id)
            interrupt(harness)
            await settle()
            // Downloaded again later, with no new request for profile A.
            harness.library.finishDownload(.xingkai)
            XCTAssertEqual(storedFont(harness.profileA.id, in: harness.store), .pingFang, "35.9a \(name)")
            XCTAssertNil(harness.model.toastState, "35.9a \(name)")
        }
    }

    // MARK: - 35.8 one write path

    func testAppliedFontSurvivesALaterColorEditInTheStyleTab() throws {
        let harness = try makeHarness(states: [.xingkai: .available])
        harness.model.applyFont(.xingkai, profileID: harness.profileA.id)
        harness.model.styleTabModel?.selectTextColor(OverlayStyle.swatches[2])

        let stored = try XCTUnwrap(harness.store.profiles.first { $0.id == harness.profileA.id })
        XCTAssertEqual(stored.style.fontID, .xingkai, "35.8")
        XCTAssertEqual(stored.style.textColor, OverlayStyle.swatches[2], "35.8")
    }

    func testReplaceFontOutsideTheTabsIsFollowedByTheStyleTabBeforeItsNextEdit() async throws {
        let harness = try makeHarness(fontA: .huninn, states: [.huninn: .available])
        XCTAssertEqual(harness.model.styleTabModel?.profile.style.fontID, .huninn)

        try harness.store.replaceFont(.huninn, with: .pingFang)
        await settle()
        harness.model.styleTabModel?.selectTextColor(OverlayStyle.swatches[3])

        let stored = try XCTUnwrap(harness.store.profiles.first { $0.id == harness.profileA.id })
        XCTAssertEqual(stored.style.fontID, .pingFang, "35.8: the old font is not written back")
        XCTAssertEqual(stored.style.textColor, OverlayStyle.swatches[3], "35.8")
    }

    func testStyleTabAndFontListShareTheScreensLibraryAndApplyPath() throws {
        let harness = try makeHarness(states: [.huninn: .available])
        harness.model.styleTabModel?.fontList.didTap(.huninn)
        XCTAssertEqual(storedFont(harness.profileA.id, in: harness.store), .huninn, "FR-5.18: the grid goes through applyFont")
    }
}

/// A mutable cell for values a test closure fills in.
private final class Box<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}
