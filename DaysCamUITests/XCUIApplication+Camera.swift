import XCTest

extension XCUIApplication {
    /// From the photo wall (what `-UITestOpenFirstRecord` lands on since #618),
    /// opens the camera and waits for the shutter. Returns whether it appeared.
    @discardableResult
    func openCamera(timeout: TimeInterval = 10) -> Bool {
        let button = buttons["wallCameraButton"]
        guard button.waitForExistence(timeout: timeout) else { return false }
        button.tap()
        return buttons["快門"].waitForExistence(timeout: timeout)
    }
}
