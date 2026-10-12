import XCTest
@testable import DaysCam

/// The first-launch spotlight's state machine (TASK-96, #400): when it
/// starts (96.1, 96.7, 96.8), how it ends (96.3–96.5, 96.10), the launch
/// arguments (96.13) and the seen flag staying out of the profiles (96.12).
@MainActor
final class OnboardingSpotlightModelTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "OnboardingSpotlightModelTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeModel(arguments: [String] = []) -> OnboardingSpotlightModel {
        OnboardingSpotlightModel(defaults: defaults, arguments: arguments)
    }

    // MARK: - Fresh-install decision (96.16, 96.17)

    func testFreshInstallBecomesPendingAndStartsOncePermissionIsAnswered() {
        let model = makeModel()
        XCTAssertNil(model.state, "no record before the decision")
        model.decideIfNeeded(isFreshInstall: true)
        XCTAssertEqual(model.state, .pending)
        model.cameraPermissionDidChange(.notDetermined)
        XCTAssertNil(model.step, "96.8 nothing while the system prompt is up")
        model.cameraPermissionDidChange(.authorized)
        XCTAssertEqual(model.step, .startDate, "96.1")
    }

    func testExistingInstallBecomesDoneAndNeverShows() {
        let model = makeModel()
        model.decideIfNeeded(isFreshInstall: false)
        XCTAssertEqual(model.state, .done, "96.16／96.17 profiles already there, or re-seeded after corruption")
        model.cameraPermissionDidChange(.authorized)
        XCTAssertNil(model.step)
        XCTAssertTrue(model.isDone)
    }

    func testTheDecisionIsMadeOnlyOnce() {
        let model = makeModel()
        model.decideIfNeeded(isFreshInstall: true)
        model.decideIfNeeded(isFreshInstall: false)
        XCTAssertEqual(model.state, .pending, "a later launch cannot flip pending to done")
        defaults.removeObject(forKey: OnboardingSpotlightModel.stateKey)
        let other = makeModel()
        other.decideIfNeeded(isFreshInstall: false)
        other.decideIfNeeded(isFreshInstall: true)
        XCTAssertEqual(other.state, .done)
    }

    func testNothingStartsWithoutARecord() {
        let model = makeModel()
        model.cameraPermissionDidChange(.authorized)
        XCTAssertNil(model.step, "no decision yet → nothing to show")
    }

    // MARK: - Starting (96.1, 96.8)

    private func makePendingModel(arguments: [String] = []) -> OnboardingSpotlightModel {
        let model = makeModel(arguments: arguments)
        model.decideIfNeeded(isFreshInstall: true)
        return model
    }

    func testStartsAtStepOneOncePermissionIsAnsweredEitherWay() {
        for permission in [CameraPermission.authorized, .denied, .restricted] {
            defaults.removeObject(forKey: OnboardingSpotlightModel.stateKey)
            let model = makePendingModel()
            model.cameraPermissionDidChange(.notDetermined)
            model.cameraPermissionDidChange(permission)
            XCTAssertEqual(model.step, .startDate, "96.1／96.8 starts after \(permission), granted or not")
        }
    }

    func testPermissionChangesDoNotRestartOrSkipAStep() {
        let model = makePendingModel()
        model.cameraPermissionDidChange(.authorized)
        model.advance()
        model.cameraPermissionDidChange(.authorized)
        XCTAssertEqual(model.step, .overlayStyle, "a repeated permission value leaves step 2 alone")
    }

    // MARK: - Steps and ending (96.2, 96.3)

    func testNextThenGotItEndsTheTourAndRecordsIt() {
        let model = makePendingModel()
        model.cameraPermissionDidChange(.authorized)
        model.advance()
        XCTAssertEqual(model.step, .overlayStyle, "96.2")
        XCTAssertEqual(model.state, .pending, "下一步 alone does not record it (96.7)")
        model.advance()
        XCTAssertNil(model.step, "96.3 知道了 ends it")
        XCTAssertEqual(model.state, .done)
        XCTAssertEqual(defaults.string(forKey: OnboardingSpotlightModel.stateKey), "done")
    }

    func testADoneTourNeverShowsAgain() {
        let first = makePendingModel()
        first.cameraPermissionDidChange(.authorized)
        first.advance()
        first.advance()
        let relaunch = makeModel()
        relaunch.decideIfNeeded(isFreshInstall: false)
        relaunch.cameraPermissionDidChange(.authorized)
        XCTAssertNil(relaunch.step, "96.3 not again after a relaunch")
    }

    func testQuittingDuringStepOneShowsStepOneAgain() {
        let first = makePendingModel()
        first.cameraPermissionDidChange(.authorized)
        XCTAssertEqual(first.step, .startDate)
        // No advance, no finish: the app is killed here. Next launch the file
        // exists, so the store would not report a fresh install — but the
        // record is already `pending`, so that no longer matters.
        let relaunch = makeModel()
        relaunch.decideIfNeeded(isFreshInstall: false)
        relaunch.cameraPermissionDidChange(.authorized)
        XCTAssertEqual(relaunch.step, .startDate, "96.7 from step 1 again")
    }

    // MARK: - Target taps and escape (96.4, 96.5, 96.10)

    func testTappingTheTargetEndsTheTourAtEitherStep() {
        let stepOne = makePendingModel()
        stepOne.cameraPermissionDidChange(.authorized)
        stepOne.targetTapped()
        XCTAssertNil(stepOne.step, "96.4 no step 2 after tapping the chip")
        XCTAssertTrue(stepOne.isDone)

        let twoDefaults = UserDefaults(suiteName: "\(suiteName!).two")!
        defer { twoDefaults.removePersistentDomain(forName: "\(suiteName!).two") }
        let stepTwo = OnboardingSpotlightModel(defaults: twoDefaults, arguments: [])
        stepTwo.decideIfNeeded(isFreshInstall: true)
        stepTwo.cameraPermissionDidChange(.authorized)
        stepTwo.advance()
        stepTwo.targetTapped()
        XCTAssertNil(stepTwo.step, "96.5")
        XCTAssertTrue(stepTwo.isDone)
    }

    func testEscapeEndsTheTourAndRecordsIt() {
        let model = makePendingModel()
        model.cameraPermissionDidChange(.authorized)
        model.finish()
        XCTAssertNil(model.step, "96.10 escape")
        XCTAssertTrue(model.isDone)
    }

    func testFinishWhileNotShowingDoesNotRecordAnything() {
        let model = makePendingModel()
        model.finish()
        model.advance()
        XCTAssertEqual(model.state, .pending)
        XCTAssertNil(model.step)
    }

    // MARK: - Launch arguments (96.13)

    func testSkipArgumentHidesTheTourAndWritesNothing() {
        let model = makeModel(arguments: ["-UITestSkipOnboarding"])
        model.decideIfNeeded(isFreshInstall: true)
        XCTAssertNil(model.state, "a skipped launch leaves the record alone")
        model.cameraPermissionDidChange(.authorized)
        XCTAssertNil(model.step)
    }

    func testResetArgumentForcesPendingSoTheTourShowsAgain() {
        defaults.set("done", forKey: OnboardingSpotlightModel.stateKey)
        let model = makeModel(arguments: ["-UITestResetOnboarding"])
        XCTAssertEqual(model.state, .pending)
        model.decideIfNeeded(isFreshInstall: false)
        XCTAssertEqual(model.state, .pending, "the forced record is not re-decided")
        model.cameraPermissionDidChange(.authorized)
        XCTAssertEqual(model.step, .startDate)
    }

    // MARK: - Copy (#400 文案定稿)

    func testCopyIsTheFinalWording() {
        XCTAssertEqual(OnboardingSpotlightModel.Step.startDate.stepLabel, "1 / 2")
        XCTAssertEqual(OnboardingSpotlightModel.Step.startDate.title, "設定起始日")
        XCTAssertEqual(OnboardingSpotlightModel.Step.startDate.message, "點這裡管理設定檔，設定不同的起始日，例如寶寶生日。")
        XCTAssertEqual(OnboardingSpotlightModel.Step.startDate.buttonTitle, "下一步")
        XCTAssertEqual(OnboardingSpotlightModel.Step.overlayStyle.stepLabel, "2 / 2")
        XCTAssertEqual(OnboardingSpotlightModel.Step.overlayStyle.title, "設定疊字樣式")
        XCTAssertEqual(OnboardingSpotlightModel.Step.overlayStyle.message, "點這裡調整照片上的文字：字型、顏色、位置等等。")
        XCTAssertEqual(OnboardingSpotlightModel.Step.overlayStyle.buttonTitle, "知道了")
        XCTAssertEqual(OnboardingSpotlightModel.Step.startDate.target, .profileChip)
        XCTAssertEqual(OnboardingSpotlightModel.Step.overlayStyle.target, .overlayPanelButton)
        XCTAssertNil(OnboardingSpotlightModel.Step.startDate.secondaryTarget)
        XCTAssertEqual(OnboardingSpotlightModel.Step.overlayStyle.secondaryTarget, .overlayText, "step 2 B lights the text too")
    }

    // MARK: - Profiles untouched (96.12)

    func testTheSeenFlagNeverReachesTheProfileFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProfileStore(directory: directory, scheduler: ProfileStore.immediateScheduler)
        store.load()
        let before = try Data(contentsOf: store.fileURL)

        let model = makeModel()
        model.decideIfNeeded(isFreshInstall: store.didSeedFreshInstall)
        model.cameraPermissionDidChange(.authorized)
        model.advance()
        model.advance()

        let after = try Data(contentsOf: store.fileURL)
        XCTAssertEqual(before, after, "96.12 profiles.json is byte-for-byte unchanged")
        XCTAssertFalse(String(decoding: after, as: UTF8.self).contains(OnboardingSpotlightModel.stateKey))
        XCTAssertFalse(String(decoding: after, as: UTF8.self).contains("pending"))
        let reloaded = ProfileStore(directory: directory, scheduler: ProfileStore.immediateScheduler)
        XCTAssertEqual(reloaded.load().count, store.profiles.count)
    }
}

