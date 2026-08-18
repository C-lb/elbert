import Foundation
import SwiftData
import Testing

@testable import Elbert

@Suite("Deck import")
struct DeckImportTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(try Persistence.inMemoryContainer())
    }

    @Test("rows become basic notes in the deck, one card each")
    func writesNotesAndCards() throws {
        let context = try makeContext()
        let deck = Deck(name: "Imported")
        context.insert(deck)

        let summary = DeckImport.run(
            rows: [
                ImportRow(term: "chat", definition: "cat"),
                ImportRow(term: "chien", definition: "dog"),
            ],
            into: deck,
            context: context
        )
        try context.save()

        #expect(summary == ImportSummary(notes: 2, cards: 2))

        let notes = try context.fetch(FetchDescriptor<Note>())
        #expect(notes.count == 2)

        let allBasic = notes.allSatisfy { $0.type == .basic }
        #expect(allBasic)

        let inDeck = notes.allSatisfy { $0.deck?.id == deck.id }
        #expect(inDeck)

        #expect(Set(notes.map(\.term)) == ["chat", "chien"])
    }

    @Test("imported cards arrive new, with no scheduling state")
    func cardsArriveNew() throws {
        let context = try makeContext()
        let deck = Deck(name: "Imported")
        context.insert(deck)

        _ = DeckImport.run(rows: [ImportRow(term: "chat", definition: "cat")], into: deck, context: context)
        try context.save()

        let cards = try context.fetch(FetchDescriptor<Card>())
        #expect(cards.count == 1)
        #expect(cards[0].reps == 0)
        #expect(cards[0].lapses == 0)
        #expect(cards[0].lastReview == nil)
    }

    @Test("importing into a deck that already has notes adds to it")
    func addsToExistingDeck() throws {
        let context = try makeContext()
        let deck = Deck(name: "Imported")
        context.insert(deck)

        let existing = Note(type: .basic, term: "old", definition: "note", deck: deck)
        context.insert(existing)
        _ = CardsFromNote.reconcile(existing, in: context)
        try context.save()

        let summary = DeckImport.run(rows: [ImportRow(term: "chat", definition: "cat")], into: deck, context: context)
        try context.save()

        #expect(summary == ImportSummary(notes: 1, cards: 1))
        #expect(try context.fetch(FetchDescriptor<Note>()).count == 2)
    }

    @Test("no rows writes nothing")
    func emptyRows() throws {
        let context = try makeContext()
        let deck = Deck(name: "Imported")
        context.insert(deck)

        let summary = DeckImport.run(rows: [], into: deck, context: context)
        try context.save()

        #expect(summary == ImportSummary(notes: 0, cards: 0))
        #expect(try context.fetch(FetchDescriptor<Note>()).isEmpty)
    }

    @Test("a row with an empty definition still imports")
    func emptyDefinition() throws {
        let context = try makeContext()
        let deck = Deck(name: "Imported")
        context.insert(deck)

        let summary = DeckImport.run(rows: [ImportRow(term: "chat", definition: "")], into: deck, context: context)
        try context.save()

        #expect(summary == ImportSummary(notes: 1, cards: 1))
    }
}
