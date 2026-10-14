import AVFoundation
import Combine
import SwiftUI

/// Hands the viewfinder's preview layer to the model that must convert touch
/// points with it. The layer belongs to `CameraPreviewContainerView`; this is
/// the only way out of it.
final class PreviewLayerBridge {
    weak var layer: AVCaptureVideoPreviewLayer?

    /// The 0...1 device point under `layerPoint`, with the front camera's
    /// mirroring and the crop of `.resizeAspectFill` accounted for by the
    /// layer itself. Nil without a layer or when the result is not a number.
    func devicePoint(forLayerPoint layerPoint: CGPoint) -> CGPoint? {
        guard let layer else { return nil }
        let point = layer.captureDevicePointConverted(fromLayerPoint: layerPoint)
        return point.x.isFinite && point.y.isFinite ? point : nil
    }
}

/// What the focus model asks of the camera (issue #303). Real ones forward to
/// `CameraService`; the UI tests pass fakes.
struct FocusExposureActions {
    /// Both return the request's id, 0 for none.
    var focusAndExpose: (CGPoint) -> Int
    var lock: (CGPoint) -> Int
    var setBias: (Float) -> Void
    /// Like `setBias`, but tagged with the focus request the drag belongs to,
    /// so the camera can refuse a bias that arrives after a newer tap
    /// (TASK-88). Preferred over `setBias` when set.
    var setBiasForRequest: ((Float, Int) -> Void)?
    /// The exposure bias range the live device accepts.
    var deviceBiasRange: () -> ClosedRange<Float>
}

/// Tap-to-focus, drag-for-exposure and hold-to-lock on the viewfinder
/// (issue #303). Owns the gesture state machine and what the reticle, the sun
/// and the lock label show; `CameraService` stays the only thing that touches
/// the device.
///
/// Truth comes from the service: the lock label follows `FocusExposureState`
/// alone and is never shown on a request's say-so, and a bias that is only
/// requested is shown until the service answers or reports a failure, then
/// reverts to what the device really has.
@MainActor
final class ViewfinderFocusModel: ObservableObject {
    /// Where the focus square is, in the viewfinder's own coordinates.
    struct Reticle: Equatable {
        let id: Int
        let layerPoint: CGPoint
    }

    @Published private(set) var reticle: Reticle?
    /// True once the reticle has faded to half opacity.
    @Published private(set) var isReticleDimmed = false
    /// The exposure compensation to show, in EV.
    @Published private(set) var displayedBias: Float = 0
    /// Whether the device really holds AE/AF locked.
    @Published private(set) var isLocked = false

    /// Press this long without moving to lock.
    let holdDuration: Duration
    /// How long the reticle stays bright, then dims.
    let dimDelay: Duration
    /// After dimming, how long a reticle with nothing to show lingers.
    let hideDelay: Duration

    /// Touch travel that turns a press into a drag.
    static let dragSlop: CGFloat = 10
    /// Vertical points that make one EV.
    static let pointsPerEV: CGFloat = 80
    /// Smallest bias step sent to the camera.
    static let biasStep: Float = 0.1
    /// How long after a tap closed the panel or a capsule a touch that only
    /// then begins still counts as that tap (#541).
    static let consumedTapWindow: Duration = .milliseconds(300)

    let previewBridge = PreviewLayerBridge()

    private let actions: FocusExposureActions
    private let convert: (CGPoint, CGSize) -> CGPoint?
    /// Whether a new touch may start a focus gesture (panel closed, no
    /// capsule open, a live camera).
    var canAcceptGesture: () -> Bool = { true }
    /// Whether a pinch is under way.
    var isPinching: () -> Bool = { false }
    /// Whether a touch that begins at this point belongs to something else —
    /// the overlay text's own tap (TASK-105) — and must be ignored outright.
    var shouldIgnoreTouch: (CGPoint) -> Bool = { _ in false }