/// The hole and bubble placement rules (#400 外觀), independent of the view.
final class OnboardingSpotlightGeometryTests: XCTestCase {
    private let screen = CGSize(width: 393, height: 852)
    private let button = CGRect(x: 319, y: 760, width: 44, height: 44)
    private let text = CGRect(x: 280, y: 580, width: 90, height: 34)

    func testStepOneHoleIsACapsuleAroundTheChipAndBubbleSitsBelow() {
        let chip = CGRect(x: 150, y: 70, width: 92, height: 34)
        let geometry = OnboardingSpotlightGeometry(step: .startDate, target: chip, screenSize: screen, bubbleHeight: 120)
        XCTAssertEqual(geometry.hole, chip.insetBy(dx: -3, dy: -3))
        XCTAssertNil(geometry.secondaryHole, "step 1 has one hole")
        XCTAssertEqual(geometry.arrowEdge, .top)
        XCTAssertEqual(geometry.bubble.minY, geometry.hole.maxY + 6 + 8)
        XCTAssertEqual(geometry.bubble.midX, chip.midX, accuracy: 0.5, "centered under the chip")
        XCTAssertEqual(geometry.bubble.width, 300)
        XCTAssertEqual(geometry.arrowOffset, chip.midX - geometry.bubble.minX, accuracy: 0.5)
    }

