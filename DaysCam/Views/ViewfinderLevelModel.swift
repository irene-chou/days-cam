import CoreMotion
import Foundation

/// A gravity vector in the device's own axes, as CoreMotion reports it
/// (x to the right, y to the top edge, z out of the screen); held upright it
/// is `(0, -1, 0)`.
struct LevelGravity: Equatable {
    var x: Double
    var y: Double
    var z: Double
}

/// Where gravity readings come from, so the model is tested and the UI tests
/// run without CoreMotion.
@MainActor
protocol LevelSource: AnyObject {
    /// Starts delivering readings to `handler` on the main actor.
    func start(_ handler: @escaping @MainActor (LevelGravity) -> Void)
    func stop()
}

/// The real source: device motion at 30 Hz on the main queue.
@MainActor
final class CoreMotionLevelSource: LevelSource {
    private let manager = CMMotionManager()

    func start(_ handler: @escaping @MainActor (LevelGravity) -> Void) {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30
        manager.startDeviceMotionUpdates(to: .main) { motion, _ in
            guard let gravity = motion?.gravity else { return }
            MainActor.assumeIsolated {
                handler(LevelGravity(x: gravity.x, y: gravity.y, z: gravity.z))
            }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}

#if DEBUG
/// A phone held at a fixed tilt, for the UI tests (`-UITestLevelAngle <度>`,
/// clockwise positive): reports it once each time it is started.
@MainActor
final class FixedAngleLevelSource: LevelSource {
    private let degrees: Double

    init(degrees: Double) {
        self.degrees = degrees
    }

    nonisolated static var uiTestAngle: Double? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-UITestLevelAngle"), index + 1 < arguments.count else { return nil }
        return Double(arguments[index + 1])
    }

    func start(_ handler: @escaping @MainActor (LevelGravity) -> Void) {
        let radians = degrees * .pi / 180
        handler(LevelGravity(x: sin(radians), y: -cos(radians), z: 0))
    }

    func stop() {}
}
#endif

/// What the indicator shows right now.
enum LevelDisplay: Equatable {
    case hidden
    /// Within 5° of level, `angle` degrees clockwise.
    case visible(angle: Double)
    /// Within 1° of level.
    case level
}

/// When the level shows (#687-3, #711): within 5° of level it shows the tilt,
/// within 1° it is level and stays for `holdDuration` before fading, beyond
/// 5° (or without an angle) it hides at once. Once showing, it keeps showing
/// out to 6° so it does not flicker at the edge. After the hold it stays
/// hidden until the phone leaves the 1° band again.
struct LevelDisplayState {
    static let visibleLimit = 5.0
    /// The wider limit while already in range, against flicker at the edge.
    static let hiddenLimit = 6.0
    static let levelLimit = 1.0

    var holdDuration: TimeInterval
    private var angle: Double?
    private var levelSince: TimeInterval?
    private var isExpired = false
    private var isInRange = false

    init(holdDuration: TimeInterval = 1) {
        self.holdDuration = holdDuration
    }

    /// Takes a new angle (`nil` when there is none) at time `now` (seconds).
    mutating func update(angle: Double?, now: TimeInterval) -> LevelDisplay {
        self.angle = angle
        return evaluate(now: now)
    }

    /// Re-evaluates the last angle at a later time, for the hold running out.
    mutating func refresh(now: TimeInterval) -> LevelDisplay {
        evaluate(now: now)
    }

    /// Forgets everything, as when the level stops.
    mutating func reset() {
        angle = nil
        levelSince = nil
        isExpired = false
        isInRange = false
    }

    /// Seconds from `now` until the hold ends, while level is showing.
    func holdRemaining(now: TimeInterval) -> TimeInterval? {
        guard let levelSince, !isExpired, holdDuration.isFinite else { return nil }
        return max(0, holdDuration - (now - levelSince))
    }

