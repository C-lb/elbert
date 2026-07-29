import Testing

@testable import Elbert

// The two cases in `src/engine/cards-from-note.test.ts` are the oracle and appear first, verbatim.
// Everything after them is the edge coverage task 4 calls for, which the web app never had.

@Suite("Cloze parsing")
struct ClozeParseTests {
    @Test("the web app's case: duplicate ordinals de-duplicate and sort")
    func webOracle() {
        let parsed = Cloze.parse("{{c1::Madrid::capital}} is in {{c2::Spain}}, {{c1::Madrid}}")
        #expect(parsed == [
            ClozeDeletion(ord: 1, hint: "capital"),
            ClozeDeletion(ord: 2, hint: nil),
        ])
    }

    @Test("text with no cloze parses to nothing")
    func noDeletions() {
        #expect(Cloze.parse("Madrid is in Spain").isEmpty)
        #expect(!Cloze.hasDeletions("Madrid is in Spain"))
        #expect(Cloze.hasDeletions("{{c1::Madrid}}"))
    }

    @Test("out-of-order ordinals come back ascending")
    func sorting() {
        let parsed = Cloze.parse("{{c3::c}} {{c1::a}} {{c2::b}}")
        #expect(parsed.map(\.ord) == [1, 2, 3])
    }

    @Test("gaps in the ordinals are left as gaps")
    func gaps() {
        #expect(Cloze.parse("{{c1::a}} {{c7::b}}").map(\.ord) == [1, 7])
    }

    @Test("a repeated ordinal keeps the first occurrence's hint")
    func firstHintWins() {
        #expect(Cloze.parse("{{c1::a::first}} {{c1::a::second}}").first?.hint == "first")
    }

    @Test("a first occurrence with no hint is not rescued by a later one")
    func firstAbsenceWins() {
        #expect(Cloze.parse("{{c1::a}} {{c1::a::late}}").first?.hint == nil)
    }

    @Test("an empty hint is no hint")
    func emptyHint() {
        #expect(Cloze.parse("{{c1::a::}}").first?.hint == nil)
    }

    @Test("an empty answer still produces the ordinal")
    func emptyAnswer() {
        #expect(Cloze.parse("{{c1::}}") == [ClozeDeletion(ord: 1, hint: nil)])
    }

    @Test("two deletions on one line stay separate, the match is not greedy")
    func laziness() {
        let parsed = Cloze.parse("{{c1::a}} and {{c2::b}}")
        #expect(parsed.count == 2)
        #expect(Cloze.answer("{{c1::a}} and {{c2::b}}", ord: 1) == "a")
    }

    @Test("a cloze does not span a newline")
    func noNewlineSpanning() {
        #expect(Cloze.parse("{{c1::a\nb}}").isEmpty)
    }

    @Test("malformed syntax is left alone")
    func malformed() {
        #expect(Cloze.parse("{{c1:a}}").isEmpty)
        #expect(Cloze.parse("{{cx::a}}").isEmpty)
        #expect(Cloze.parse("{c1::a}").isEmpty)
    }

    @Test("an ordinal too large for Int is a typo, not a card")
    func absurdOrdinal() {
        #expect(Cloze.parse("{{c99999999999999999999999::a}}").isEmpty)
    }
}

@Suite("Cloze rendering")
struct ClozeRenderTests {
    @Test("the web app's cases: hint shown unrevealed, answers shown revealed")
    func webOracle() {
        #expect(
            Cloze.render("{{c1::Madrid::capital}} is in {{c2::Spain}}", ord: 1, revealed: false)
                == "[capital] is in Spain"
        )
        #expect(
            Cloze.render("{{c1::Madrid}} is in {{c2::Spain}}", ord: 1, revealed: true)
                == "Madrid is in Spain"
        )
    }

    @Test("no hint renders the ellipsis placeholder")
    func placeholder() {
        #expect(Cloze.render("{{c1::Madrid}} is in Spain", ord: 1, revealed: false) == "[...] is in Spain")
    }

    @Test("an empty hint renders the placeholder too, unlike the web version")
    func emptyHintRendersPlaceholder() {
        #expect(Cloze.render("{{c1::Madrid::}}", ord: 1, revealed: false) == "[...]")
    }

    @Test("other ordinals stay revealed while this one is blanked")
    func otherOrdinalsAreContext() {
        let text = "{{c1::a}} {{c2::b}} {{c3::c}}"
        #expect(Cloze.render(text, ord: 2, revealed: false) == "a [...] c")
    }

    @Test("every occurrence of the target ordinal is blanked, not just the first")
    func allOccurrencesBlank() {
        #expect(Cloze.render("{{c1::a}} then {{c1::a}}", ord: 1, revealed: false) == "[...] then [...]")
    }

    @Test("an ordinal that is not in the text changes nothing")
    func unknownOrdinal() {
        #expect(Cloze.render("{{c1::a}} {{c2::b}}", ord: 9, revealed: false) == "a b")
    }

    @Test("text around and between the deletions is preserved exactly")
    func surroundingText() {
        let text = "  Leading, {{c1::a}}, middle, {{c2::b}}. Trailing.  "
        #expect(Cloze.render(text, ord: 1, revealed: true) == "  Leading, a, middle, b. Trailing.  ")
    }

    @Test("text with no cloze is returned unchanged")
    func passthrough() {
        #expect(Cloze.render("Madrid is in Spain", ord: 1, revealed: false) == "Madrid is in Spain")
    }
}

@Suite("Cloze answers")
struct ClozeAnswerTests {
    @Test("the answer is the blanked span, hint excluded")
    func answerExcludesHint() {
        #expect(Cloze.answer("{{c1::Madrid::capital}}", ord: 1) == "Madrid")
    }

    @Test("a missing ordinal is nil, not empty string")
    func missingIsNil() {
        #expect(Cloze.answer("{{c1::Madrid}}", ord: 2) == nil)
    }

    @Test("an empty answer is empty string, distinguishable from missing")
    func emptyIsNotMissing() {
        #expect(Cloze.answer("{{c1::}}", ord: 1) == "")
    }

    @Test("a repeated ordinal answers with the first occurrence")
    func firstOccurrenceWins() {
        #expect(Cloze.answer("{{c1::first}} {{c1::second}}", ord: 1) == "first")
    }
}
