import XCTest

/// Shared machinery for the UI walks.
///
/// Both suites drive the same shell, and both were flaky in the same two ways before this existed:
/// they read a heading that had not settled, and they trusted a tap that was never delivered.
extension XCTestCase {
    /// Matches `ScreenID.title`. The tab bar caption and the screen heading carry the same words,
    /// so querying by label alone is a coin toss between them.
    var screenTitleIdentifier: String { "screen-title" }

    /// The heading that *says* something, rather than any heading.
    ///
    /// Every screen's heading carries the same identifier, and during a tab or push transition both
    /// the outgoing and the incoming screen are briefly in the hierarchy. Waiting on the identifier
    /// alone is therefore satisfied by the screen being left, and the label read a moment later is
    /// a race that passes on a fast machine and fails on a slow one.
    func headingElement(_ app: XCUIApplication, _ expected: String) -> XCUIElement {
        app.staticTexts
            .matching(identifier: screenTitleIdentifier)
            .matching(NSPredicate(format: "label == %@", expected))
            .firstMatch
    }

    /// Taps something that navigates, and insists the navigation actually happened.
    ///
    /// A touch is sometimes never delivered to the app at all: the button is found and the event is
    /// synthesised, and the action never runs. The tab bar still reports the old tab twenty seconds
    /// later, so it is the touch that is lost rather than the transition being slow, and only a
    /// second tap fixes it. The per-attempt wait is long enough that a slow screen is not mistaken
    /// for a dropped touch and tapped twice.
    ///
    /// Only for taps that are safe to repeat: selecting a tab, pushing a screen, opening a sheet.
    /// Never for one that writes.
    func tap(
        _ element: XCUIElement,
        untilExists target: XCUIElement,
        _ what: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for attempt in 1...3 {
            XCTAssertTrue(element.waitForExistence(timeout: 10), "\(what): nothing to tap", file: file, line: line)
            if target.exists { return }
            element.tap()
            if target.waitForExistence(timeout: attempt == 1 ? 8 : 10) { return }
        }
        XCTFail(what, file: file, line: line)
    }

    func selectTab(
        _ app: XCUIApplication,
        _ tab: String,
        heading: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        tap(
            app.buttons[tab],
            untilExists: headingElement(app, heading),
            "never landed on \(heading)",
            file: file,
            line: line
        )
    }


    /// Taps a text field until it actually holds the keyboard, then leaves it focused.
    ///
    /// A single tap on a field is found, dispatched, and silently not honoured often enough to
    /// matter: the field never takes focus and the `typeText` after it fails with "Neither element
    /// nor any descendant has keyboard focus", several minutes later. Unlike a writing tap this one
    /// is safe to repeat, because focusing an already-focused field does nothing.
    func focus(
        _ element: XCUIElement,
        in app: XCUIApplication,
        _ what: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for attempt in 1...3 {
            element.tap()
            if app.keyboards.element.waitForExistence(timeout: attempt == 1 ? 5 : 10) { return }
        }
        XCTFail("\(what) never took keyboard focus", file: file, line: line)
    }
}
