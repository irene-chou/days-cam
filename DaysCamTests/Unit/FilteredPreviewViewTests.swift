import CoreImage
import XCTest
@testable import DaysCam

/// The live-tone viewfinder (#590): the preview path and the photo path run
/// the same filters, `.standard` is never processed, and the Metal draw lands
/// right side up and aspect-filled.
final class FilteredPreviewViewTests: XCTestCase {
    private func solidImage(_ color: CIColor, size: CGSize) -> CIImage {
        CIImage(color: color).cropped(to: CGRect(origin: .zero, size: size))
    }

    private func makeCGImage(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 0.5, green: 0.45, blue: 0.4, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 2))
        return try XCTUnwrap(context.makeImage())
    }

    private func bytes(of image: CGImage) -> Data? {
        image.dataProvider?.data as Data?
    }

    func testStandardIsNeverProcessed() {
        let image = solidImage(CIColor(red: 0.3, green: 0.3, blue: 0.3), size: CGSize(width: 8, height: 8))
        XCTAssertTrue(ColorToneRenderer.filtered(.standard, image) === image)
    }

    func testPreviewAndPhotoPathsGiveTheSamePixelsForEveryTone() throws {
        let source = try makeCGImage(width: 64, height: 48)
        let input = CIImage(cgImage: source)
        let colorSpace = try XCTUnwrap(source.colorSpace)
        for tone in ColorTone.allCases where tone != .standard {
            let photo = try XCTUnwrap(ColorToneRenderer.apply(tone, to: source), "\(tone)")
            let filtered = try XCTUnwrap(ColorToneRenderer.filtered(tone, input))
            let preview = try XCTUnwrap(ColorToneRenderer.context.createCGImage(
                filtered, from: input.extent, format: .RGBA8, colorSpace: colorSpace))
            XCTAssertEqual(bytes(of: photo), bytes(of: preview), "590 \(tone): same pixels either path")
            XCTAssertNotEqual(bytes(of: photo), bytes(of: source), "\(tone) changed something")
        }
    }

    func testAspectFillCentersAndCrops() {
        let wide = FilteredPreviewMetalView.aspectFillTransform(from: CGSize(width: 100, height: 50),
                                                                to: CGSize(width: 50, height: 50))
        XCTAssertEqual(wide.a, 1, accuracy: 0.001)
        XCTAssertEqual(wide.tx, -25, accuracy: 0.001, "sides cropped equally")
        let tall = FilteredPreviewMetalView.aspectFillTransform(from: CGSize(width: 30, height: 60),
                                                                to: CGSize(width: 60, height: 60))
        XCTAssertEqual(tall.a, 2, accuracy: 0.001)
        XCTAssertEqual(tall.ty, -30, accuracy: 0.001, "top and bottom cropped equally")
    }

    /// Core Image's convention is kept: what is at high y in the picture stays
    /// at high y (the top of the screen) after the fit. There is deliberately
    /// no flip, and no texture readback test: `CIContext.render(_:to:)` into
    /// a drawable needs none (confirmed on a device), and `getBytes` row 0 does
    /// not say which way up the screen shows the texture.
    func testFitKeepsTheTopOfThePictureAtHighY() {
        let size = CGSize(width: 40, height: 80)
        let transform = FilteredPreviewMetalView.aspectFillTransform(from: size, to: CGSize(width: 20, height: 40))
        let top = CGPoint(x: 20, y: 80).applying(transform)
        let bottom = CGPoint(x: 20, y: 0).applying(transform)
        XCTAssertGreaterThan(top.y, bottom.y)
        XCTAssertEqual(transform.d, 0.5, accuracy: 0.001, "scaled, never mirrored vertically")
    }

    func testTheHandlerIsRemovedWhenTheViewGoesAway() {
        let service = CameraService()
        let coordinator = FilteredPreviewView.Coordinator(service: service)
        let view = FilteredPreviewMetalView()
        coordinator.install(on: view)
        XCTAssertTrue(service.isPreviewFrameHandlerActive)
        FilteredPreviewView.dismantleUIView(view, coordinator: coordinator)
        XCTAssertFalse(service.isPreviewFrameHandlerActive, "590 no frames once the view is gone")
    }

    func testDismantlingAnOldViewLeavesTheReplacementsHandler() {
        let service = CameraService()
        let oldCoordinator = FilteredPreviewView.Coordinator(service: service)
        let newCoordinator = FilteredPreviewView.Coordinator(service: service)
        let oldView = FilteredPreviewMetalView()
        let newView = FilteredPreviewMetalView()
        oldCoordinator.install(on: oldView)
        newCoordinator.install(on: newView) // the new view is made before the old one is torn down
        FilteredPreviewView.dismantleUIView(oldView, coordinator: oldCoordinator)
        XCTAssertTrue(service.isPreviewFrameHandlerActive)
        FilteredPreviewView.dismantleUIView(newView, coordinator: newCoordinator)
        XCTAssertFalse(service.isPreviewFrameHandlerActive)
    }
}
