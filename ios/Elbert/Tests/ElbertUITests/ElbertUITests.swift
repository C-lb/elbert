import XCTest

final class ElbertUITests: XCTestCase {
    /// Launch smoke only. Task 16 replaces this with the real create-deck-and-study walk.
    /// It deliberately asserts nothing about specific copy, because the root view is still
    /// scaffolding and changes again in task 9.
    func testAppLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(app.staticTexts.firstMatch.waitForExistence(timeout: 10))
    }
}
