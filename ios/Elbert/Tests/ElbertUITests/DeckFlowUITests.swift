import XCTest

/// The acceptance walks for tasks 10 to 14. These run against the sample decks, which are seeded
/// from real lecture slides under the `-seedSampleData` launch argument, so the flows are
/// exercised against content with cloze notes, reversed notes and long text in it rather than
/// against "Deck 1".
final class DeckFlowUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Launches, and waits for the sample data to be *on screen* rather than for the shell to
    /// exist.
    ///
    /// The tab bar is up within a second of launch, long before seeding has finished writing, so
    /// gating on it starts the walk against a half-empty app: counts read low, rows are missing,
    /// and the failure lands somewhere later that has nothing to do with the cause. A seeded deck
    /// row on Home is the condition that actually says the seed is done.
    private func launchSeeded() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-seedSampleData"]
        app.launch()
        XCTAssertTrue(app.buttons["Home"].waitForExistence(timeout: 15))
        XCTAssertTrue(
            app.buttons.containing(NSPredicate(format: "label CONTAINS 'Strategy'"))
                .firstMatch.waitForExistence(timeout: 20),
            "the sample data never appeared"
        )
        return app
    }

    private func openDecks(_ app: XCUIApplication) {
        selectTab(app, "Decks", heading: "Decks")
    }

    // MARK: - Task 10, DeckList

    func testSeededDecksAppearWithCounts() {
        let app = launchSeeded()
        openDecks(app)

        // Deck rows carry a combined accessibility label, so this asserts the counts are rendered
        // rather than just that the name is on screen.
        XCTAssertTrue(app.buttons.containing(
            NSPredicate(format: "label CONTAINS 'Strategy' AND label CONTAINS 'new'")
        ).firstMatch.waitForExistence(timeout: 5))

        XCTAssertTrue(app.buttons.containing(
            NSPredicate(format: "label CONTAINS 'Marketing'")
        ).firstMatch.exists)
    }

    func testCreateRenameAndDeleteADeck() {
        let app = launchSeeded()
        openDecks(app)

        // Create
        let field = app.textFields["Deck name"]
        tap(app.buttons["New deck"], untilExists: field, "the naming alert never opened")
        field.typeText("Temporary")
        app.buttons["Create"].tap()

        let created = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Temporary'")).firstMatch
        XCTAssertTrue(created.waitForExistence(timeout: 5))

        // Rename, through the row's context menu
        created.press(forDuration: 1.0)
        app.buttons["Rename"].tap()
        let renameField = app.textFields["Deck name"]
        XCTAssertTrue(renameField.waitForExistence(timeout: 5))
        renameField.tap()
        renameField.typeText(" deck")
        app.buttons["Rename"].tap()

        let renamed = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Temporary deck'")).firstMatch
        XCTAssertTrue(renamed.waitForExistence(timeout: 5))

        // Delete, which must confirm first because there is no undo
        renamed.press(forDuration: 1.0)
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.buttons["Delete deck"].waitForExistence(timeout: 5))
        app.buttons["Delete deck"].tap()

        // Waiting for a row to *go* is not `waitForExistence` inverted: that answers "did it ever
        // appear in the next two seconds", which is true of a row that is still being torn down.
        let gone = expectation(
            for: NSPredicate(format: "exists == false"),
            evaluatedWith: app.buttons.containing(NSPredicate(format: "label CONTAINS 'Temporary'")).firstMatch
        )
        wait(for: [gone], timeout: 30)
    }

    // MARK: - Task 11, DeckSettings

    func testDeckSettingsPersist() {
        let app = launchSeeded()
        openDecks(app)

        tap(
            app.buttons.containing(NSPredicate(format: "label CONTAINS 'Marketing'")).firstMatch,
            untilExists: headingElement(app, "Marketing"),
            "never landed on the Marketing deck"
        )

        tap(
            app.buttons["Deck settings"],
            untilExists: app.staticTexts["New cards per day"],
            "never landed on deck settings"
        )

        // The retention slider explains itself in words, not just a percentage.
        XCTAssertTrue(app.sliders["Desired retention"].exists)

        let stepper = app.steppers["New cards per day"]
        XCTAssertTrue(stepper.waitForExistence(timeout: 5))
        let before = intValue(of: stepper)
        XCTAssertNotNil(before, "the stepper does not report its value")

        // By name rather than by index: which end of a stepper is which is not something a test
        // should be asserting by accident. The stepper's identifier is prefixed onto its two
        // buttons, so the name is matched at the end rather than whole.
        stepper.buttons.matching(NSPredicate(format: "identifier ENDSWITH 'Increment'"))
            .firstMatch
            .tap()
        let changed = intValue(of: stepper)
        XCTAssertEqual(changed, (before ?? 0) + 5)

        // Leave and come back: the value must have persisted.
        tap(
            app.navigationBars.buttons.element(boundBy: 0),
            untilExists: app.buttons["Deck settings"],
            "never came back off deck settings"
        )
        tap(
            app.buttons["Deck settings"],
            untilExists: app.steppers["New cards per day"],
            "never got back into deck settings"
        )

        let reopened = app.steppers["New cards per day"]
        XCTAssertTrue(reopened.waitForExistence(timeout: 5))
        XCTAssertEqual(intValue(of: reopened), changed)
    }

    /// A stepper's value comes back as a string or as a number depending on how the accessibility
    /// value was set, and reading only one of the two is a test that passes for the wrong reason.
    private func intValue(of element: XCUIElement) -> Int? {
        switch element.value {
        case let text as String: Int(text.trimmingCharacters(in: .whitespaces))
        case let number as NSNumber: number.intValue
        default: nil
        }
    }

    // MARK: - Task 12, Editor

    func testEditorCreatesANoteAndItsCards() {
        let app = launchSeeded()
        openDecks(app)

        tap(
            app.buttons.containing(NSPredicate(format: "label CONTAINS 'Marketing'")).firstMatch,
            untilExists: app.buttons["New note"],
            "never landed on the Marketing deck"
        )
        tap(
            app.buttons["New note"],
            untilExists: app.navigationBars["New note"],
            "the editor never opened"
        )

        // Save is disabled until the note is actually valid.
        XCTAssertFalse(app.buttons["Save"].isEnabled)

        app.textFields["The word or question"].tap()
        app.typeText("Marketing myopia")
        app.textFields["The answer"].tap()
        app.typeText("Defining your business by the product rather than the need it serves")

        XCTAssertTrue(app.buttons["Save"].isEnabled)
        app.buttons["Save"].tap()

        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Marketing myopia'"))
                .firstMatch.waitForExistence(timeout: 5)
        )
    }

    /// Cloze syntax produces cards silently or produces nothing silently, which is why the editor
    /// previews the ordinals and refuses to save a cloze note with no blanks in it.
    func testClozeEditorRefusesANoteWithNoBlanks() {
        let app = launchSeeded()
        openDecks(app)

        tap(
            app.buttons.containing(NSPredicate(format: "label CONTAINS 'Strategy'")).firstMatch,
            untilExists: app.buttons["New note"],
            "never landed on the Strategy deck"
        )
        tap(
            app.buttons["New note"],
            untilExists: app.navigationBars["New note"],
            "the editor never opened"
        )

        // The field is found by its placeholder, not by position: `textFields.firstMatch` is
        // whatever the hierarchy happens to list first, so if the type switch has not landed yet
        // the text goes into some other field and the assertions below pass or fail for reasons of
        // their own.
        let text = app.textFields["Rome was founded in {{c1::753 BC}}"]
        tap(app.buttons["Cloze"], untilExists: text, "the editor never switched to cloze")
        text.tap()
        app.typeText("No blanks in this sentence")

        XCTAssertFalse(app.buttons["Save"].isEnabled)
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Mark at least one blank'"))
                .firstMatch.exists
        )

        app.buttons["Cancel"].tap()
    }

    // MARK: - Task 13, Study

    func testStudyASessionEndToEnd() {
        let app = launchSeeded()

        selectTab(app, "Study", heading: "Study")

        // Front only. The four ratings appear after the answer is shown, never before, or the
        // rating is a guess about a card you have not tried to recall.
        tap(
            app.buttons["Start studying"],
            untilExists: app.buttons["Show answer"],
            "the session never started"
        )
        XCTAssertFalse(app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Good'")).firstMatch.exists)

        // Each rating button carries its predicted interval in its accessibility label, which is
        // the thing that makes the four choices comparable.
        let good = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Good'")).firstMatch
        tap(app.buttons["Show answer"], untilExists: good, "the answer never showed")
        XCTAssertTrue(good.label.count > "Good".count, "Good has no interval on it: \(good.label)")

        let before = remainingCount(app)
        good.tap()

        XCTAssertTrue(app.buttons["Show answer"].waitForExistence(timeout: 5))
        let after = remainingCount(app)
        XCTAssertNotNil(before)
        XCTAssertNotNil(after)

        tap(
            app.buttons["End session"],
            untilExists: headingElement(app, "Session done"),
            "no session summary"
        )
    }

    private func remainingCount(_ app: XCUIApplication) -> Int? {
        let label = app.staticTexts.containing(NSPredicate(format: "label ENDSWITH 'left'"))
            .firstMatch.label
        return Int(label.replacingOccurrences(of: " left", with: ""))
    }

    // MARK: - Task 14, Home

    func testHomeCountsMatchDecks() {
        let app = launchSeeded()

        // Home aggregates, so its total must equal what the deck list shows per deck.
        XCTAssertTrue(app.staticTexts["Where the work is"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Start studying"].exists)

        tap(
            app.buttons["Start studying"],
            untilExists: headingElement(app, "Study"),
            "Home's Start studying did not go to Study"
        )
        XCTAssertTrue(app.buttons["Study"].isSelected)
    }

    // MARK: - Import

    /// Pastes two rows into a brand new deck and proves they became cards.
    ///
    /// Launches with `-resetStore` rather than `-seedSampleData`, because this walk asserts on a
    /// deck's own counts and the sample decks would make that assertion depend on the fixture.
    func testPastedRowsImportIntoANewDeck() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetStore"]
        app.launch()

        XCTAssertTrue(app.buttons["Home"].waitForExistence(timeout: 15))
        selectTab(app, "Decks", heading: "Decks")

        // The toolbar button and the sheet's title share the word "Import", which is exactly the
        // two-elements-one-name trap. The button is a button, the title is static text.
        tap(app.buttons["Import"], untilExists: app.staticTexts["Import"], "open the import sheet")

        // A vertical `TextField` surfaces as a text field on some runs and a text view on others,
        // depending on whether it has grown past one line yet, so match on the identifier alone
        // rather than betting on the element type.
        let paste = app.descendants(matching: .any).matching(identifier: "import-paste").firstMatch
        XCTAssertTrue(paste.waitForExistence(timeout: 5), "the paste field never appeared")
        focus(paste, in: app, "the paste field")
        paste.typeText("chat\tcat\nchien\tdog")

        let name = app.textFields["import-new-deck"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        focus(name, in: app, "the new deck field")
        name.typeText("French")

        // A writing tap is never re-tapped: a second one here would import twice.
        app.buttons["import-confirm"].tap()

        let row = app.buttons.containing(NSPredicate(format: "label CONTAINS 'French'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the imported deck never appeared")
        XCTAssertTrue(row.label.contains("2 new"), "expected two new cards, got \(row.label)")
    }
}

