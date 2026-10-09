import Combine
import XCTest
@testable import DaysCam

/// Covers the corner round button and its expansion (TASK-72, #302).
@MainActor
final class ZoomPresetBarTests: XCTestCase {
    private let presets = [ZoomPreset(displayFactor: 0.5), ZoomPreset(displayFactor: 1), ZoomPreset(displayFactor: 2)]
    private var cancellables: Set<AnyCancellable> = []

    /// 72.1: the button shows the current zoom; a single preset shows nothing.
    func testCollapsedTextAndVisibility() {
        XCTAssertEqual(ZoomPresetBarLogic.collapsedText(requested: 1, presets: presets), "1×")
        XCTAssertEqual(ZoomPresetBarLogic.collapsedText(requested: 2, presets: presets), "2×")
        XCTAssertEqual(ZoomPresetBarLogic.collapsedText(requested: 1.7, presets: presets), "1.7×")
        XCTAssertFalse(ZoomPresetBarLogic.isShown(presets: []))
        XCTAssertFalse(ZoomPresetBarLogic.isShown(presets: [ZoomPreset(displayFactor: 1)]))
        XCTAssertTrue(ZoomPresetBarLogic.isShown(presets: presets))
    }

    /// 72.6: the label reads the current zoom.
    func testCollapsedAccessibilityLabel() {
        XCTAssertEqual(ZoomPresetBarLogic.collapsedAccessibilityLabel(requested: 2), "焦段，目前 2 倍")
        XCTAssertEqual(ZoomPresetBarLogic.collapsedAccessibilityLabel(requested: 1.7), "焦段，目前 1.7 倍")
    }

    /// 72.2: a tap opens, a second closes; collapse is idempotent.
    func testToggleAndCollapse() {
        let expansion = ZoomPresetExpansion()
        XCTAssertFalse(expansion.isExpanded)
        expansion.toggle()
        XCTAssertTrue(expansion.isExpanded)
        expansion.toggle()
        XCTAssertFalse(expansion.isExpanded)
        expansion.collapse()
        XCTAssertFalse(expansion.isExpanded)
    }

    /// 72.3: closes on its own after the delay.
    func testAutoCollapsesAfterDelay() async throws {
        let expansion = ZoomPresetExpansion(autoCollapseDelay: .milliseconds(50))
        expansion.expand()
        XCTAssertTrue(expansion.isExpanded)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(expansion.isExpanded)
    }

    /// 72.3: collapsing early cancels the timer, so a later expand is not cut short.
    func testEarlyCollapseCancelsTimer() async throws {
        let expansion = ZoomPresetExpansion(autoCollapseDelay: .milliseconds(200))
        expansion.expand()
        expansion.collapse()
        try await Task.sleep(for: .milliseconds(100))
        expansion.expand()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(expansion.isExpanded, "the first timer must not close the second expansion")
    }

    /// 72.4: a pinch moves the zoom but never the expansion state.
    func testPinchDoesNotExpand() {
        let zoom = ViewfinderZoomModel(zoomRange: { ZoomRange(minimum: 0.5, maximum: 10) }, applyFactor: { _ in })
        let expansion = ZoomPresetExpansion()
        var changes = 0
        expansion.objectWillChange.sink { changes += 1 }.store(in: &cancellables)
        zoom.pinchChanged(magnification: 1.7)
        zoom.pinchChanged(magnification: 1.8)
        zoom.pinchEnded()
        XCTAssertEqual(zoom.requestedFactor, 1.8, accuracy: 0.0001)
        XCTAssertFalse(expansion.isExpanded)
        XCTAssertEqual(changes, 0)
        XCTAssertEqual(ZoomPresetBarLogic.collapsedText(requested: zoom.requestedFactor, presets: presets), "1.8×")
    }
}
