import XCTest
@testable import DaysCam

/// A capture device with a chosen lens layout, recording what zoom did to it.
private final class FakeLensDevice: ZoomableCaptureDevice {
    let minAvailableVideoZoomFactor: CGFloat
    let maxAvailableVideoZoomFactor: CGFloat
    let zoomLens: ZoomLens
    var videoZoomFactor: CGFloat
    var isRampingVideoZoom = false
    private(set) var rampTargets: [(factor: CGFloat, rate: Float)] = []
    private(set) var cancelCount = 0
    private(set) var isLocked = false

    init(lens: ZoomLens, min: CGFloat = 1, max: CGFloat = 16) {
        zoomLens = lens
        minAvailableVideoZoomFactor = min
        maxAvailableVideoZoomFactor = max
        videoZoomFactor = min
    }

    func lockForConfiguration() throws { isLocked = true }
    func unlockForConfiguration() { isLocked = false }
    func cancelVideoZoomRamp() { cancelCount += 1; isRampingVideoZoom = false }
    func ramp(toVideoZoomFactor factor: CGFloat, withRate rate: Float) {
        XCTAssertTrue(isLocked, "ramp without the configuration lock")
        rampTargets.append((factor, rate))
    }
}

/// Display factor 1× against the device's own `videoZoomFactor`, the preset
/// list per lens layout, and the zoom applied through both (issue #279, 62.7).
final class ZoomPlanTests: XCTestCase {
    private let triple = ZoomLens(hasUltraWide: true, switchOverFactors: [2, 6])
    private let dualWide = ZoomLens(hasUltraWide: true, switchOverFactors: [2])
    private let dualTele = ZoomLens(hasUltraWide: false, switchOverFactors: [2])
    private let single = ZoomLens()

    private func presets(_ lens: ZoomLens, min: CGFloat = 1, max: CGFloat = 60,
                         crop: Bool = true) -> [CGFloat] {
        ZoomPlan.make(lens: lens, minAvailable: min, maxAvailable: max, offersCropPresets: crop)
            .presets.map(\.displayFactor)
    }

    // MARK: Conversion

    func testWithAnUltraWideOneTimesIsTheSwitchOverFactor() {
        XCTAssertEqual(triple.baseDeviceFactor, 2)
        XCTAssertEqual(triple.deviceFactor(forDisplay: 1), 2)
        XCTAssertEqual(triple.deviceFactor(forDisplay: 0.5), 1)
        XCTAssertEqual(triple.displayFactor(forDevice: 6), 3)
    }

    func testWithoutAnUltraWideDisplayAndDeviceFactorsAreTheSame() {
        for lens in [single, dualTele] {
            XCTAssertEqual(lens.baseDeviceFactor, 1)
            XCTAssertEqual(lens.deviceFactor(forDisplay: 2.5), 2.5)
            XCTAssertEqual(lens.displayFactor(forDevice: 2.5), 2.5)
        }
    }

    /// A device that does not report a switch-over still has a sane 1×.
    func testUltraWideWithoutSwitchOverFactorsAssumesTwo() {
        XCTAssertEqual(ZoomLens(hasUltraWide: true, switchOverFactors: []).baseDeviceFactor, 2)
    }

    // MARK: Range

    func testRangeIsInDisplayFactorsAndCappedAtTen() {
        let plan = ZoomPlan.make(lens: triple, minAvailable: 1, maxAvailable: 123, offersCropPresets: true)
        XCTAssertEqual(plan.range, ZoomRange(minimum: 0.5, maximum: 10))
    }

    func testRangeKeepsADeviceMaximumBelowTheCap() {
        // Device zoom 12 on a base of 2 is 6× displayed.
        let plan = ZoomPlan.make(lens: dualWide, minAvailable: 1, maxAvailable: 12, offersCropPresets: true)
        XCTAssertEqual(plan.range, ZoomRange(minimum: 0.5, maximum: 6))
    }

    // MARK: Presets

    func testTripleCameraOffersPointFiveOneTwoThree() {
        XCTAssertEqual(presets(triple), [0.5, 1, 2, 3])
    }

    func testTripleCameraWithAFiveTimesTelephotoOffersFive() {
        XCTAssertEqual(presets(ZoomLens(hasUltraWide: true, switchOverFactors: [2, 10])), [0.5, 1, 2, 5])
    }

    func testDualWideCameraOffersPointFiveOneTwo() {
        XCTAssertEqual(presets(dualWide), [0.5, 1, 2])
    }

    /// The telephoto of a dual camera sits at 2×, which 2× already is.
    func testDualCameraWithoutUltraWideOffersOneTwo() {
        XCTAssertEqual(presets(dualTele), [1, 2])
    }

    func testDualCameraWithALongerTelephotoAddsIt() {
        XCTAssertEqual(presets(ZoomLens(hasUltraWide: false, switchOverFactors: [3])), [1, 2, 3])
    }

    func testSingleLensCameraOffersOneTwo() {
        XCTAssertEqual(presets(single), [1, 2])
    }

    func testTwoTimesIsLeftOutWhenTheDeviceCannotReachIt() {
        XCTAssertEqual(presets(single, max: 1.5), [1])
    }

    func testFrontCameraOffersOnlyOne() {
        XCTAssertEqual(presets(single, crop: false), [1])
    }

