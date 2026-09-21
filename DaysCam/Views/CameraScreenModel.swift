import Combine
import Foundation

/// Drives PRD S-1, the camera screen: camera lifecycle, permission/status
/// interpretation, and the profile-driven overlay (TASK-08). The
/// display-settings sheet and the profile switcher are layered on in later
/// tasks. `CameraScreen` only lays out whatever this model currently says —
/// see `docs/TASKS.md`'s note on why UI-level acceptance criteria live here
/// rather than in the view.
///
/// Like `ProfileListModel.adapting(to:)`, this is one of the boundary types
/// that does depend on `ProfileStore`'s concrete type — a screen-level model
/// has to be the place real services get wired together. It mirrors the
/// store's `@Published profiles`/`selectedProfileID` the same way that
/// adapter does.
@MainActor
final class CameraScreenModel: ObservableObject {
    let cameraService: CameraService
    private let profileStore: ProfileStore
    private let calendar: Calendar
    private let calculator: DayCountCalculator
    private let renderer: TemplateRenderer

    /// Mirrors `profileStore.profiles`. The caller (`DaysCamApp`) is expected
    /// to have already called `profileStore.load()` before building this
    /// model, so this starts non-empty (PRD §2.2/§4.3 guarantee at least one
    /// profile always exists).
    @Published private(set) var profiles: [CameraProfile] = []
    /// Mirrors `profileStore.selectedProfileID`.
    @Published private(set) var selectedProfileID: UUID?

    private var cancellables = Set<AnyCancellable>()

    init(cameraService: CameraService,
         profileStore: ProfileStore,
         calendar: Calendar = .current,
         calculator: DayCountCalculator = DayCountCalculator(),
         renderer: TemplateRenderer = TemplateRenderer()) {
        self.cameraService = cameraService
        self.profileStore = profileStore
        self.calendar = calendar
        self.calculator = calculator
        self.renderer = renderer
        self.profiles = profileStore.profiles
        self.selectedProfileID = profileStore.selectedProfileID
        bindToProfileStore()
    }

    private func bindToProfileStore() {
        profileStore.$profiles
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.profiles = $0 }
            .store(in: &cancellables)
        profileStore.$selectedProfileID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.selectedProfileID = $0 }
            .store(in: &cancellables)
    }

    /// Called when the screen appears. Permission is requested here, not at
    /// app launch (PRD §2.2).
    func onAppear() {
        cameraService.start()
    }

    /// Called when the screen disappears. Pairs with `onAppear` — per
    /// `CameraService.stop()`'s own doc comment, a screen that stops on
    /// backgrounding must call `onAppear` again on the way back.
    func onDisappear() {
        cameraService.stop()
    }

    func switchCamera() {
        cameraService.switchCamera()
    }

    /// The label the placeholder viewfinder shows in the simulator (PRD §2.4).
    static let simulatorPlaceholderText = "模擬器不支援拍照"

    /// Whether the viewfinder should show the simulator/placeholder
    /// background instead of a live preview (PRD §2.4).
    var showsPlaceholder: Bool {
        !cameraService.isCaptureSupported
    }

    /// Whether the shutter should be disabled right now.
    ///
    /// True whenever a live picture is not actually on screen: no capture
    /// support (simulator), permission not granted, or the session is not
    /// `.running`. TASK-10 wires the shutter's action itself; this only
    /// decides whether it may be tapped at all.
    var isShutterDisabled: Bool {
        !cameraService.isCaptureSupported
            || cameraService.permission.needsGuidance
            || cameraService.status != .running
    }

    /// A transient reason the viewfinder cannot show a live picture even
    /// though permission is fine — an interruption or a session failure
    /// (PRD §2.4). `nil` when nothing needs to be said (including the
    /// simulator, which has its own placeholder rather than this message).
    var statusMessage: String? {
        switch cameraService.status {
        case .interrupted, .unavailable(.sessionFailure), .unavailable(.noCaptureDevice):
            return "相機暫時無法使用"
        case .idle, .running, .unavailable(.simulator):
            return nil
        }
    }
}

// MARK: - Profile-driven overlay (TASK-08)

extension CameraScreenModel {
    /// The profile currently applied to the viewfinder, or `nil` only in the
    /// brief window before `profileStore.load()` has populated `profiles`
    /// (never observable once the app has actually launched, PRD FR-1.8).
    var selectedProfile: CameraProfile? {
        profiles.first { $0.id == selectedProfileID }
    }

    /// The overlay text for `selectedProfile` as of right now.
    ///
    /// Re-rendered on every access rather than cached, using
    /// `TemplateRenderer` directly — the same renderer TASK-10's shutter must
    /// call again at capture time (PRD §6.4), so the viewfinder is never the
    /// source of truth for what gets baked into the photo.
    var overlayText: String {
        guard let selectedProfile else { return "" }
        return renderer.render(profile: selectedProfile, capturedAt: calculator.now(), calendar: calendar)
    }

    /// The theme `selectedProfile` draws its overlay with.
    var overlayTheme: OverlayTheme {
        OverlayTheme.theme(for: selectedProfile?.themeID ?? .classicWhite)
    }

    /// The anchor point `selectedProfile` draws its overlay at.
    var overlayPosition: OverlayPosition {
        selectedProfile?.position ?? .bottomTrailing
    }
}
