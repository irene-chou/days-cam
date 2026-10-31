import Photos
import UIKit

#if DEBUG
/// A photo library that is undecided until asked, then answers with `mode`.
/// Never saves anything.
final class UITestPhotoLibrary: PhotoLibraryAccessing {
    private var status: PHAuthorizationStatus = .notDetermined
    private let answer: PHAuthorizationStatus
    let startsOn: Bool

    init?(mode: String) {
        switch mode {
        case "full": answer = .authorized
        case "limited": answer = .limited
        case "denied": answer = .denied
        case "withdrawn": answer = .denied
        default: return nil
        }
        startsOn = mode == "withdrawn"
        if mode == "withdrawn" { status = .denied }
    }

    func authorizationStatus(for level: PHAccessLevel) -> PHAuthorizationStatus { status }

    func requestAuthorization(for level: PHAccessLevel, handler: @escaping (PHAuthorizationStatus) -> Void) {
        status = answer
        handler(answer)
    }

    func performChanges(_ changes: @escaping () -> String?,
                        completion: @escaping (Bool, String?, Error?) -> Void) {
        completion(false, nil, nil)
    }

    func saveToAlbum(_ image: UIImage, albumIdentifier: String?, albumTitle: String,
                     completion: @escaping (AlbumWriteResult) -> Void) {
        completion(AlbumWriteResult(succeeded: false, assetIdentifier: nil, albumIdentifier: nil, error: nil))
    }
}
#endif
