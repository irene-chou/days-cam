import SwiftUI
import XCTest
@testable import DaysCam

/// #687: the level's angle, display rules and when it reads the sensor.
@MainActor
final class ViewfinderLevelModelTests: XCTestCase {
    private func gravity(tilt degrees: Double) -> LevelGravity {
        let radians = degrees * .pi / 180
        return LevelGravity(x: sin(radians), y: -cos(radians), z: 0)
    }

    private final class FakeSource: LevelSource {
        var starts = 0
        var stops = 0
        private(set) var handler: (@MainActor (LevelGravity) -> Void)?
        func start(_ handler: @escaping @MainActor (LevelGravity) -> Void) {
            starts += 1
            self.handler = handler
        }
        func stop() { stops += 1 }
    }

    // MARK: - 1: angle

    func test_687_1_upright_isZero() throws {
        let angle = try XCTUnwrap(ViewfinderLevelModel.angle(gravity: LevelGravity(x: 0, y: -1, z: 0), rotation: .portrait))
        XCTAssertEqual(angle, 0, accuracy: 0.001)
    }

    func test_687_1_rightTiltIsPositive_leftTiltIsNegative() throws {
        let right = try XCTUnwrap(ViewfinderLevelModel.angle(gravity: gravity(tilt: 3), rotation: .portrait))
        let left = try XCTUnwrap(ViewfinderLevelModel.angle(gravity: gravity(tilt: -3), rotation: .portrait))
        XCTAssertEqual(right, 3, accuracy: 0.001)
        XCTAssertEqual(left, -3, accuracy: 0.001)
    }

    /// #711-1: front-back lean beyond 25° from upright hides it.
    func test_711_1_pitchLimit() throws {
        func lean(_ degrees: Double) -> LevelGravity {
            let radians = degrees * .pi / 180
            return LevelGravity(x: 0, y: -cos(radians), z: sin(radians))
        }
        XCTAssertNotNil(ViewfinderLevelModel.angle(gravity: lean(20), rotation: .portrait))
        XCTAssertNil(ViewfinderLevelModel.angle(gravity: lean(30), rotation: .portrait))
        XCTAssertNil(ViewfinderLevelModel.angle(gravity: lean(-30), rotation: .portrait))
        // Landscape held upright leans the same way.
        let landscape = LevelGravity(x: -cos(20 * Double.pi / 180), y: 0, z: sin(20 * Double.pi / 180))
        XCTAssertNotNil(ViewfinderLevelModel.angle(gravity: landscape, rotation: .landscapeTopLeft))
        let landscapeFar = LevelGravity(x: -cos(30 * Double.pi / 180), y: 0, z: sin(30 * Double.pi / 180))
        XCTAssertNil(ViewfinderLevelModel.angle(gravity: landscapeFar, rotation: .landscapeTopLeft))
        // Hysteresis: 25.5° passes only when it was already upright.
        XCTAssertNil(ViewfinderLevelModel.angle(gravity: lean(25.5), rotation: .portrait))
        XCTAssertNotNil(ViewfinderLevelModel.angle(gravity: lean(25.5), rotation: .portrait, wasUpright: true))
        XCTAssertNil(ViewfinderLevelModel.angle(gravity: lean(26.5), rotation: .portrait, wasUpright: true))
    }

    func test_687_1_pointingDownOrUp_isNil() {
        XCTAssertNil(ViewfinderLevelModel.angle(gravity: LevelGravity(x: 0, y: 0, z: -1), rotation: .portrait))
        XCTAssertNil(ViewfinderLevelModel.angle(gravity: LevelGravity(x: 0, y: 0, z: 1), rotation: .portrait))
    }

    func test_687_1_landscapeIsRelativeToTheLandscapeFrame() throws {
        // Top edge pointing left: the phone's right side is up, so gravity is -x.
        let upright = try XCTUnwrap(ViewfinderLevelModel.angle(gravity: LevelGravity(x: -1, y: 0, z: 0),
                                                              rotation: .landscapeTopLeft))
        XCTAssertEqual(upright, 0, accuracy: 0.001)
        // The same portrait-style vector is a 90 degree roll for a landscape viewfinder.
        let rolled = try XCTUnwrap(ViewfinderLevelModel.angle(gravity: LevelGravity(x: 0, y: -1, z: 0),
                                                             rotation: .landscapeTopLeft))
        XCTAssertEqual(abs(rolled), 90, accuracy: 0.001)

        let topRight = try XCTUnwrap(ViewfinderLevelModel.angle(gravity: LevelGravity(x: 1, y: 0, z: 0),
                                                               rotation: .landscapeTopRight))
        XCTAssertEqual(topRight, 0, accuracy: 0.001)
        let flipped = try XCTUnwrap(ViewfinderLevelModel.angle(gravity: LevelGravity(x: 0, y: 1, z: 0),
                                                              rotation: .upsideDown))
        XCTAssertEqual(flipped, 0, accuracy: 0.001)
    }

    func test_687_1_landscapeSmallTilt_sameSignAsClockwise() throws {
        // Landscape top-left, turned 3 degrees clockwise (as the viewer sees it).
        let radians = 3 * Double.pi / 180
        // Photo frame gravity (sin, -cos); map back to device: x' = -y, y' = x  =>  x = y', y = -x'.
        let device = LevelGravity(x: -cos(radians), y: -sin(radians), z: 0)
        let angle = try XCTUnwrap(ViewfinderLevelModel.angle(gravity: device, rotation: .landscapeTopLeft))
        XCTAssertEqual(angle, 3, accuracy: 0.001)
    }

    // MARK: - 2: display rules