    private var serviceState = FocusExposureState.initial
    private var pendingBias: Float?
    /// A new tap asked the camera to unlock; the lock label stays off until
    /// the camera answers.
    private var isLockClearPending = false
    private var lastSentBias: Float?
    private var nextReticleID = 0
    /// The id the camera gave the latest focus or lock request.
    private var latestFocusRequestID = 0
    private var touch: Touch?
    /// Until when a touch that begins is the tap that just closed the panel
    /// or a capsule (`ignoreTouchConsumedByTap`).
    private var consumedTapDeadline: ContinuousClock.Instant?
    private var holdTask: Task<Void, Never>?
    private var dimTask: Task<Void, Never>?
    private var viewfinderSize = CGSize.zero

    private struct Touch {
        enum Mode { case undecided, adjusting, locked, ignored }
        let start: CGPoint
        var mode = Mode.undecided
        var anchorY: CGFloat = 0
        var anchorBias: Float = 0
    }

    init(actions: FocusExposureActions,
         convert: ((CGPoint, CGSize) -> CGPoint?)? = nil,
         holdDuration: Duration = .milliseconds(500),
         dimDelay: Duration = .milliseconds(1500),
         hideDelay: Duration = .seconds(2)) {
        self.actions = actions
        self.convert = convert ?? { [previewBridge] point, _ in previewBridge.devicePoint(forLayerPoint: point) }
        self.holdDuration = holdDuration
        self.dimDelay = dimDelay
        self.hideDelay = hideDelay
    }

    deinit {
        holdTask?.cancel()
        dimTask?.cancel()
    }

    // MARK: Range and text

    /// `deviceRange` narrowed to ±2 EV, the range the UI offers. Always
    /// non-empty and always inside both.
    nonisolated static func effectiveBiasRange(deviceRange: ClosedRange<Float>) -> ClosedRange<Float> {
        CameraService.exposureBiasRange(minimum: deviceRange.lowerBound, maximum: deviceRange.upperBound)
    }

    /// `bias` snapped to `biasStep` and held inside the effective range.
    nonisolated static func clampedBias(_ bias: Float, deviceRange: ClosedRange<Float>) -> Float {
        let range = effectiveBiasRange(deviceRange: deviceRange)
        let snapped = (bias / biasStep).rounded() * biasStep
        return min(max(snapped, range.lowerBound), range.upperBound)
    }

    /// "+0.7" / "-1.3", or nil at zero where nothing is shown.
    nonisolated static func biasText(for bias: Float) -> String? {
        guard abs(bias) >= 0.05 else { return nil }
        return String(format: "%+.1f", Double(bias))
    }

    // MARK: Touch

    /// One update of the finger that started at `startLocation`; `location`
    /// is where it is now. All in the viewfinder's coordinates.
    func touchChanged(startLocation: CGPoint, location: CGPoint, viewfinderSize: CGSize) {
        self.viewfinderSize = viewfinderSize
        // `onEnded` is skipped when SwiftUI cancels a gesture; the view then
        // calls `touchCancelled()`. A touch that starts somewhere else than
        // the one we hold is a new one even if that signal was missed.
        if let held = touch, held.start != startLocation { touchCancelled() }
        if touch == nil { beginTouch(at: startLocation) }
        guard var current = touch else { return }
        if isPinching() {
            invalidateTouch()
            return
        }
        guard current.mode == .undecided || current.mode == .adjusting else { return }
        if current.mode == .undecided {
            let distance = hypot(location.x - current.start.x, location.y - current.start.y)
            guard distance > Self.dragSlop else { return }
            holdTask?.cancel()
            let vertical = abs(location.y - current.start.y) > abs(location.x - current.start.x)
            guard vertical, reticle != nil else {
                current.mode = .ignored
                touch = current
                return
            }
            current.mode = .adjusting
            current.anchorY = location.y
            current.anchorBias = displayedBias
            touch = current
            keepReticleBright()
            return
        }
        let raw = current.anchorBias - Float((location.y - current.anchorY) / Self.pointsPerEV)
        requestBias(raw)
        keepReticleBright()
    }

    /// The touch is over without having ended: SwiftUI cancelled the gesture
    /// (a system gesture, the app going to the background). Does nothing a
    /// lift would, such as a tap.
    func touchCancelled() {
        holdTask?.cancel()
        holdTask = nil
        touch = nil
    }

