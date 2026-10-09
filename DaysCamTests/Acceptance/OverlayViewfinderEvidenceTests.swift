import SwiftUI
import XCTest
@testable import DaysCam

/// Issue #159: real viewfinder composition beside the baked placeholder photo.
@MainActor
final class OverlayViewfinderEvidenceTests: XCTestCase {
    func testViewfinderAndBakedPhotoEvidence() throws {
        let frame = CGSize(width: 300, height: 400)
        let text = "小寶 第 10 天"
        let cases: [(String, OverlayStyle)] = [
            ("thick-stroke", OverlayStyle(outline: .stroke, strokeWidth: 4, shadow: .none)),
            ("solid-box", OverlayStyle(outline: .box, shadow: .none)),
            ("hard-shadow", OverlayStyle(outline: .none, shadow: .hard)),
            ("thin-stroke", OverlayStyle(outline: .stroke, shadow: .none)),
            ("translucent-box", OverlayStyle(outline: .box, autoOutlineOpacity: 0.5, shadow: .soft)),
            ("glow", OverlayStyle(outline: .none, shadow: .glow))
        ]
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let background = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 1200), format: format).image { context in
            UIColor(white: 0.25, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 900, height: 1200))
        }
        for (name, style) in cases {
            let baked = try XCTUnwrap(OverlayRenderer().bake(image: background, text: text, style: style,
                                                            placement: .anchor(.bottomTrailing), font: .pingFang))
            let comparison = HStack(spacing: 12) {
                VStack {
                    Text("觀景窗 preview")
                    ZStack {
                        Image(uiImage: background).resizable()
                        OverlayTextView(text: text, style: style, placement: .anchor(.bottomTrailing), frameSize: frame)
                    }.frame(width: frame.width, height: frame.height)
                }
                VStack {
                    Text("照片 bake")
                    Image(uiImage: baked).resizable().frame(width: frame.width, height: frame.height)
                }
            }.font(.system(size: 14)).padding(12).background(Color.white)
                .environment(\.displayScale, 3).environment(\.colorScheme, .light)
            let renderer = ImageRenderer(content: comparison)
            renderer.scale = 3
            let attachment = XCTAttachment(image: try XCTUnwrap(renderer.uiImage))
            attachment.name = "173_V8_iPhone16_\(name)_preview-bake"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testInteractiveBodyFrameAndLongTextEvidence() throws {
        let frame = CGSize(width: 300, height: 400)
        let content = HStack(spacing: 12) {
            ForEach([OverlayPosition.topLeading, .bottomTrailing], id: \.self) { anchor in
                ZStack {
                    Color(white: 0.25)
                    OverlayTextView(text: "小寶的一百天紀念日 第100天", style: OverlayStyle(outline: .stroke, strokeWidth: 4, shadow: .hard),
                        placement: .anchor(anchor), frameSize: frame, onDragChanged: { _, _ in })
                }.frame(width: frame.width, height: frame.height)
            }
        }.padding(12).background(Color.white).environment(\.displayScale, 3)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        let attachment = XCTAttachment(image: try XCTUnwrap(renderer.uiImage))
        attachment.name = "173_V4-V5_iPhone16_longtext-body-frame"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