    func test_687_2_displayStateMachine() {
        var state = LevelDisplayState(holdDuration: 1)
        XCTAssertEqual(state.update(angle: 8, now: 0), .hidden)
        XCTAssertEqual(state.update(angle: 4, now: 0.1), .visible(angle: 4))
        XCTAssertEqual(state.update(angle: 0.5, now: 0.2), .level)
        XCTAssertEqual(state.update(angle: 0.5, now: 1.1), .level, "still within the hold")
        XCTAssertEqual(state.refresh(now: 1.2), .hidden, "hold over")
        XCTAssertEqual(state.update(angle: 0.4, now: 1.3), .hidden, "stays hidden while still level")
        XCTAssertEqual(state.update(angle: 4, now: 1.4), .visible(angle: 4), "leaving the band shows it again")
        XCTAssertEqual(state.update(angle: 0.2, now: 1.5), .level)
    }

    func test_687_2_levelThenBeyondLimitHidesAtOnce() {
        var state = LevelDisplayState(holdDuration: 1)
        XCTAssertEqual(state.update(angle: 0, now: 0), .level)
        XCTAssertEqual(state.update(angle: 8, now: 0.1), .hidden)
        XCTAssertEqual(state.update(angle: nil, now: 0.2), .hidden)
    }

    /// #711-2: 4° shows, 7° hides; once showing, 5.5° stays and 6.5° hides.
    func test_711_2_rollLimitAndHysteresis() {
        var state = LevelDisplayState(holdDuration: 1)
        XCTAssertEqual(state.update(angle: 4, now: 0), .visible(angle: 4))
        XCTAssertEqual(state.update(angle: 7, now: 0.1), .hidden)

        XCTAssertEqual(state.update(angle: 5.5, now: 0.2), .hidden, "not showing: 5° limit")
        XCTAssertEqual(state.update(angle: 4.5, now: 0.3), .visible(angle: 4.5))
        XCTAssertEqual(state.update(angle: 5.5, now: 0.4), .visible(angle: 5.5), "showing: 6° limit")
        XCTAssertEqual(state.update(angle: 6.5, now: 0.5), .hidden)
        XCTAssertEqual(state.update(angle: 5.5, now: 0.6), .hidden, "back to the 5° limit")
    }

    func test_714_fadeDurations() {
        XCTAssertEqual(LevelIndicatorView.fadeInDuration, 0.3)
        XCTAssertEqual(LevelIndicatorView.fadeOutDuration, 0.5)
    }

    /// #711-3: the level line and the focus frame share one yellow.
    func test_711_3_focusYellowValue() {
        XCTAssertEqual(CameraTheme.focusYellow, Color(red: 1, green: 0.84, blue: 0.04))
    }

    func test_687_2_modelShowsAndHoldsWithInjectedClock() {
        var time = 0.0
        let source = FakeSource()
        let model = ViewfinderLevelModel(source: source, now: { time })
        model.setConditions(LevelConditions(isSwitchOn: true))
        source.handler?(gravity(tilt: 4))
        guard case .visible(let angle) = model.display else { return XCTFail("\(model.display)") }
        XCTAssertEqual(angle, 4, accuracy: 0.01)

        model.rotation = .portrait
        source.handler?(gravity(tilt: 0))
        // Smoothing pulls toward level over a few readings.
        for _ in 0..<60 { source.handler?(gravity(tilt: 0)) }
        XCTAssertEqual(model.display, .level)
        time = 1.5
        model.refresh()
        XCTAssertEqual(model.display, .hidden)
    }

    // MARK: - 3: when it runs

    func test_687_3_runsOnlyWhenEveryConditionHolds() {
        let source = FakeSource()
        let model = ViewfinderLevelModel(source: source)

        model.setConditions(LevelConditions(isSwitchOn: false))
        XCTAssertEqual(source.starts, 0, "switch off")

        model.setConditions(LevelConditions(isSwitchOn: true))
        XCTAssertEqual(source.starts, 1)
        XCTAssertTrue(model.isRunning)

        model.setConditions(LevelConditions(isSwitchOn: true, isCountingDown: true))
        XCTAssertEqual(source.stops, 1, "countdown")
        model.setConditions(LevelConditions(isSwitchOn: true))
        XCTAssertEqual(source.starts, 2)

        model.setConditions(LevelConditions(isSwitchOn: true, isSceneActive: false))
        XCTAssertEqual(source.stops, 2, "scene inactive")
        model.setConditions(LevelConditions(isSwitchOn: true))
        XCTAssertEqual(source.starts, 3)

        model.setConditions(LevelConditions(isSwitchOn: true, isCameraVisible: false))
        XCTAssertEqual(source.stops, 3, "camera gone")
        XCTAssertEqual(model.display, .hidden)

        model.setConditions(LevelConditions(isSwitchOn: true))
        model.setConditions(LevelConditions(isSwitchOn: false))
        XCTAssertEqual(source.stops, 4, "switch off again")
    }

    func test_687_3_sameConditionsDoNotRestart() {
        let source = FakeSource()
        let model = ViewfinderLevelModel(source: source)
        model.setConditions(LevelConditions(isSwitchOn: true))
        model.setConditions(LevelConditions(isSwitchOn: true))
        XCTAssertEqual(source.starts, 1)
    }

    /// #701-1: thin, long line close to the native camera's.
    func test_701_1_lineDimensions() {
        XCTAssertEqual(LevelIndicatorView.thickness, 1)
        XCTAssertEqual(LevelIndicatorView.sideLength, 36)
        XCTAssertEqual(LevelIndicatorView.middleLength, 96)
        XCTAssertEqual(LevelIndicatorView.gap, 8)
        XCTAssertEqual(LevelIndicatorView.levelLength, 184)
    }
}