    /// The viewfinder's own tap just closed the panel or a capsule, so that
    /// touch must not focus as well (73.6). Through iOS 26 the focus drag has
    /// already begun by then and is dropped here; from iOS 27 the tap is
    /// recognized first and the drag's first update only follows, so the
    /// touch that begins right after is dropped instead (#541).
    func ignoreTouchConsumedByTap() {
        if touch != nil {
            invalidateTouch()
        } else {
            consumedTapDeadline = .now + Self.consumedTapWindow
        }
    }

    /// The finger lifted. A press that never moved and was not held is a tap.
    func touchEnded() {
        guard let finished = touch else { return }
        touch = nil
        holdTask?.cancel()
        holdTask = nil
        guard finished.mode == .undecided, !isPinching() else { return }
        focus(at: finished.start, lock: false)
    }

    private func beginTouch(at start: CGPoint) {
        holdTask?.cancel()
        let consumedByTap = consumedTapDeadline.map { ContinuousClock.now < $0 } ?? false
        consumedTapDeadline = nil
        guard !consumedByTap, canAcceptGesture(), !isPinching(), !shouldIgnoreTouch(start) else {
            touch = Touch(start: start, mode: .ignored)
            return
        }
        touch = Touch(start: start)
        holdTask = Task { [weak self, holdDuration] in
            try? await Task.sleep(for: holdDuration)
            guard !Task.isCancelled else { return }
            self?.holdElapsed()
        }
    }

    private func invalidateTouch() {
        holdTask?.cancel()
        holdTask = nil
        touch?.mode = .ignored
    }

    private func holdElapsed() {
        guard var current = touch, current.mode == .undecided, !isPinching() else { return }
        // The panel or a capsule may have opened under the finger.
        guard canAcceptGesture() else {
            current.mode = .ignored
            touch = current
            return
        }
        current.mode = .locked
        touch = current
        focus(at: current.start, lock: true)
    }

    private func focus(at layerPoint: CGPoint, lock: Bool) {
        guard let devicePoint = convert(layerPoint, viewfinderSize) else { return }
        // A new point starts from the default exposure and no lock (TASK-88,
        // as the system camera does). Until the camera answers, 0 and no lock
        // show, and a bias request still waiting is void. If the request
        // fails, `receiveFailure` shows what the device really has. A long
        // press lock keeps the bias (the camera does not reset it), so it
        // waits for no zero and shows the device's own value.
        pendingBias = lock ? nil : 0
        lastSentBias = nil
        isLockClearPending = !lock
        if !lock { isLocked = false }
        refreshDisplayedBias()
        nextReticleID += 1
        reticle = Reticle(id: nextReticleID, layerPoint: layerPoint)
        keepReticleBright()
        latestFocusRequestID = lock ? actions.lock(devicePoint) : actions.focusAndExpose(devicePoint)
    }

    private func requestBias(_ raw: Float) {
        let value = Self.clampedBias(raw, deviceRange: actions.deviceBiasRange())
        guard value != lastSentBias else { return }
        lastSentBias = value
        pendingBias = value
        refreshDisplayedBias()
        if let setBiasForRequest = actions.setBiasForRequest, latestFocusRequestID > 0 {
            setBiasForRequest(value, latestFocusRequestID)
        } else {
            actions.setBias(value)
        }
    }

    // MARK: Service feedback

    /// The service's focus/exposure state changed.
    ///
    /// While a requested bias is waiting, only the answer carrying that bias
    /// settles it. A faster drag leaves earlier answers on the way (a bias that
    /// is passed through, 0 included); those only update what the device has
    /// and never clear the request.
    func receive(_ state: FocusExposureState) {
        serviceState = state
        if let pending = pendingBias, abs(state.exposureBias - pending) < 0.001 {
            pendingBias = nil
        }
        // Until a state without the lock comes, an old lock answer is stale.
        if !state.isLocked { isLockClearPending = false }
        isLocked = state.isLocked && !isLockClearPending
        refreshDisplayedBias()
    }

    /// The camera applied a tap's reset (bias 0, unlocked), even when its
    /// state was already at rest and so published nothing. Ends the wait for
    /// the default exposure that `focus(at:)` started; the reticle stays.
    /// A confirmation for an older tap says nothing about the newest one.
    func receiveTapReset(appliedRequestID: Int) {
        guard appliedRequestID >= latestFocusRequestID else { return }
        if pendingBias == 0 { pendingBias = nil }
        isLockClearPending = false
        isLocked = serviceState.isLocked
        refreshDisplayedBias()
    }

