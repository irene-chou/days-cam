import SwiftUI
import UIKit
import XCTest
@testable import DaysCam

/// TASK-148 (#515), 148.6: renders the whole font list (every font not yet
/// downloaded except PingFang, so every row is drawn from its preview image)
/// at the width of the simulator it runs on, and cuts it into pages. With
/// `DAYSCAM_UI_SHOT_DIR` in the runner's environment the pages are written
/// there as PNGs; they are always attached to the result.
@MainActor
final class FontListSnapshotTests: XCTestCase {
    func testRenderTheWholeFontListInPages() throws {
        let width = UIScreen.main.bounds.width
        let library = FakeFontLibrary()
        let model = FontLibraryModel(profileID: UUID(), currentFontID: .pingFang, library: library,
                                     profiles: { [] }, applyFont: { _, _ in })
        model.listDidAppear()
        let padding: CGFloat = 10
        let host = UIHostingController(rootView: FontListView(model: model)
            .padding(.horizontal, padding)
            .frame(width: width)
            .background(CameraTheme.background))
        let height: CGFloat = 6000
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        let fitted = host.sizeThatFits(in: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)).height
        XCTAssertGreaterThan(fitted, 2000, "the whole list was laid out")
        host.view.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        let full = UIGraphicsImageRenderer(size: CGSize(width: width, height: fitted), format: format).image { _ in
            host.view.drawHierarchy(in: CGRect(x: 0, y: 0, width: width, height: fitted), afterScreenUpdates: true)
        }
        let pageHeight: CGFloat = 900
        let pages = Int(ceil(fitted / pageHeight))
        for page in 0..<pages {
            let top = CGFloat(page) * pageHeight
            let slice = min(pageHeight, fitted - top)
            let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: slice), format: format).image { _ in
                full.draw(at: CGPoint(x: 0, y: -top))
            }
            let name = "148.6_font-list-\(page + 1)"
            let attachment = XCTAttachment(image: image)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
            if let path = ProcessInfo.processInfo.environment["DAYSCAM_UI_SHOT_DIR"], !path.isEmpty,
               let png = image.pngData() {
                let directory = URL(fileURLWithPath: path, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try png.write(to: directory.appendingPathComponent("\(name).png"))
            }
        }
    }
}
