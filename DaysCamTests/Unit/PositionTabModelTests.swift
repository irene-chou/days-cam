import XCTest
@testable import DaysCam

/// Covers `PositionTabModel`'s state and drag-to-fraction conversion
/// (PRD 0.2 FR-12), TASK-24 acceptance 24.8–24.11. The drag gesture itself
/// lives on `CameraScreen` (`ui-shell`, TASK-22, not yet landed); everything
/// here is the pure conversion plus the model's own persistence, both
/// testable without it.
@MainActor
final class PositionTabModelTests: XCTestCase {
    private func baselineProfile(position: OverlayPlacement = .anchor(.bottomTrailing)) -> CameraProfile {
        CameraProfile(name: "小寶",
                     startDate: DateFixture.components(2026, 1, 1),
                     position: position)
    }

    private final class Spy {
        var updated: [CameraProfile] = []
        var shouldThrow: Error?

        func update(_ profile: CameraProfile) throws {
            if let error = shouldThrow { throw error }
            updated.append(profile)
        }
    }

    private func makeModel(profile: CameraProfile, spy: Spy) -> PositionTabModel {
        PositionTabModel(profile: profile, updateProfile: spy.update)
    }

    // MARK: - 24.8 拖曳換算：中心點落在觀景窗正中心

    func testDragCenterAtViewfinderCenterConvertsToHalfHalf() {
        let (x, y) = PositionTabModel.customPosition(
            forDragCenter: CGPoint(x: 144, y: 192),
            viewfinderSize: CGSize(width: 288, height: 384)
        )
        XCTAssertEqual(x, 0.5, accuracy: 0.0001, "24.8")
        XCTAssertEqual(y, 0.5, accuracy: 0.0001, "24.8")
    }

    func testApplyDragAtCenterStoresCustomHalfHalf() {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(), spy: spy)
        model.applyDrag(center: CGPoint(x: 144, y: 192), viewfinderSize: CGSize(width: 288, height: 384))
        XCTAssertEqual(model.profile.position, .custom(x: 0.5, y: 0.5), "24.8")
        XCTAssertEqual(spy.updated.last?.position, .custom(x: 0.5, y: 0.5))
    }

    // MARK: - 24.9 拖到觀景窗外，被夾到邊距內、值 ≤ 1

    func testDragCenterOutsideViewfinderClampsToMarginBand() {
        let (x, y) = PositionTabModel.customPosition(
            forDragCenter: CGPoint(x: 400, y: 500),
            viewfinderSize: CGSize(width: 288, height: 384)
        )
        XCTAssertLessThanOrEqual(x, 1, "24.9")
        XCTAssertLessThanOrEqual(y, 1, "24.9")
        XCTAssertEqual(x, 1 - PositionTabModel.marginRatio, accuracy: 0.0001, "24.9: 夾在 4% 邊距上")
        XCTAssertEqual(y, 1 - PositionTabModel.marginRatio, accuracy: 0.0001, "24.9: 夾在 4% 邊距上")
    }

    func testDragCenterBeforeOriginClampsToMarginBandLowEnd() {
        let (x, y) = PositionTabModel.customPosition(
            forDragCenter: CGPoint(x: -50, y: -20),
            viewfinderSize: CGSize(width: 288, height: 384)
        )
        XCTAssertEqual(x, PositionTabModel.marginRatio, accuracy: 0.0001)
        XCTAssertEqual(y, PositionTabModel.marginRatio, accuracy: 0.0001)
    }

    // MARK: - 24.10 點九宮格「左上」

    func testSelectingTopLeadingStoresAnchorAndNamesIt() {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(), spy: spy)
        model.selectAnchor(.topLeading)
        XCTAssertEqual(model.profile.position, .anchor(.topLeading), "24.10")
        XCTAssertEqual(model.positionName, "左上", "24.10")
    }

    func testSelectAnchorNoOpsWhenUnchanged() {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(position: .anchor(.bottomTrailing)), spy: spy)
        model.selectAnchor(.bottomTrailing)
        XCTAssertTrue(spy.updated.isEmpty)
    }

    // MARK: - 24.11 .custom 狀態下的位置名稱

    func testCustomPositionNameIsCustomPosition() {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(position: .custom(x: 0.3, y: 0.7)), spy: spy)
        XCTAssertEqual(model.positionName, "自訂位置", "24.11")
    }

    // MARK: - 每個錨點都有名稱，且與 0.1 位置選單一致

    func testEveryAnchorHasAName() {
        let names = OverlayPosition.allCases.map(PositionTabModel.anchorName)
        XCTAssertEqual(names, ["左上", "中上", "右上", "左中", "正中", "右中", "左下", "中下", "右下"])
    }

    // MARK: - #126 九宮格小框邊長：上限 96、留白 12/8、無下限

    func testGridBoxSideCapsAtMaxWhenAvailableHeightIsAmple() {
        XCTAssertEqual(PositionTabModel.gridBoxSide(forAvailableHeight: 200), 96, "N.1")
    }

    func testGridBoxSideOnRegularPanelHeight() {
        XCTAssertEqual(PositionTabModel.gridBoxSide(forAvailableHeight: 120), 96, "N.1: 120 - 12*2")
    }

    func testGridBoxSideOnSmallScreenPanelHeight() {
        XCTAssertEqual(PositionTabModel.gridBoxSide(forAvailableHeight: 104), 88, "N.1: 104 - 8*2")
    }

    func testGridBoxVerticalInsetSwitchesAt120() {
        XCTAssertEqual(PositionTabModel.gridBoxVerticalInset(forAvailableHeight: 120), 12)
        XCTAssertEqual(PositionTabModel.gridBoxVerticalInset(forAvailableHeight: 119), 8)
        XCTAssertEqual(PositionTabModel.gridBoxVerticalInset(forAvailableHeight: 104), 8)
        XCTAssertEqual(PositionTabModel.gridBoxVerticalInset(forAvailableHeight: .infinity), 12)
    }

    func testGridBoxSideHasNoFloor() {
        XCTAssertEqual(PositionTabModel.gridBoxSide(forAvailableHeight: 100), 84, "100 - 8*2")
    }

    func testGridBoxSideNeverGoesNegative() {
        XCTAssertEqual(PositionTabModel.gridBoxSide(forAvailableHeight: 10), 0)
        XCTAssertEqual(PositionTabModel.gridBoxSide(forAvailableHeight: 0), 0)
    }

    func testGridBoxSideFallsBackToMaxWhenNotYetMeasured() {
        XCTAssertEqual(PositionTabModel.gridBoxSide(forAvailableHeight: .infinity), 96, "N.1")
    }

    // MARK: - 失敗回報為 lastError

    func testUpdateProfileFailureIsSurfacedAsLastError() {
        struct DummyError: Error {}
        let spy = Spy()
        spy.shouldThrow = DummyError()
        let model = makeModel(profile: baselineProfile(), spy: spy)
        model.selectAnchor(.topLeading)
        XCTAssertNotNil(model.lastError)
        XCTAssertEqual(model.profile.position, .anchor(.topLeading))
    }
}
