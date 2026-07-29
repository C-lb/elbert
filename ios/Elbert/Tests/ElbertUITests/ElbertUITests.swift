import XCTest

final class ElbertUITests: XCTestCase {
    func testAppLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Elbert"].waitForExistence(timeout: 10))
    }
}
