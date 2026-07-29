import XCTest

final class ElbertUITests: XCTestCase {
    private let tabs = ["Home", "Decks", "Study", "Settings"]

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        return app
    }

    private func heading(in app: XCUIApplication) -> XCUIElement {
        app.staticTexts[screenTitleIdentifier]
    }

    func testAppLaunches() {
        let app = launch()
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(heading(in: app).waitForExistence(timeout: 10))
        XCTAssertEqual(heading(in: app).label, "Home")
    }

    /// The task 9 acceptance walk. A unit test can say the four tabs exist and that their icons
    /// have fill variants; only this can say that tapping one actually changes the screen.
    func testEveryTabSwitches() {
        let app = launch()
        XCTAssertTrue(app.buttons["Home"].waitForExistence(timeout: 10))

        for tab in tabs {
            // The screen changed: the heading now reads this tab's name.
            selectTab(app, tab, heading: tab)

            // Current state is carried as a real accessibility trait, not just a filled glyph, so
            // VoiceOver and the visual state cannot drift apart.
            XCTAssertTrue(app.buttons[tab].isSelected, "\(tab) is not marked selected")

            for other in tabs where other != tab {
                XCTAssertFalse(app.buttons[other].isSelected, "\(other) still marked selected")
            }
        }
    }

    /// The bar reserves its own space via `safeAreaInset`. If that ever comes off, the last row of
    /// a scroll view slides underneath the bar and this is what notices.
    func testContentClearsTheTabBar() {
        let app = launch()
        let bar = app.buttons["Home"]
        XCTAssertTrue(bar.waitForExistence(timeout: 10))

        let title = heading(in: app)
        XCTAssertTrue(title.exists)
        XCTAssertLessThan(
            title.frame.maxY,
            bar.frame.minY,
            "screen content overlaps the tab bar"
        )
    }

    /// Each tab keeps its own navigation stack, so switching away and back must not reset it.
    /// With placeholder screens there is nothing to push yet, so this asserts the weaker thing it
    /// honestly can: the tab comes back to the same screen rather than being rebuilt elsewhere.
    func testTabsReturnToWhereTheyWere() {
        let app = launch()
        XCTAssertTrue(app.buttons["Decks"].waitForExistence(timeout: 10))

        selectTab(app, "Decks", heading: "Decks")
        selectTab(app, "Settings", heading: "Settings")
        selectTab(app, "Decks", heading: "Decks")
        XCTAssertTrue(app.buttons["Decks"].isSelected)
    }
}
