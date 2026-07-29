import Foundation
import SwiftData
import Testing

@testable import Elbert

// Cases ported from `src/engine/cards-from-note.test.ts`. Where the TypeScript asserts on
// `deletedAt`, the Swift version asserts the row is gone, since soft delete is what this port
// drops (spec section 6).

@MainActor
private struct Fixture {
    let context: ModelContext
    let note: Note

    init(type: NoteType, term: String) throws {
        context = ModelContext(try Persistence.inMemoryContainer())
        note = Note(type: type, term: term, definition: "def")
        context.insert(note)
    }

    /// Every card row that still exists for the note, ordinal ascending.
    var cards: [Card] {
        (note.cards ?? []).sorted { $0.ord < $1.ord }
    }

    var ordinals: [Int] { cards.map(\.ord) }

    func card(ord: Int) -> Card? { cards.first { $0.ord == ord } }

    func retype(_ type: NoteType, term: String? = nil) {
        note.type = type
        if let term { note.term = term }
    }

    @discardableResult
    func reconcile() throws -> Reconciliation {
        let result = CardsFromNote.reconcile(note, in: context)
        try context.save()
        return result
    }
}

@Suite("Cards for a note")
@MainActor
struct CardsForNoteTests {
    @Test("basic gives one card, reversed gives two, cloze gives one per ordinal")
    func cardCounts() throws {
        #expect(CardsFromNote.wantedOrdinals(for: Note(type: .basic, term: "hola")) == [0])
        #expect(CardsFromNote.wantedOrdinals(for: Note(type: .basicReversed, term: "hola")) == [0, 1])
        #expect(CardsFromNote.wantedOrdinals(for: Note(type: .cloze, term: "{{c1::a}} {{c2::b}}")) == [1, 2])
    }

    @Test("a cloze note with no deletions wants no cards")
    func clozeWithoutDeletions() {
        #expect(CardsFromNote.wantedOrdinals(for: Note(type: .cloze, term: "no blanks here")).isEmpty)
    }

    @Test("new cards start unscheduled and due now")
    func freshCardState() throws {
        let card = try #require(CardsFromNote.cards(for: Note(type: .basic, term: "hola")).first)
        #expect(card.state == .new)
        #expect(card.reps == 0)
        #expect(card.lapses == 0)
        #expect(card.stability == 0)
        #expect(card.difficulty == 0)
        #expect(card.due <= Date())
    }
}

@Suite("Reconciling cards with a note")
@MainActor
struct ReconcileTests {
    @Test("a note with no cards yet gets the full set")
    func newNote() throws {
        let fixture = try Fixture(type: .basic, term: "hola")
        let result = try fixture.reconcile()

        #expect(fixture.ordinals == [0])
        #expect(result.added == [0])
        #expect(result.removed.isEmpty)
    }

    @Test("reconciling twice changes nothing the second time")
    func idempotent() throws {
        let fixture = try Fixture(type: .cloze, term: "{{c1::a}} {{c2::b}}")
        try fixture.reconcile()
        let second = try fixture.reconcile()

        #expect(second.isEmpty)
        #expect(fixture.ordinals == [1, 2])
    }

    @Test("adding a cloze ordinal adds exactly one card and leaves the others untouched")
    func addOrdinal() throws {
        let fixture = try Fixture(type: .cloze, term: "{{c1::a}} {{c2::b}}")
        try fixture.reconcile()

        let first = try #require(fixture.card(ord: 1))
        first.reps = 5
        first.stability = 12.3
        first.state = .review

        fixture.retype(.cloze, term: "{{c1::a}} {{c2::b}} {{c3::c}}")
        let result = try fixture.reconcile()

        #expect(fixture.ordinals == [1, 2, 3])
        #expect(result.added == [3])

        let survivor = try #require(fixture.card(ord: 1))
        #expect(survivor.reps == 5)
        #expect(survivor.stability == 12.3)
        #expect(survivor.state == .review)
    }

    @Test("removing a cloze ordinal deletes its card and only its card")
    func removeOrdinal() throws {
        let fixture = try Fixture(type: .cloze, term: "{{c1::a}} {{c2::b}}")
        try fixture.reconcile()

        fixture.retype(.cloze, term: "{{c1::a}}")
        let result = try fixture.reconcile()

        #expect(fixture.ordinals == [1])
        #expect(result.removed == [2])
        #expect(try fixture.context.fetch(FetchDescriptor<Card>()).count == 1)
    }

