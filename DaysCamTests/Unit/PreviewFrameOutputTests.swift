import AVFoundation
import XCTest
@testable import DaysCam

/// The live-tone frame feed (#590): format, orientation, mirroring and the
/// on/off rule, against a fake connection (the simulator has no camera).
final class PreviewFrameOutputTests: XCTestCase {
    private final class FakeConnection: FrameConnectionConfigurable {
        var isVideoMirroringSupported = true
        var automaticallyAdjustsVideoMirroring = true
        var isVideoMirrored = false
        var isEnabled = true
        var videoRotationAngle: CGFloat = 0
        var supportsRotation = true
        func isVideoRotationAngleSupported(_ videoRotationAngle: CGFloat) -> Bool { supportsRotation }
    }

    func testOutputIsBGRAAndDropsLateFrames() {
        let frameOutput = PreviewFrameOutput()
        let format = frameOutput.output.videoSettings?[kCVPixelBufferPixelFormatTypeKey as String] as? OSType
        XCTAssertEqual(format, kCVPixelFormatType_32BGRA)
        XCTAssertTrue(frameOutput.output.alwaysDiscardsLateVideoFrames)
    }

    func testConnectionIsUprightAndMirroredOnlyForTheFrontCamera() {
        let back = FakeConnection()
        PreviewFrameOutput.configure(back, facing: .back, isActive: true)
        XCTAssertEqual(back.videoRotationAngle, 90)
        XCTAssertFalse(back.isVideoMirrored)
        let front = FakeConnection()
        PreviewFrameOutput.configure(front, facing: .front, isActive: true)
        XCTAssertTrue(front.isVideoMirrored)
    }

    func testConnectionIsOffUntilAHandlerIsSet() {
        let frameOutput = PreviewFrameOutput()
        let connection = FakeConnection()
        PreviewFrameOutput.configure(connection, facing: .back, isActive: frameOutput.isActive)
        XCTAssertFalse(connection.isEnabled, "standard: no frames are produced")
        frameOutput.setHandler { _ in }
        PreviewFrameOutput.configure(connection, facing: .back, isActive: frameOutput.isActive)
        XCTAssertTrue(connection.isEnabled)
        frameOutput.setHandler(nil)
        XCTAssertFalse(frameOutput.isActive)
    }

    func testUnsupportedRotationIsLeftAlone() {
        let connection = FakeConnection()
        connection.supportsRotation = false
        PreviewFrameOutput.configure(connection, facing: .back, isActive: true)
        XCTAssertEqual(connection.videoRotationAngle, 0)
    }

    func testAddingTheFrameOutputLeavesThePhotoOutputAlone() {
        let photoOutput = AVCapturePhotoOutput()
        let before = (photoOutput.isHighResolutionCaptureEnabled, photoOutput.maxPhotoQualityPrioritization)
        let session = AVCaptureSession()
        _ = PreviewFrameOutput()
        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
        XCTAssertEqual(before.0, photoOutput.isHighResolutionCaptureEnabled)
        XCTAssertEqual(before.1, photoOutput.maxPhotoQualityPrioritization)
    }
}