    func testPresetsAreAscendingWithoutDuplicates() {
        let list = presets(ZoomLens(hasUltraWide: true, switchOverFactors: [2, 4, 4]))
        XCTAssertEqual(list, list.sorted())
        XCTAssertEqual(Set(list).count, list.count)
    }

    // MARK: Applying

    /// 1× on a virtual device with an ultra-wide is device zoom 2, not 1.
    func testResetToOneTimesSetsTheBaseFactorOnAVirtualDevice() {
        let device = FakeLensDevice(lens: triple)
        XCTAssertEqual(CameraService.applyZoom(1, to: device), 1)
        XCTAssertEqual(device.videoZoomFactor, 2)
    }

    func testPointFiveIsTheDevicesOwnMinimum() {
        let device = FakeLensDevice(lens: triple)
        XCTAssertEqual(CameraService.applyZoom(0.5, to: device), 0.5)
        XCTAssertEqual(device.videoZoomFactor, 1)
    }

    func testDisplayFactorBelowTheRangeIsRaisedToIt() {
        let device = FakeLensDevice(lens: triple)
        XCTAssertEqual(CameraService.applyZoom(0.2, to: device), 0.5)
        XCTAssertEqual(device.videoZoomFactor, 1)
    }

    func testDisplayFactorAboveTheCapIsLoweredToTenTimes() {
        let device = FakeLensDevice(lens: triple, max: 123)
        XCTAssertEqual(CameraService.applyZoom(40, to: device), 10)
        XCTAssertEqual(device.videoZoomFactor, 20)
    }

    func testWithoutAnUltraWideNothingIsScaled() {
        let device = FakeLensDevice(lens: single)
        XCTAssertEqual(CameraService.applyZoom(3, to: device), 3)
        XCTAssertEqual(device.videoZoomFactor, 3)
    }

    func testRampingGoesThroughRampAtTheDeviceFactor() {
        let device = FakeLensDevice(lens: triple)
        device.videoZoomFactor = 2
        CameraService.applyZoom(1.5, to: device, rampRate: CameraService.presetRampRate)
        XCTAssertEqual(device.rampTargets.count, 1)
        XCTAssertEqual(device.rampTargets.first?.factor, 3)
        XCTAssertEqual(device.rampTargets.first?.rate, CameraService.presetRampRate)
        XCTAssertEqual(device.videoZoomFactor, 2, "a ramp does not jump the factor")
    }

    /// #601: a ramp across a lens switch-over still ramps, so the main camera
    /// has time to take over (a direct jump showed a distorted frame first).
    func testRampAcrossASwitchOverStillRamps() {
        let device = FakeLensDevice(lens: triple)
        CameraService.applyZoom(2, to: device, rampRate: CameraService.presetRampRate)
        XCTAssertEqual(device.rampTargets.count, 1)
        XCTAssertEqual(device.rampTargets.first?.factor, 4)
    }

    func testAPinchCancelsARunningRamp() {
        let device = FakeLensDevice(lens: triple)
        device.isRampingVideoZoom = true
        CameraService.applyZoom(1.7, to: device)
        XCTAssertEqual(device.cancelCount, 1)
        XCTAssertEqual(device.videoZoomFactor, 3.4, accuracy: 0.0001)
    }
}

/// The quick-zoom bar's text and selection (issue #279, 62.3).
final class ZoomPresetBarLogicTests: XCTestCase {
    private let presets = [0.5, 1, 2, 3].map { ZoomPreset(displayFactor: CGFloat($0)) }

    func testNearestPresetIsSelected() {
        XCTAssertEqual(ZoomPresetBarLogic.selectedIndex(requested: 1, presets: presets), 1)
        XCTAssertEqual(ZoomPresetBarLogic.selectedIndex(requested: 1.7, presets: presets), 2)
        XCTAssertEqual(ZoomPresetBarLogic.selectedIndex(requested: 0.6, presets: presets), 0)
        XCTAssertEqual(ZoomPresetBarLogic.selectedIndex(requested: 10, presets: presets), 3)
        XCTAssertNil(ZoomPresetBarLogic.selectedIndex(requested: 1, presets: []))
    }

    func testSelectedExactPresetShowsItsFactorWithTimes() {
        XCTAssertEqual(ZoomPresetBarLogic.text(for: presets[2], isSelected: true, requested: 2), "2×")
        XCTAssertEqual(ZoomPresetBarLogic.text(for: presets[0], isSelected: true, requested: 0.5), "0.5×")
    }

    /// 62.3: pinched to 1.7×, the "2" button shows the real zoom.
    func testSelectedOffPresetShowsTheActualZoom() {
        XCTAssertEqual(ZoomPresetBarLogic.text(for: presets[2], isSelected: true, requested: 1.7), "1.7×")
    }

    func testUnselectedButtonsAreBare() {
        XCTAssertEqual(ZoomPresetBarLogic.text(for: presets[0], isSelected: false, requested: 1), ".5")
        XCTAssertEqual(ZoomPresetBarLogic.text(for: presets[1], isSelected: false, requested: 2), "1")
        XCTAssertEqual(ZoomPresetBarLogic.text(for: presets[3], isSelected: false, requested: 1), "3")
    }

    func testAccessibilityLabelNamesTheFactor() {
        XCTAssertEqual(ZoomPresetBarLogic.accessibilityLabel(for: presets[2]), "焦段 2 倍")
        XCTAssertEqual(ZoomPresetBarLogic.accessibilityLabel(for: presets[0]), "焦段 0.5 倍")
    }
}
