import SwiftUI
import UIKit
import XCTest
@testable import DaysCam

/// Regression coverage for #108's real-device QA finding: the nine-point
/// grid's dots rendered clustered in a small band near the top of the box
/// instead of spread across its full height, even though `gridBoxSide`
/// itself (the pure function deciding the box's side) was — and still is —
/// correct, and an isolated `#Preview` looked fine. `PositionTabModelTests`
/// already covers `gridBoxSide`'s own math; nothing at that level would ever
/// have caught this, since the bug was `LazyVGrid` silently not stretching
/// its *rows* to fill an imposed height (see `PositionTabView.grid`'s doc
/// comment) — a real layout behavior only a hosted, rendered view can show.
///
/// Follows `ColorSchemeEscapeTests`' pattern: a real `UIHostingController`/
/// `UIWindow`, not `#Preview` — `#Preview`'s own render path did not
/// reproduce the bug QA found on an actual device, so this deliberately
/// avoids that path too.
@MainActor
final class PositionTabViewGridFillTests: XCTestCase {
    func testNineDotsSpreadAcrossTheFullBoxHeightNotClusteredNearOneEdge() throws {
        let profile = CameraProfile(name: "測試",
                                     startDate: DateComponents(year: 2026, month: 1, day: 1),
                                     position: .anchor(.bottomTrailing))
        let model = PositionTabModel(profile: profile) { _ in }
        // 300 clamps to `gridBoxMaxSide` (132) — matches #108's iPhone 16 QA
        // report, where the box itself was already correctly sized (~132pt
        // square) but the dots inside it were not spread across it.
        let view = PositionTabView(model: model, availableHeight: 300)

        let dotFrames = renderedDotFrames(hosting: view, hostWidth: 375, hostHeight: 400)
        // Fail fast rather than crash on the force-unwraps below: on iOS 27
        // SwiftUI no longer exposes `Circle` as a `UIView` (the hosting view
        // has no subviews), so this finds 0 dots there.
        XCTAssertEqual(dotFrames.count, 9)
        guard dotFrames.count == 9 else { return }

        // Bucket to the nearest 5pt: the selected dot is 14pt across versus
        // 7pt for the other eight, so their centers can differ by a
        // sub-point rounding amount within the *same* row without that
        // meaning a fourth row actually exists.
        let rowCenters = Set(dotFrames.map { ($0.midY / 5).rounded() * 5 }).sorted()
        XCTAssertEqual(rowCenters.count, 3, "九個點應該落在三個不同的列上，量到的列中心：\(rowCenters)")

        // The box's own grid area is `gridBoxSide - 2*4` (the `.padding(4)`
        // on each side, `PositionTabView.body`) — 124pt here. Each row
        // should own roughly a third of that, so the top and bottom row
        // centers should be far apart, not clustered together the way the
        // pre-fix `LazyVGrid` left them (under 25pt apart in the original
        // bug report).
        let rowSpan = try XCTUnwrap(rowCenters.last) - XCTUnwrap(rowCenters.first)
        XCTAssertGreaterThan(rowSpan, 60, "三列應該分散在小框的整個高度，不是擠在一小段範圍內")
    }

    func testDotsFillBothAxesEquallyOnAConstrainedHeightLikeIPhoneSE() throws {
        // A moderate, non-max `availableHeight`, sanity-checking that the
        // box stays square once `gridBoxSide` is no longer pinned at
        // `gridBoxMaxSide` the way `testNineDotsSpreadAcross...` above always
        // clamps to. Not a claim that this covers every real iPhone SE
        // scenario: a *separate*, real-device #122 QA report found the box
        // non-square at SE's actual (much smaller, ~36pt) `gridBoxSide` —
        // the human's 2026-09-29 call was to track that as its own,
        // not-yet-diagnosed issue rather than fold a fix into this PR, so
        // this test intentionally does not attempt to reproduce it.
        let profile = CameraProfile(name: "測試",
                                     startDate: DateComponents(year: 2026, month: 1, day: 1),
                                     position: .anchor(.bottomTrailing))
        let model = PositionTabModel(profile: profile) { _ in }
        let availableHeight: CGFloat = 108 // gridBoxSide = 108 - 24 = 84
        let view = PositionTabView(model: model, availableHeight: availableHeight)

        let dotFrames = renderedDotFrames(hosting: view, hostWidth: 375, hostHeight: 200)
        // Fail fast rather than crash on the force-unwraps below: on iOS 27
        // SwiftUI no longer exposes `Circle` as a `UIView` (the hosting view
        // has no subviews), so this finds 0 dots there.
        XCTAssertEqual(dotFrames.count, 9)
        guard dotFrames.count == 9 else { return }

        let xSpan = try XCTUnwrap(dotFrames.map(\.midX).max()) - XCTUnwrap(dotFrames.map(\.midX).min())
        let ySpan = try XCTUnwrap(dotFrames.map(\.midY).max()) - XCTUnwrap(dotFrames.map(\.midY).min())
        // Both spans should be close to each other (the box is square) and
        // comfortably above a "clustered in a sliver" span like the ~25pt
        // `ySpan` the pre-fix bug produced.
        XCTAssertEqual(xSpan, ySpan, accuracy: 3, "點的橫向、縱向分佈範圍應該接近相等（正方形），量到 xSpan=\(xSpan) ySpan=\(ySpan)")
        XCTAssertGreaterThan(ySpan, 30, "縱向不該被壓縮成一小段")
    }

