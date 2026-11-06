import AVFoundation
import XCTest
@testable import DaysCam

/// Covers the hardware-shutter hookup on `CameraPreviewContainerView` (#686).
/// The simulator never delivers `AVCaptureEvent`s, so the real button press
/// is a device-only acceptance item; here the handler is driven directly.
@MainActor
final class CameraPreviewViewTests: XCTestCase {
    func testContainerHasOneCaptureEventInteraction() throws {
        let view = CameraPreviewContainerView(onCaptureEvent: {})
        let interactions = view.interactions.compactMap { $0 as? AVCaptureEventInteraction }
        XCTAssertEqual(interactions.count, 1)
        XCTAssertTrue(try XCTUnwrap(interactions.first).isEnabled)
    }

    func testDisablingCaptureEventDisablesTheInteraction() throws {
        let view = CameraPreviewContainerView(onCaptureEvent: {})
        view.isCaptureEventEnabled = false
        let interaction = try XCTUnwrap(view.interactions.compactMap { $0 as? AVCaptureEventInteraction }.first)
        XCTAssertFalse(interaction.isEnabled)
        view.isCaptureEventEnabled = true
        XCTAssertTrue(interaction.isEnabled)
    }

    func testEndedPhaseCallsOnCaptureEventOnce() {
        var count = 0
        let fired = expectation(description: "onCaptureEvent")
        let view = CameraPreviewContainerView(onCaptureEvent: {
            count += 1
            fired.fulfill()
        })
        view.handle(phase: .ended)
        wait(for: [fired], timeout: 1)
        XCTAssertEqual(count, 1)
    }

    func testBeganAndCancelledPhasesDoNotCallOnCaptureEvent() {
        var count = 0
        let view = CameraPreviewContainerView(onCaptureEvent: { count += 1 })
        view.handle(phase: .began)
        view.handle(phase: .cancelled)
        // The `.ended` path hops to the main queue; drain it to be sure
        // nothing was scheduled.
        let drained = expectation(description: "drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)
        XCTAssertEqual(count, 0)
    }
}