    private mutating func evaluate(now: TimeInterval) -> LevelDisplay {
        let limit = isInRange ? Self.hiddenLimit : Self.visibleLimit
        guard let angle, abs(angle) <= limit else {
            levelSince = nil
            isExpired = false
            isInRange = false
            return .hidden
        }
        isInRange = true
        guard abs(angle) <= Self.levelLimit else {
            levelSince = nil
            isExpired = false
            return .visible(angle: angle)
        }
        if isExpired { return .hidden }
        let start = levelSince ?? now
        levelSince = start
        if now - start >= holdDuration {
            isExpired = true
            return .hidden
        }
        return .level
    }
}

/// The conditions under which the level reads the sensor (#687-1): the
/// camera is on top, the switch is on, no countdown, scene active.
struct LevelConditions: Equatable {
    var isSwitchOn = false
    var isCountingDown = false
    var isSceneActive = true
    var isCameraVisible = true

    var shouldRun: Bool {
        isSwitchOn && isCameraVisible && isSceneActive && !isCountingDown
    }
}

/// Reads gravity and turns it into the level's display (#687).
@MainActor
final class ViewfinderLevelModel: ObservableObject {
    @Published private(set) var display: LevelDisplay = .hidden

    /// How the viewfinder is held; angles are relative to it.
    var rotation: ViewfinderRotation = .portrait

    private(set) var isRunning = false

    private let source: LevelSource
    private let now: () -> TimeInterval
    private var state: LevelDisplayState
    private var filtered: LevelGravity?
    private var isUpright = false
    private var expiryTask: Task<Void, Never>?

    /// How far the phone may lean front or back from upright and still show
    /// the level, in degrees (#711-1).
    nonisolated static let uprightLimit = 25.0

    /// Low-pass weight of a new reading at 30 Hz, about a 0.2 s time constant.
    private static let smoothing = (1.0 / 30) / (0.2 + 1.0 / 30)

    init(source: LevelSource,
         holdDuration: TimeInterval = 1,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.source = source
        self.now = now
        self.state = LevelDisplayState(holdDuration: holdDuration)
    }

    /// The tilt, in degrees clockwise, of the viewfinder's horizon: gravity is
    /// first turned into the viewfinder's axes by `rotation`, then the roll
    /// is taken. `nil` when the phone is more than `uprightLimit` (`wasUpright`:
    /// `uprightLimit` + 1°, against flicker) from upright, front to back.
    nonisolated static func angle(gravity: LevelGravity, rotation: ViewfinderRotation,
                                  wasUpright: Bool = false) -> Double? {
        let limit = uprightLimit + (wasUpright ? 1 : 0)
        guard abs(gravity.z) <= sin(limit * Double.pi / 180) else { return nil }
        let radians = rotation.degrees * .pi / 180
        let x = gravity.x * cos(radians) - gravity.y * sin(radians)
        let y = gravity.x * sin(radians) + gravity.y * cos(radians)
        guard x != 0 || y != 0 else { return nil }
        return atan2(x, -y) * 180 / .pi
    }

    /// Starts or stops the sensor to match `conditions`.
    func setConditions(_ conditions: LevelConditions) {
        if conditions.shouldRun {
            guard !isRunning else { return }
            isRunning = true
            filtered = nil
            source.start { [weak self] gravity in self?.receive(gravity) }
        } else {
            guard isRunning else { return }
            isRunning = false
            source.stop()
            expiryTask?.cancel()
            state.reset()
            filtered = nil
            isUpright = false
            display = .hidden
        }
    }

    /// Takes one reading.
    func receive(_ gravity: LevelGravity) {
        guard isRunning else { return }
        let smoothed: LevelGravity
        if let previous = filtered {
            let weight = Self.smoothing
            smoothed = LevelGravity(x: previous.x + (gravity.x - previous.x) * weight,
                                    y: previous.y + (gravity.y - previous.y) * weight,
                                    z: previous.z + (gravity.z - previous.z) * weight)
        } else {
            smoothed = gravity
        }
        filtered = smoothed
        let angle = Self.angle(gravity: smoothed, rotation: rotation, wasUpright: isUpright)
        isUpright = angle != nil
        apply(state.update(angle: angle, now: now()))
    }

    /// Re-evaluates at the current time; called when the level hold may have
    /// run out.
    func refresh() {
        apply(state.refresh(now: now()))
    }

    private func apply(_ next: LevelDisplay) {
        if display != next { display = next }
        expiryTask?.cancel()
        guard next == .level, let remaining = state.holdRemaining(now: now()) else { return }
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }
}