    func testStepTwoHasACircleAndATextHoleAndTheBubbleSitsToTheLeft() {
        let geometry = OnboardingSpotlightGeometry(step: .overlayStyle, target: button, secondaryTarget: text,
                                                   screenSize: screen, bubbleHeight: 120)
        XCTAssertEqual(geometry.hole.size, CGSize(width: 44, height: 44))
        XCTAssertEqual(geometry.hole.midX, button.midX)
        XCTAssertEqual(geometry.hole.midY, button.midY)
        XCTAssertEqual(geometry.secondaryHole, text.insetBy(dx: -6, dy: -6), "96.2 the text hole is the text plus 6pt")
        XCTAssertEqual(geometry.arrowEdge, .trailing, "96.2 arrow points right at the button")
        XCTAssertEqual(geometry.bubble.maxX, geometry.hole.minX - 6 - 8, accuracy: 0.5, "left of the button")
        // Centered on the button, but never below the screen's bottom margin:
        // here the 120pt bubble would reach 842 > 836, so it sits 6pt higher.
        XCTAssertEqual(geometry.bubble.maxY, screen.height - 16, accuracy: 0.5, "kept inside the bottom margin")
        XCTAssertEqual(geometry.bubble.midY, button.midY - 6, accuracy: 0.5)
        let roomy = OnboardingSpotlightGeometry(step: .overlayStyle, target: button, secondaryTarget: text,
                                                screenSize: CGSize(width: 393, height: 900), bubbleHeight: 120)
        XCTAssertEqual(roomy.bubble.midY, button.midY, accuracy: 0.5, "vertically centered on the button when there is room")
        XCTAssertEqual(geometry.bubble.width, min(300, geometry.hole.minX - 14 - 16), accuracy: 0.5)
        XCTAssertEqual(geometry.arrowOffset, button.midY - geometry.bubble.minY, accuracy: 0.5)
        XCTAssertFalse(geometry.bubble.intersects(geometry.secondaryHole!), "96.2 never covers the text hole")
    }

