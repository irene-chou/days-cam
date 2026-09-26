import XCTest
@testable import DaysCam

/// Covers `PositionDragAdapter`: the translation → center conversion #65
/// asks `ui-shell` to write between `CameraScreen`'s `OverlayDragHandling`
/// reports and `PositionTabModel.applyDrag(center:viewfinderSize:)`'s
/// absolute-center interface. Equivalent to TASK-24's own 24.8/24.9
/// (`PositionTabModelTests`), but exercised through this card's own
/// shell-side adapter path (acceptance P.3, P.4).
@MainActor
final class PositionDragAdapterTests: XCTestCase {
    private final class Spy {
        var updated: [CameraProfile] = []
        func update(_ profile: CameraProfile) throws {
            updated.append(profile)
        }
    }

    private func makeAdapter(position: OverlayPlacement = .anchor(.middleCenter)) -> (PositionDragAdapter, PositionTabModel, Spy) {
        let spy = Spy()
        let profile = CameraProfile(name: "小寶", startDate: DateFixture.components(2026, 1, 1), position: position)
        let positionTabModel = PositionTabModel(profile: profile, updateProfile: spy.update)
        let adapter = PositionDragAdapter(positionTabModel: positionTabModel)
        return (adapter, positionTabModel, spy)
    }

    // MARK: - P.3 觀景窗正中心（等同 24.8，經殼層轉接）

    func testDragEndedAtViewfinderCenterConvertsToHalfHalf() {
        let (adapter, positionTabModel, _) = makeAdapter()
        // Profile starts at `.anchor(.middleCenter)`, whose reference point
        // at a 288x384 viewfinder is already (144, 192) — a zero translation
        // lands the drag exactly there, matching 24.8's own inputs.
        adapter.overlayDragEnded(translation: .zero, viewfinderSize: CGSize(width: 288, height: 384))

        XCTAssertEqual(positionTabModel.profile.position, .custom(x: 0.5, y: 0.5), "P.3")
    }

    // MARK: - P.4 拖出觀景窗外，被夾進 4% 邊距（等同 24.9）

    func testDragEndedOutsideViewfinderClampsIntoTheMargin() {
        let (adapter, positionTabModel, _) = makeAdapter()
        let viewfinderSize = CGSize(width: 288, height: 384)
        // Center (144,192) + this translation lands the raw center at
        // (400, 500) — past the viewfinder's own 288x384 bounds.
        adapter.overlayDragEnded(translation: CGSize(width: 256, height: 308), viewfinderSize: viewfinderSize)

        guard case let .custom(x, y) = positionTabModel.profile.position else {
            return XCTFail("expected a .custom position")
        }
        XCTAssertLessThanOrEqual(x, 1, "P.4")
        XCTAssertLessThanOrEqual(y, 1, "P.4")
        XCTAssertEqual(x, 1 - PositionTabModel.marginRatio, accuracy: 0.0001, "P.4: 夾在 4% 邊距上")
        XCTAssertEqual(y, 1 - PositionTabModel.marginRatio, accuracy: 0.0001, "P.4: 夾在 4% 邊距上")
    }

    // MARK: - overlayDragChanged 不寫入（本卡的假設：changed 只做預覽用的基準點）

    func testDragChangedDoesNotPersist() {
        let (adapter, _, spy) = makeAdapter()
        adapter.overlayDragChanged(translation: CGSize(width: 10, height: 10),
                                   viewfinderSize: CGSize(width: 288, height: 384))
        XCTAssertTrue(spy.updated.isEmpty, "changed must not persist — only overlayDragEnded commits")
    }

    // MARK: - 同一次拖曳的 translation 是從起點累加，不是逐次疊加

    func testTranslationWithinOneGestureIsMeasuredFromTheSameStartPoint() {
        let (adapter, positionTabModel, _) = makeAdapter()
        let viewfinderSize = CGSize(width: 288, height: 384)

        // Two `changed` calls, as SwiftUI's `DragGesture` reports them: every
        // translation is measured from the same original touch-down point,
        // never from the previous callback's translation.
        adapter.overlayDragChanged(translation: CGSize(width: 10, height: 0), viewfinderSize: viewfinderSize)
        adapter.overlayDragChanged(translation: CGSize(width: 20, height: 0), viewfinderSize: viewfinderSize)
        adapter.overlayDragEnded(translation: CGSize(width: 20, height: 0), viewfinderSize: viewfinderSize)

        let (expectedX, _) = PositionTabModel.customPosition(forDragCenter: CGPoint(x: 164, y: 192),
                                                              viewfinderSize: viewfinderSize)
        guard case let .custom(actualX, _) = positionTabModel.profile.position else {
            return XCTFail("expected a .custom position")
        }
        XCTAssertEqual(actualX, expectedX, accuracy: 0.0001)
    }

    // MARK: - 起點取自疊字當下的實際位置，不是固定的觀景窗中心

    func testStartCenterComesFromTheOverlaysCurrentAnchoredPosition() {
        // Starting from 左上 (`.topLeading`), not the default
        // `.middleCenter` — the drag's start point must track wherever the
        // overlay actually is, not assume it always starts centered.
        let (adapter, positionTabModel, _) = makeAdapter(position: .anchor(.topLeading))
        let viewfinderSize = CGSize(width: 288, height: 384)
        let margin = OverlayMetrics.margin(forShortEdge: min(viewfinderSize.width, viewfinderSize.height))

        adapter.overlayDragEnded(translation: .zero, viewfinderSize: viewfinderSize)

        let (expectedX, expectedY) = PositionTabModel.customPosition(forDragCenter: CGPoint(x: margin, y: margin),
                                                                      viewfinderSize: viewfinderSize)
        XCTAssertEqual(positionTabModel.profile.position, .custom(x: expectedX, y: expectedY))
    }

    // MARK: - 走 `OverlayPanelModel.overlayDragHandler` 的殼層轉接路徑

    func testWiredThroughOverlayPanelModelsOverlayDragHandler() {
        let (adapter, positionTabModel, _) = makeAdapter()
        let panelModel = OverlayPanelModel()
        panelModel.overlayDragHandler = adapter

        panelModel.overlayDragHandler?.overlayDragEnded(translation: .zero,
                                                        viewfinderSize: CGSize(width: 288, height: 384))

        XCTAssertEqual(positionTabModel.profile.position, .custom(x: 0.5, y: 0.5))
    }
}
