import XCTest
@testable import DaysCam

/// #649-8: the camera and export wording of a permission failure differ.
final class PhotoSaveErrorMessageTests: XCTestCase {
    func testCameraPermissionFailureAsksForAnotherShot() {
        XCTAssertEqual(PhotoSaveError.permissionDenied.cameraDisplayMessage,
                       "這張照片沒有存起來。請到「設定」›「DaysCam」›「照片」允許取用後再拍一次。")
    }

    func testSharedAndExportWordingNeverSaysShootAgain() {
        XCTAssertFalse(PhotoSaveError.permissionDenied.displayMessage.contains("再拍一次"))
        XCTAssertEqual(PhotoExportError.saveFailed(.permissionDenied).message,
                       "新照片沒有存起來。請到「設定」›「DaysCam」›「照片」允許取用後再匯出一次。")
    }
}
