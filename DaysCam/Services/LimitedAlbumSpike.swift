#if DEBUG
import Photos
import SwiftUI
import UIKit

/// Temporary device-only PhotoKit probe for issue #306.
@MainActor
final class LimitedAlbumSpike: ObservableObject {
    @Published var log = UserDefaults.standard.string(forKey: "spike75.log") ?? ""
    @Published var busy = false
    private let defaults = UserDefaults.standard
    private var albumID: String? {
        get { defaults.string(forKey: "spike75.albumID") }
        set { defaults.set(newValue, forKey: "spike75.albumID") }
    }

    func record(_ message: String) {
        let line = "\(Date().ISO8601Format()) \(message)"
        print("[TASK-75] \(line)")
        log += line + "\n"
        defaults.set(log, forKey: "spike75.log")
    }

    func inspect(_ label: String) -> PHAssetCollection? {
        record("\(label) device=\(UIDevice.current.model) iOS=\(UIDevice.current.systemVersion) readWrite=\(PHPhotoLibrary.authorizationStatus(for: .readWrite)) addOnly=\(PHPhotoLibrary.authorizationStatus(for: .addOnly)) rememberedID=\(albumID ?? "nil")")
        let byID = albumID.flatMap {
            PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [$0], options: nil).firstObject
        }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title = %@", "DaysCam")
        let byTitle = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: options)
        record("fetch id: \(describe(byID)); title matches=\(byTitle.count)")
        byTitle.enumerateObjects { album, _, _ in
            self.record("fetch title: \(self.describe(album))")
        }
        return byID ?? byTitle.firstObject
    }

    private func describe(_ album: PHAssetCollection?) -> String {
        guard let album else { return "nil" }
        return "\(album.localIdentifier) title=\(album.localizedTitle ?? "nil") visiblePhotoCount=\(PHAsset.fetchAssets(in: album, options: nil).count)"
    }

    private func authorize(_ level: PHAccessLevel) async {
        let status = await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: level) { continuation.resume(returning: $0) }
        }
        record("request \(level): \(status)")
    }

    private func change(_ label: String, _ block: @escaping () -> Void) async -> Bool {
        let result: (Bool, Error?) = await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges(block) { success, error in
                continuation.resume(returning: (success, error))
            }
        }
        let error = result.1 as NSError?
        record("\(label) performChanges success=\(result.0) error.domain=\(error?.domain ?? "nil") code=\(error.map { String($0.code) } ?? "nil") description=\(error?.localizedDescription ?? "nil")")
        return result.0
    }

    func create(_ scenario: String) async {
        busy = true
        defer { busy = false }
        if scenario == "L5" { await authorize(.addOnly) }
        await authorize(.readWrite)
        let existing = inspect("\(scenario) before")
        if let existing {
            albumID = existing.localIdentifier
            record("\(scenario) reuse visible album; no creation change block")
        } else {
            var candidate: String?
            let success = await change("\(scenario) create album") {
                candidate = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: "DaysCam")
                    .placeholderForCreatedAssetCollection.localIdentifier
            }
            record("creation placeholderID=\(candidate ?? "nil")")
            if success { albumID = candidate }
        }
        _ = inspect("\(scenario) after")
    }

    func save(_ image: UIImage, scenario: String) async {
        busy = true
        defer { busy = false }
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            record("\(scenario) JPEG encoding failed")
            return
        }
        let existing = inspect("\(scenario) before")
        // Existing-album scenarios must not silently create a replacement.
        guard let existing else {
            record("\(scenario) no fetchable existing album; skipped write (cannot target collection by placeholder from a previous transaction)")
            return
        }
        var assetID: String?
        var albumRequestAvailable = false
        let success = await change("\(scenario) combined") {
            let creation = PHAssetCreationRequest.forAsset()
            creation.addResource(with: .photo, data: data, options: nil)
            let placeholder = creation.placeholderForCreatedAsset
            assetID = placeholder?.localIdentifier
            let request = PHAssetCollectionChangeRequest(for: existing)
            albumRequestAvailable = request != nil
            if let placeholder { request?.addAssets([placeholder] as NSArray) }
        }
        record("\(scenario) assetID=\(assetID ?? "nil") albumChangeRequestAvailable=\(albumRequestAvailable)")
        _ = inspect("\(scenario) after combined")
        if !success || !albumRequestAvailable {
            record("\(scenario) fallback: creates another asset; inspect Recents for duplicates")
            var retryID: String?
            let created = await change("\(scenario) split 1 create asset") {
                let creation = PHAssetCreationRequest.forAsset()
                creation.addResource(with: .photo, data: data, options: nil)
                retryID = creation.placeholderForCreatedAsset?.localIdentifier
            }
            record("\(scenario) split assetID=\(retryID ?? "nil")")
            _ = inspect("\(scenario) after split 1")
            if created, let retryID {
                let assets = PHAsset.fetchAssets(withLocalIdentifiers: [retryID], options: nil)
                record("\(scenario) split asset fetch count=\(assets.count)")
                if assets.count > 0 {
                    var available = false
                    _ = await change("\(scenario) split 2 add asset") {
                        let request = PHAssetCollectionChangeRequest(for: existing)
                        available = request != nil
                        request?.addAssets(assets)
                    }
                    record("\(scenario) split albumChangeRequestAvailable=\(available)")
                } else { record("\(scenario) split 2 skipped: asset not fetchable") }
            }
            _ = inspect("\(scenario) after split 2")
        }
    }
}

/// Debug-only research screen; does not use production permission routing.
struct LimitedAlbumSpikeView: View {
    @StateObject private var probe = LimitedAlbumSpike()
    @State private var captureScenario: String?
    @State private var showingCamera = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("TASK-75 實機研究；先照 Issue #306 準備權限／相簿。")
                    ForEach(["L1", "L4", "L5"], id: \.self) { scenario in
                        Button("\(scenario)：請求權限 → fetch／建立相簿") {
                            Task { await probe.create(scenario) }
                        }
                    }
                    ForEach(["L2", "L3", "L6", "L7"], id: \.self) { scenario in
                        Button("\(scenario)：拍照 → 加入既有相簿") {
                            captureScenario = scenario
                            showingCamera = true
                        }
                    }
                    Button("重新 fetch／記錄目前權限") { _ = probe.inspect("manual") }
                    ShareLink("分享完整紀錄", item: probe.log)
                    Text(probe.log).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }.padding()
            }
            .navigationTitle("Limited Album Spike")
            .disabled(probe.busy)
            .sheet(isPresented: $showingCamera) {
                SpikeCamera { image in
                    showingCamera = false
                    if let image, let scenario = captureScenario {
                        Task { await probe.save(image, scenario: scenario) }
                    }
                }
            }
        }
    }
}

private struct SpikeCamera: UIViewControllerRepresentable {
    let completion: (UIImage?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let completion: (UIImage?) -> Void
        init(completion: @escaping (UIImage?) -> Void) { self.completion = completion }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            completion(info[.originalImage] as? UIImage)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { completion(nil) }
    }
}
#endif