    /// Hosts `view` in a real window, draws it to a bitmap and returns every
    /// dot's frame (in window coordinates).
    ///
    /// Pixel-based on purpose: from iOS 27 the hosting view has no `UIView`
    /// subviews at all (SwiftUI draws into a single layer), so the earlier
    /// view-hierarchy walk found 0 dots there. A dot is a connected blob of
    /// pixels darker than the box fill and the page, at most 16pt across,
    /// nearly square and mostly filled (a circle fills about 78% of its
    /// bounding box; glyphs of the position name next to the box fill far
    /// less).
    ///
    /// Polls until nine dots appear (or a 3s timeout) instead of a single
    /// fixed wait; the simulators are shared by several agents at once.
    private func renderedDotFrames(hosting view: PositionTabView, hostWidth: CGFloat, hostHeight: CGFloat) -> [CGRect] {
        let hosting = UIHostingController(rootView: view.frame(width: hostWidth))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: hostWidth, height: hostHeight))
        window.overrideUserInterfaceStyle = .light
        window.rootViewController = hosting
        window.makeKeyAndVisible()
        hosting.view.frame = CGRect(x: 0, y: 0, width: hostWidth, height: hostHeight)

        var frames: [CGRect] = []
        let deadline = Date().addingTimeInterval(3)
        repeat {
            hosting.view.setNeedsLayout()
            hosting.view.layoutIfNeeded()
            frames = dotFrames(in: hosting.view)
            if frames.count == 9 { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline

        return frames
    }

    private func dotFrames(in view: UIView) -> [CGRect] {
        let width = Int(view.bounds.width)
        let height = Int(view.bounds.height)
        guard width > 0, height > 0 else { return [] }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: view.bounds.size, format: format).image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        guard let cgImage = image.cgImage else { return [] }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drewPixels = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drewPixels else { return [] }

        func isDark(_ x: Int, _ y: Int) -> Bool {
            let offset = (y * width + x) * 4
            let luminance = (0.299 * Double(pixels[offset]) + 0.587 * Double(pixels[offset + 1])
                             + 0.114 * Double(pixels[offset + 2])) / 255
            return luminance < 0.8
        }

        var visited = [Bool](repeating: false, count: width * height)
        var result: [CGRect] = []
        for startY in 0..<height {
            for startX in 0..<width where !visited[startY * width + startX] && isDark(startX, startY) {
                var stack = [(startX, startY)]
                visited[startY * width + startX] = true
                var minX = startX, maxX = startX, minY = startY, maxY = startY, count = 0
                while let (x, y) = stack.popLast() {
                    count += 1
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                    for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, ny >= 0, nx < width, ny < height,
                              !visited[ny * width + nx], isDark(nx, ny) else { continue }
                        visited[ny * width + nx] = true
                        stack.append((nx, ny))
                    }
                }
                let blobWidth = maxX - minX + 1, blobHeight = maxY - minY + 1
                let fillRatio = Double(count) / Double(blobWidth * blobHeight)
                if blobWidth >= 5, blobWidth <= 16, abs(blobWidth - blobHeight) <= 1, fillRatio >= 0.7 {
                    result.append(CGRect(x: minX, y: minY, width: blobWidth, height: blobHeight))
                }
            }
        }
        return result
    }
}
