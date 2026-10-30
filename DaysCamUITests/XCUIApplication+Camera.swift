import XCTest

extension XCUIApplication {
    /// From the photo wall (what `-UITestOpenFirstRecord` lands on since #618),
    /// opens the camera and waits for the shutter. Returns whether it appeared.
    ///
    /// The wall is pushed right after launch, so on a slow CI runner the first
    /// tap can land during the push transition and be dropped; tap again once
    /// before giving up.
    @discardableResult
    func openCamera(timeout: TimeInterval = 15) -> Bool {
        let button = buttons["wallCameraButton"]
        let shutter = buttons["快門"]
        guard button.waitForExistence(timeout: timeout) else { return false }
        for _ in 0..<2 {
            if button.exists { button.tap() }
            if shutter.waitForExistence(timeout: timeout / 2) { return true }
        }
        return shutter.exists
    }
}
