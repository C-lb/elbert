import XCTest

/// Task 16, the end-to-end smoke walk: create a deck from scratch, add a note to it, study it,
/// and rate the card. Where the task-10-through-14 suites each exercise one screen against the
/// seeded sample data, this one strings the whole path together against a deck that did not exist
/// a moment ago, which is the thing a brand-new user actually does first.
///
/// Launched with `-resetStore`, not `-seedSampleData`: seeding is unrelated to what this walk is
/// proving, and a from-scratch deck is what a brand-new user's first session looks like. Plain
/// `app.launch()` is not "clean" here — XCUITest never resets the data container between test
/// runs, only a launch argument the app itself acts on does, so without `-resetStore` this test
/// would inherit whatever `DeckFlowUITests` (seeded decks) or an earlier run of this very test
/// left behind. Two symptoms of skipping it, both seen in review: the global Study tab session
/// would serve some other deck's cards first once one exists whose name sorts earlier, and a
/// `deckRow` lookup that matches by `CONTAINS` could resolve a previous run's leftover
/// "Smoke test deck" instead of the one this run just created.
///
/// The note's term and definition are deliberately words that appear nowhere else in the app's
/// chrome (not in the deck name, not in any screen title or button label), so a static-text
/// assertion on them can only be satisfied by the note itself actually having saved and rendered
/// — not by some other label on screen that happens to share a substring.
final class SmokeUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testCreateDeckAddNoteStudyAndRate() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetStore"]
        app.launch()
        // Not gated on the tab bar: the bar is up before the root screen has finished settling,
        // so this waits for the heading to actually read "Home" the way `testAppLaunches` does.
        XCTAssertTrue(headingElement(app, "Home").waitForExistence(timeout: 15), "never settled on Home")

        let deckName = "Smoke test deck"

        // MARK: create deck

        selectTab(app, "Decks", heading: "Decks")

        // With `-resetStore`, Decks starts genuinely empty, so — same reasoning as "New note"
        // below — DeckListScreen shows "New deck" twice: once in the toolbar, once as the
        // empty-state action. `app.buttons["New deck"]` alone is ambiguous until the first deck
        // exists; `.firstMatch` is fine since both fire the same closure.
        let newDeck = app.buttons.matching(NSPredicate(format: "label == 'New deck'")).firstMatch
        let field = app.textFields["Deck name"]
        tap(newDeck, untilExists: field, "the naming alert never opened")
        // No `.tap()` before typing here: a UIAlertController's text field auto-focuses when the
        // alert presents, unlike the editor's fields below, which sit in an ordinary form and
        // need an explicit tap to become first responder. Not an oversight — don't "fix" it to
        // match the editor.
        field.typeText(deckName)
        // Writes once: this creates the deck, so it is a single tap and an assertion on the
        // result rather than the re-tapping helper.
        app.buttons["Create"].tap()

        let deckRow = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", deckName)).firstMatch
        XCTAssertTrue(deckRow.waitForExistence(timeout: 5), "the new deck never appeared on Decks")

        // MARK: add a note

        // A brand-new deck is empty, so (like DeckListScreen's empty state) DeckNotesScreen shows
        // "New note" twice: once in the toolbar, once as the empty-state action. Both fire the same
        // closure, so `.firstMatch` is fine — `app.buttons["New note"]` alone is ambiguous here in a
        // way it is not against the seeded decks the other suite uses, which already have notes.
        let newNote = app.buttons.matching(NSPredicate(format: "label == 'New note'")).firstMatch
        tap(deckRow, untilExists: newNote, "never landed inside the new deck")
        tap(newNote, untilExists: app.navigationBars["New note"], "the editor never opened")

        XCTAssertFalse(app.buttons["Save"].isEnabled, "Save should start disabled on an empty note")

        let term = "Chlorophyll pigment"
        let definition = "Captures light energy for photosynthesis"

        app.textFields["The word or question"].tap()
        app.typeText(term)
        app.textFields["The answer"].tap()
        app.typeText(definition)

        XCTAssertTrue(app.buttons["Save"].isEnabled)
        // Writes once: saving the note.
        app.buttons["Save"].tap()

        // `term` matches nothing else on screen (not the deck name, not any button or heading),
        // so this can only pass once the note row itself has rendered — it is not satisfied by,
        // say, the "Smoke test deck" heading that is already on screen at this point.
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", term))
                .firstMatch.waitForExistence(timeout: 5),
            "the new note never appeared in the deck"
        )

        // MARK: study it

        selectTab(app, "Study", heading: "Study")

        tap(
            app.buttons["Start studying"],
            untilExists: app.buttons["Show answer"],
            "the session never started"
        )

        let good = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Good'")).firstMatch
        tap(app.buttons["Show answer"], untilExists: good, "the answer never showed")
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", definition)).firstMatch.exists,
            "the answer side never showed the note's answer"
        )

        // MARK: rate it

        // Writes once: this records the review. A second tap here would grade the card twice.
        good.tap()

        // Either another card comes up (Show answer again) or the session is done; either one
        // proves the rating was recorded and the queue moved on. A predicate evaluated against
        // `app` itself, rather than one fixed element, is what lets this wait on an "or" instead
        // of committing to a single outcome ahead of time.
        let sessionDone = headingElement(app, "Session done")
        let nextCard = app.buttons["Show answer"]
        let movedOn = expectation(
            for: NSPredicate { _, _ in sessionDone.exists || nextCard.exists },
            evaluatedWith: app
        )
        wait(for: [movedOn], timeout: 10)
    }
}
