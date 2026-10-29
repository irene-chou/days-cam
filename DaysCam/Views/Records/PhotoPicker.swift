import PhotosUI
import SwiftUI

/// The system photo picker for 加入照片 (PRD 2.0 FR-17.7): the shared library,
/// several photos at once, images only.
struct PhotoPicker: UIViewControllerRepresentable {
    /// Called once with the picked assets' identifiers; empty when the user
    /// cancelled or picked nothing the app can address.
    var onPicked: ([String]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.selectionLimit = 0
        configuration.filter = .images
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onPicked: ([String]) -> Void

        init(onPicked: @escaping ([String]) -> Void) {
            self.onPicked = onPicked
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            onPicked(results.compactMap(\.assetIdentifier))
        }
    }
}
