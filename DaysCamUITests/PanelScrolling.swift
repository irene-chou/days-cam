import XCTest

extension XCUIApplication {
    /// Scrolls the open panel's tab body until `element` sits wholly between
    /// the tab bar and the home-indicator band, which swallows taps (92.7; a
    /// 4.7-inch screen has none).
    ///
    /// A row scrolled off either edge is not in the accessibility tree, so
    /// there is no telling which way it went: this drags back to the top
    /// first, then up a little at a time (#567 made the content tab taller,
    /// pushing the lower rows below the fold on more screens). `swipeUp` and
    /// `isHittable` are unreliable in the panel, so it drags by coordinate.
    func revealInPanel(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let tabBottom = buttons["panelCollapseButton"].frame.maxY
        let bottomBand: CGFloat = frame.height >= 812 ? 50 : 8
        func isOnScreen() -> Bool {
            element.exists && element.frame.minY >= tabBottom && element.frame.maxY <= frame.height - bottomBand
        }
        func drag(_ dy: CGFloat, from y: CGFloat) {
            let start = coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.width * 0.08, dy: y))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: dy)),
                        withVelocity: .slow, thenHoldForDuration: 0.3)
            Thread.sleep(forTimeInterval: 0.5)
        }
        if isOnScreen() { return }
        for _ in 0..<3 where !isOnScreen() {
            drag(150, from: tabBottom + 30)
        }
        for _ in 0..<8 where !isOnScreen() {
            drag(-100, from: (tabBottom + frame.height) / 2)
        }
        XCTAssertTrue(isOnScreen(), "\(element) on screen: exists \(element.exists) frame \(element.frame) tab \(tabBottom) screen \(frame.height)",
                      file: file, line: line)
    }
}