    /// The camera went back to continuous auto on its own (flip, lens, scene
    /// change, foreground), which the state alone cannot say when it was
    /// already at rest: reticle, requests and bias all go.
    ///
    /// `appliedRequestID` is the latest focus request the device had taken
    /// when it reset. A newer request made since (the event can arrive after a
    /// new tap) was taken after the reset, so the frame it drew stays.
    func receiveReset(appliedRequestID: Int = .max) {
        guard appliedRequestID >= latestFocusRequestID else { return }
        serviceState = .initial
        pendingBias = nil
        lastSentBias = nil
        isLockClearPending = false
        isLocked = false
        hideReticle()
        refreshDisplayedBias()
    }

    /// The service could not apply a request. Drops what was only requested,
    /// so the sun and the label show what the device really has, and removes
    /// a reticle that has nothing behind it.
    func receiveFailure() {
        isLockClearPending = false
        isLocked = serviceState.isLocked
        pendingBias = nil
        lastSentBias = nil
        refreshDisplayedBias()
        if !serviceState.isLocked, serviceState.exposureBias == 0 { hideReticle() }
    }

    // MARK: Reticle

    /// The camera changed under the reticle (flip, lens, foreground, panel).
    func hideReticle() {
        dimTask?.cancel()
        dimTask = nil
        if reticle != nil { reticle = nil }
        if isReticleDimmed { isReticleDimmed = false }
    }

    private func refreshDisplayedBias() {
        let value = pendingBias ?? serviceState.exposureBias
        if displayedBias != value { displayedBias = value }
    }

    private func keepReticleBright() {
        if isReticleDimmed { isReticleDimmed = false }
        dimTask?.cancel()
        dimTask = Task { [weak self, dimDelay, hideDelay] in
            try? await Task.sleep(for: dimDelay)
            guard !Task.isCancelled, let self else { return }
            self.isReticleDimmed = true
            try? await Task.sleep(for: hideDelay)
            guard !Task.isCancelled else { return }
            // A reticle with a lock or a bias behind it stays, dimmed.
            if !self.serviceState.isLocked, self.displayedBias == 0, self.touch == nil {
                self.hideReticle()
            }
        }
    }
}

#if DEBUG
/// A camera that is not there, for the UI tests (`-UITestFocus`): answers the
/// model the way `CameraService` would, with a −2...1 device range. With
/// `-UITestFocusLockFails` or `-UITestFocusBiasFails`, those requests fail.
@MainActor
final class FakeFocusExposureBackend {
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("-UITestFocus") }

    private var state = FocusExposureState.initial
    private weak var model: ViewfinderFocusModel?
    private let lockFails = ProcessInfo.processInfo.arguments.contains("-UITestFocusLockFails")
    private let biasFails = ProcessInfo.processInfo.arguments.contains("-UITestFocusBiasFails")

    func attach(_ model: ViewfinderFocusModel) { self.model = model }

    private var lastID = 0
    private func nextID() -> Int {
        lastID += 1
        return lastID
    }

    var actions: FocusExposureActions {
        FocusExposureActions(
            focusAndExpose: { [weak self] _ in
                self?.reply { $0.isLocked = false; $0.exposureBias = 0 }
                return self?.nextID() ?? 0
            },
            lock: { [weak self] _ in
                guard let self else { return 0 }
                if self.lockFails { self.fail() } else { self.reply { $0.isLocked = true; $0.exposureBias = 0 } }
                return self.nextID()
            },
            setBias: { [weak self] bias in
                guard let self else { return }
                if self.biasFails { self.fail() } else { self.reply { $0.exposureBias = bias } }
            },
            deviceBiasRange: { -2...1 })
    }

    private func reply(_ change: @escaping (inout FocusExposureState) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            guard let self else { return }
            change(&self.state)
            self.model?.receive(self.state)
        }
    }

    private func fail() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            self?.model?.receiveFailure()
        }
    }
}
#endif