    @Test("basic to reversed adds the ord 1 card")
    func basicToReversed() throws {
        let fixture = try Fixture(type: .basic, term: "hola")
        try fixture.reconcile()

        fixture.retype(.basicReversed)
        try fixture.reconcile()

        #expect(fixture.ordinals == [0, 1])
    }

    @Test("reversed to basic deletes the ord 1 card")
    func reversedToBasic() throws {
        let fixture = try Fixture(type: .basicReversed, term: "hola")
        try fixture.reconcile()

        fixture.retype(.basic)
        try fixture.reconcile()

        #expect(fixture.ordinals == [0])
        #expect(try fixture.context.fetch(FetchDescriptor<Card>()).count == 1)
    }

    /// The divergence from the web version, stated as a test rather than left implicit. The web
    /// app resurrects the same row id; without soft delete there is no row left to resurrect, so
    /// the returning ordinal gets a new id. Fresh FSRS state is the same either way, which is why
    /// the id is the only thing lost.
    @Test("an ordinal that returns comes back with a new id and fresh state")
    func returningOrdinalIsNew() throws {
        let fixture = try Fixture(type: .basicReversed, term: "hola")
        try fixture.reconcile()

        let originalID = try #require(fixture.card(ord: 1)).id
        try #require(fixture.card(ord: 1)).reps = 9

        fixture.retype(.basic)
        try fixture.reconcile()

        fixture.retype(.basicReversed)
        try fixture.reconcile()

        let returned = try #require(fixture.card(ord: 1))
        #expect(returned.id != originalID)
        #expect(returned.reps == 0)
        #expect(returned.stability == 0)
        #expect(returned.state == .new)
    }

    /// The invariant section 6 asks for explicitly: a round trip must not accumulate rows.
    @Test("basic to reversed to basic to reversed leaves exactly two cards, one per ordinal")
    func roundTripDoesNotAccumulate() throws {
        let fixture = try Fixture(type: .basic, term: "hola")
        try fixture.reconcile()

        for type in [NoteType.basicReversed, .basic, .basicReversed] {
            fixture.retype(type)
            try fixture.reconcile()
        }

        let all = try fixture.context.fetch(FetchDescriptor<Card>())
        #expect(all.count == 2)
        #expect(fixture.ordinals == [0, 1])
    }

    /// Two devices editing the same note offline can each mint a card for the same ordinal, since
    /// there is no unique constraint to stop them. Reconcile has to survive the merge.
    @Test("duplicate cards for one ordinal collapse to the most-studied one")
    func duplicatesCollapse() throws {
        let fixture = try Fixture(type: .basic, term: "hola")
        try fixture.reconcile()

        let original = try #require(fixture.card(ord: 0))
        original.reps = 7
        let intruder = Card(ord: 0, reps: 2, note: fixture.note)
        fixture.context.insert(intruder)
        try fixture.context.save()

        let result = try fixture.reconcile()

        #expect(result.deduplicated == [0])
        #expect(fixture.ordinals == [0])
        #expect(try #require(fixture.card(ord: 0)).reps == 7)
    }

    @Test("duplicates at an ordinal that is also going away are all deleted")
    func duplicatesAtRemovedOrdinal() throws {
        let fixture = try Fixture(type: .basicReversed, term: "hola")
        try fixture.reconcile()
        fixture.context.insert(Card(ord: 1, note: fixture.note))
        try fixture.context.save()

        fixture.retype(.basic)
        try fixture.reconcile()

        #expect(fixture.ordinals == [0])
        #expect(try fixture.context.fetch(FetchDescriptor<Card>()).count == 1)
    }

    /// Faithful to the web version, and the reason the editor refuses to save a cloze note with no
    /// blanks in it. Worth a test so the behaviour is a decision rather than a surprise.
    @Test("emptying a cloze note of its deletions removes every card")
    func clozeEmptiedRemovesAll() throws {
        let fixture = try Fixture(type: .cloze, term: "{{c1::a}}")
        try fixture.reconcile()

        fixture.retype(.cloze, term: "no blanks left")
        let result = try fixture.reconcile()

        #expect(fixture.ordinals.isEmpty)
        #expect(result.removed == [1])
    }
}