    func testStepTwoBubbleMovesDownRatherThanCoverTheText() {
        // A text block sitting low and left enough to be under the bubble.
        let lowText = CGRect(x: 60, y: 700, width: 90, height: 34)
        let geometry = OnboardingSpotlightGeometry(step: .overlayStyle, target: button, secondaryTarget: lowText,
                                                   screenSize: CGSize(width: 393, height: 1000), bubbleHeight: 120)
        XCTAssertEqual(geometry.arrowEdge, .trailing)
        XCTAssertEqual(geometry.bubble.minY, lowText.maxY + 6 + 6, accuracy: 0.5, "pushed below the text hole")
        XCTAssertFalse(geometry.bubble.intersects(geometry.secondaryHole!))
    }

    func testStepTwoFallsBackAboveTheButtonWhenTooNarrow() {
        // The button far left leaves no room for a bubble beside it.
        let leftButton = CGRect(x: 100, y: 760, width: 44, height: 44)
        let geometry = OnboardingSpotlightGeometry(step: .overlayStyle, target: leftButton, secondaryTarget: text,
                                                   screenSize: screen, bubbleHeight: 120)
        XCTAssertEqual(geometry.arrowEdge, .bottom, "96.9 narrow → above the button")
        XCTAssertEqual(geometry.bubble.maxY, min(geometry.hole.minY, geometry.secondaryHole!.minY) - 14, accuracy: 0.5,
                       "above the button and the text hole")
        XCTAssertFalse(geometry.bubble.intersects(geometry.secondaryHole!))
        XCTAssertGreaterThanOrEqual(geometry.bubble.minX, 16)
        XCTAssertLessThanOrEqual(geometry.bubble.maxX, screen.width - 16)
    }

    func testStepTwoFallsBackAboveWhenTheTextLeavesNoRoomBelow() {
        // Text hole so low the pushed-down bubble would leave the screen.
        let lowText = CGRect(x: 60, y: 760, width: 200, height: 34)
        let geometry = OnboardingSpotlightGeometry(step: .overlayStyle, target: button, secondaryTarget: lowText,
                                                   screenSize: screen, bubbleHeight: 120)
        XCTAssertEqual(geometry.arrowEdge, .bottom)
        XCTAssertLessThanOrEqual(geometry.bubble.maxY, geometry.secondaryHole!.minY - 14 + 0.5)
    }

    func testStepTwoWithoutATextFrameHasOneHole() {
        let geometry = OnboardingSpotlightGeometry(step: .overlayStyle, target: button, secondaryTarget: nil,
                                                   screenSize: screen, bubbleHeight: 120)
        XCTAssertNil(geometry.secondaryHole)
        XCTAssertEqual(geometry.arrowEdge, .trailing)
        let empty = OnboardingSpotlightGeometry(step: .overlayStyle, target: button, secondaryTarget: .zero,
                                                screenSize: screen, bubbleHeight: 120)
        XCTAssertNil(empty.secondaryHole, "an empty frame is treated as unknown")
    }

    func testBubbleNeverLeavesASmallScreenAndGrowsWithItsText() {
        let small = CGSize(width: 320, height: 568)
        let chip = CGRect(x: 110, y: 40, width: 100, height: 34)
        let tall = OnboardingSpotlightGeometry(step: .startDate, target: chip, screenSize: small, bubbleHeight: 240)
        XCTAssertEqual(tall.bubble.width, 320 - 32, "96.9 fits a narrow screen")
        XCTAssertGreaterThanOrEqual(tall.bubble.minX, 16)
        XCTAssertLessThanOrEqual(tall.bubble.maxX, 320 - 16)
        XCTAssertEqual(tall.bubble.height, 240, "the height follows the measured text")

        let seButton = CGRect(x: 260, y: 500, width: 44, height: 44)
        let seText = CGRect(x: 220, y: 400, width: 80, height: 30)
        let beside = OnboardingSpotlightGeometry(step: .overlayStyle, target: seButton, secondaryTarget: seText,
                                                 screenSize: small, bubbleHeight: 240)
        XCTAssertGreaterThanOrEqual(beside.bubble.minX, 16)
        XCTAssertLessThanOrEqual(beside.bubble.maxY, small.height - 16 + 0.5, "kept above the bottom margin")
        XCTAssertFalse(beside.bubble.intersects(beside.secondaryHole!))
    }

