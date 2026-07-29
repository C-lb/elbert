import Foundation
import SwiftData
import Testing

@testable import Elbert

// Ported from `src/engine/editor-row.ts`, plus the validation the web app spreads across its
// editor component.

@Suite("Note draft validation")
struct NoteDraftValidationTests {
    @Test("a basic note needs both a term and a definition")
    func basicNeedsBoth() {
        var draft = NoteDraft()
        #expect(draft.blockingProblem == "Add a term.")

        draft.term = "Deck"
        #expect(draft.blockingProblem == "Add a definition.")

        draft.definition = "A pile of cards"
        #expect(draft.canSave)
    }

    @Test("whitespace alone does not count as filled in")
    func whitespaceIsEmpty() {
        var draft = NoteDraft()
        draft.term = "   \n  "
        draft.definition = "something"
        #expect(!draft.canSave)
    }

    /// The one case with teeth: a cloze note with no blanks reconciles to zero cards, which is a
    /// note that can never be studied and never surfaces again.
    @Test("a cloze note without a blank cannot be saved")
    func clozeNeedsADeletion() {
        var draft = NoteDraft()
        draft.type = .cloze
        draft.term = "Rome was founded in 753 BC"
        #expect(draft.blockingProblem == "Mark at least one blank, like {{c1::this}}.")

        draft.term = "Rome was founded in {{c1::753 BC}}"
        #expect(draft.canSave)
    }

    @Test("a cloze note does not need a definition")
    func clozeSkipsDefinition() {
        var draft = NoteDraft()
        draft.type = .cloze
        draft.term = "{{c1::a}}"
        #expect(draft.canSave)
    }

    @Test("the deletions a draft would produce are visible before saving")
    func deletionsPreview() {
        var draft = NoteDraft()
        draft.type = .cloze
        draft.term = "{{c2::b}} and {{c1::a}}"
        #expect(draft.clozeDeletions.map(\.ord) == [1, 2])
    }

    @Test("a basic draft reports no deletions even when the text has cloze syntax in it")
    func nonClozeIgnoresSyntax() {
        var draft = NoteDraft()
        draft.term = "{{c1::a}}"
        draft.definition = "b"
        #expect(draft.clozeDeletions.isEmpty)
    }
}

@Suite("Note draft applying")
@MainActor
struct NoteDraftApplyTests {
    private func note() throws -> (ModelContext, Note) {
        let context = ModelContext(try Persistence.inMemoryContainer())
        let note = Note(term: "term", definition: "definition")
        context.insert(note)
        return (context, note)
    }

    /// The rule carried over from the web version: an empty optional field is removed rather than
    /// stored as an empty string, so "no hint" and "a hint that is blank" cannot both exist.
    @Test("empty optional fields become nil, never empty strings")
    func emptyOptionalsAreNil() throws {
        let (_, note) = try note()
        note.example = "was here"
        note.hint = "was here too"

        var draft = NoteDraft(note)
        draft.example = ""
        draft.hint = "   "
        draft.apply(to: note)

        #expect(note.example == nil)
        #expect(note.hint == nil)
    }

    @Test("fields are trimmed on the way in")
    func trimsOnApply() throws {
        let (_, note) = try note()
        var draft = NoteDraft()
        draft.term = "  padded  "
        draft.definition = "\n also padded \n"
        draft.apply(to: note)

        #expect(note.term == "padded")
        #expect(note.definition == "also padded")
    }

    /// A no-op save still touches the row, and a touched row is a CloudKit push plus a sync on
    /// every other device, for nothing.
    @Test("a draft loaded from a note matches it, so an untouched edit writes nothing")
    func roundTripMatches() throws {
        let (_, note) = try note()
        note.example = "e"
        note.hint = "h"
        #expect(NoteDraft(note).matches(note))
    }

    @Test("whitespace-only changes do not count as changes")
    func whitespaceIsNotAChange() throws {
        let (_, note) = try note()
        var draft = NoteDraft(note)
        draft.term = "  term  "
        #expect(draft.matches(note))
    }

    @Test("a real change is detected in every field the editor owns")
    func changesAreDetected() throws {
        let (_, note) = try note()

        var type = NoteDraft(note); type.type = .cloze
        var term = NoteDraft(note); term.term = "other"
        var definition = NoteDraft(note); definition.definition = "other"
        var example = NoteDraft(note); example.example = "new"
        var hint = NoteDraft(note); hint.hint = "new"

        for draft in [type, term, definition, example, hint] {
            #expect(!draft.matches(note))
        }
    }

    @Test("applying a type change then reconciling produces the right card set")
    func applyThenReconcile() throws {
        let (context, note) = try note()
        CardsFromNote.reconcile(note, in: context)
        #expect(note.cards?.count == 1)

        var draft = NoteDraft(note)
        draft.type = .basicReversed
        draft.apply(to: note)
        CardsFromNote.reconcile(note, in: context)
        try context.save()

        #expect(note.cards?.count == 2)
    }
}

@Suite("Cloze stripping")
struct ClozeStrippingTests {
    @Test("stripping leaves the sentence with every answer in place")
    func stripsSyntax() {
        #expect(
            Cloze.stripped("{{c1::Madrid::capital}} is in {{c2::Spain}}") == "Madrid is in Spain"
        )
    }

    @Test("text with no cloze is unchanged")
    func passthrough() {
        #expect(Cloze.stripped("Madrid is in Spain") == "Madrid is in Spain")
    }
}
