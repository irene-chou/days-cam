import XCTest
@testable import DaysCam

/// Covers `PositionDragAdapter` (#68): now that `OverlayTextView` reports an
/// already-clamped center directly (see `OverlayTextViewTests`'
/// `clampedDragCenter` coverage for D.1–D.4), this adapter's only job is to
/// forward `overlayDragEnded`'s center straight into
/// `PositionTabModel.applyDrag(center:viewfinderSize:)`, and to leave
/// `overlayDragChanged` as a no-op. D.5's carry-over of P.3/P.4/24.8/24.9,
/// rewritten against the new center-based interface.
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

    // MARK: - P.3／24.8：觀景窗正中心

    func testDragEndedAtViewfinderCenterConvertsToHalfHalf() {
        let (adapter, positionTabModel, _) = makeAdapter()
        adapter.overlayDragEnded(center: CGPoint(x: 144, y: 192), viewfinderSize: CGSize(width: 288, height: 384))

        XCTAssertEqual(positionTabModel.profile.position, .custom(x: 0.5, y: 0.5), "P.3")
    }

    // MARK: - P.4／24.9：中心點落在觀景窗外，被夾進 4% 邊距

    func testDragEndedOutsideViewfinderClampsIntoTheMargin() {
        let (adapter, positionTabModel, _) = makeAdapter()
        adapter.overlayDragEnded(center: CGPoint(x: 400, y: 500), viewfinderSize: CGSize(width: 288, height: 384))

        guard case let .custom(x, y) = positionTabModel.profile.position else {
            return XCTFail("expected a .custom position")
        }
        XCTAssertLessThanOrEqual(x, 1, "P.4")
        XCTAssertLessThanOrEqual(y, 1, "P.4")
        XCTAssertEqual(x, 1 - PositionTabModel.marginRatio, accuracy: 0.0001, "P.4: 夾在 4% 邊距上")
        XCTAssertEqual(y, 1 - PositionTabModel.marginRatio, accuracy: 0.0001, "P.4: 夾在 4% 邊距上")
    }

    // MARK: - overlayDragChanged 不寫入（#68：即時跟手已交給 OverlayTextView 自己的本地位移）

    func testDragChangedDoesNotPersist() {
        let (adapter, _, spy) = makeAdapter()
        adapter.overlayDragChanged(center: CGPoint(x: 200, y: 200), viewfinderSize: CGSize(width: 288, height: 384))
        XCTAssertTrue(spy.updated.isEmpty)
    }

    // MARK: - 走 `OverlayPanelModel.overlayDragHandler` 的殼層轉接路徑

    func testWiredThroughOverlayPanelModelsOverlayDragHandler() {
        let (adapter, positionTabModel, _) = makeAdapter()
        let panelModel = OverlayPanelModel()
        panelModel.overlayDragHandler = adapter

        panelModel.overlayDragHandler?.overlayDragEnded(center: CGPoint(x: 144, y: 192),
                                                        viewfinderSize: CGSize(width: 288, height: 384))

        XCTAssertEqual(positionTabModel.profile.position, .custom(x: 0.5, y: 0.5))
    }
}