    func testMaskPathHasBothHolesCutOut() {
        let hole = CGRect(x: 100, y: 100, width: 44, height: 44)
        let textHole = CGRect(x: 200, y: 300, width: 100, height: 40)
        let path = SpotlightMaskShape(primary: hole, secondary: textHole).path(in: CGRect(origin: .zero, size: screen)).cgPath
        XCTAssertTrue(path.contains(CGPoint(x: 10, y: 10), using: .evenOdd), "outside the holes the mask is filled")
        XCTAssertFalse(path.contains(CGPoint(x: 122, y: 122), using: .evenOdd), "the circle's center is not filled")
        XCTAssertFalse(path.contains(CGPoint(x: 102, y: 122), using: .evenOdd), "the circle reaches its edge")
        XCTAssertTrue(path.contains(CGPoint(x: 101, y: 101), using: .evenOdd), "the corner outside the circle is masked")
        XCTAssertFalse(path.contains(CGPoint(x: 250, y: 320), using: .evenOdd), "the text hole is open")
        XCTAssertTrue(path.contains(CGPoint(x: 200.5, y: 300.5), using: .evenOdd), "the text hole's corner is rounded (r 8)")
        XCTAssertFalse(path.contains(CGPoint(x: 210, y: 302), using: .evenOdd))

        let oneHole = SpotlightMaskShape(primary: hole, secondary: CGRect(x: 122, y: 122, width: 0, height: 0))
            .path(in: CGRect(origin: .zero, size: screen)).cgPath
        XCTAssertTrue(oneHole.contains(CGPoint(x: 250, y: 320), using: .evenOdd), "an empty secondary draws nothing")
    }
}

/// The screen model's side (TASK-96): a highlighted target's tap ends the
/// tour *and* does what the button does (96.4, 96.5).
@MainActor
final class CameraScreenModelOnboardingTests: XCTestCase {
    private var directory: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        suiteName = "CameraScreenModelOnboardingTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func makeModel() -> CameraScreenModel {
        let store = ProfileStore(directory: directory, scheduler: ProfileStore.immediateScheduler)
        store.load()
        return CameraScreenModel(cameraService: CameraService(isCaptureSupported: false),
                                 profileStore: store,
                                 captureSettingsStore: CaptureSettingsStore(defaults: defaults),
                                 capturedPhotoStore: CapturedPhotoStore(directory: directory.appendingPathComponent("photos", isDirectory: true)),
                                 onboarding: OnboardingSpotlightModel(defaults: defaults, arguments: []))
    }

    func testStartsOnceTheSimulatorPermissionResolves() {
        let model = makeModel()
        XCTAssertEqual(model.onboarding.state, .pending, "96.16 a store that seeded with no file is a fresh install")
        XCTAssertNil(model.onboarding.step, "nothing before the screen appears")
        model.onAppear()
        let started = expectation(description: "step 1")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { started.fulfill() }
        wait(for: [started], timeout: 2)
        XCTAssertEqual(model.onboarding.step, .startDate, "96.1／96.8 after the (simulator) permission is answered")
    }

    /// 96.16／96.17: a store that found profiles, or re-seeded after
    /// corruption, is not a fresh install — the record goes straight to done.
    func testExistingProfilesOrCorruptionNeverShowTheTour() throws {
        let seeded = ProfileStore(directory: directory, scheduler: ProfileStore.immediateScheduler)
        seeded.load()
        let existing = makeModel()
        XCTAssertEqual(existing.onboarding.state, .done, "96.16 profiles already there")
        existing.onAppear()
        XCTAssertNil(existing.onboarding.step)

        try FileManager.default.removeItem(at: seeded.fileURL)
        try XCTUnwrap("這不是 JSON".data(using: .utf8)).write(to: seeded.fileURL, options: [.atomic])
        defaults.removeObject(forKey: OnboardingSpotlightModel.stateKey)
        let corrupt = makeModel()
        XCTAssertEqual(corrupt.onboarding.state, .done, "96.17 corruption is an existing install")
    }

    func testChipTapEndsTheTourAndOpensProfiles() {
        let model = makeModel()
        model.onboarding.cameraPermissionDidChange(.authorized)
        model.onboardingTargetTapped(.profileChip)
        XCTAssertNil(model.onboarding.step, "96.4")
        XCTAssertTrue(model.onboarding.isDone)
        XCTAssertTrue(model.isProfileManagerPresented, "96.4 the sheet opens as usual")
        XCTAssertFalse(model.panelModel.isOpen)
    }

    func testPanelButtonTapEndsTheTourAndOpensThePanel() {
        let model = makeModel()
        model.onboarding.cameraPermissionDidChange(.authorized)
        model.onboarding.advance()
        model.onboardingTargetTapped(.overlayPanelButton)
        XCTAssertNil(model.onboarding.step, "96.5")
        XCTAssertTrue(model.onboarding.isDone)
        XCTAssertTrue(model.panelModel.isOpen, "96.5 the panel opens as usual")
        XCTAssertFalse(model.isProfileManagerPresented)
    }
}
