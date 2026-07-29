import Foundation
import SwiftData
import Testing

@testable import Elbert

// Ported from `src/engine/queue.test.ts`, with the soft-delete cases dropped, since a deleted deck
// now takes its notes and cards with it rather than staying in the table marked dead.

@MainActor
private struct QueueFixture {
    let context: ModelContext
    let counter: NewCardCounter
    let now = Date(timeIntervalSince1970: 1_767_225_600)

    init() throws {
        context = ModelContext(try Persistence.inMemoryContainer())
        // A named suite per fixture, so one test's introduced-count never leaks into another's.
        let defaults = try #require(UserDefaults(suiteName: "queue-tests-\(UUID().uuidString)"))
        counter = NewCardCounter(defaults: defaults)
    }

    @discardableResult
    func deck(_ name: String, newPerDay: Int = 20) -> Deck {
        let deck = Deck(name: name, newPerDay: newPerDay)
        context.insert(deck)
        return deck
    }

    /// A card in its own note, so eligibility rules that key off the note are exercised properly.
    @discardableResult
    func card(
        in deck: Deck,
        state: CardState = .review,
        dueOffset: TimeInterval = -1,
        suspended: Bool = false
    ) -> Card {
        let note = Note(term: "t", definition: "d", deck: deck)
        let card = Card(
            due: now.addingTimeInterval(dueOffset),
            state: state,
            suspended: suspended,
            note: note
        )
        context.insert(note)
        context.insert(card)
        return card
    }

    func build(deckID: UUID? = nil) throws -> [Card] {
        try Queue.build(in: context, deckID: deckID, now: now, counter: counter)
    }

    func counts(deckID: UUID?) throws -> Queue.Counts {
        try Queue.counts(in: context, deckID: deckID, now: now, counter: counter)
    }
}

@Suite("Queue eligibility")
@MainActor
struct QueueEligibilityTests {
    @Test("cards not yet due are excluded")
    func futureExcluded() throws {
        let fixture = try QueueFixture()
        let deck = fixture.deck("d")
        let due = fixture.card(in: deck)
        fixture.card(in: deck, dueOffset: 86_400)

        #expect(try fixture.build().map(\.id) == [due.id])
    }

    @Test("suspended cards are excluded, whatever their state")
    func suspendedExcluded() throws {
        let fixture = try QueueFixture()
        let deck = fixture.deck("d")
        fixture.card(in: deck, suspended: true)
        fixture.card(in: deck, state: .new, suspended: true)

        #expect(try fixture.build().isEmpty)
        #expect(try fixture.counts(deckID: deck.id) == Queue.Counts(due: 0, newAvailable: 0))
    }

    /// The CloudKit mirror has no foreign keys, so a card can arrive before, or without, the note
    /// it belongs to. There is nothing to put on screen for it.
    @Test("orphaned cards are excluded")
    func orphansExcluded() throws {
        let fixture = try QueueFixture()
        let deck = fixture.deck("d")
        fixture.card(in: deck)

        let orphan = Card(due: fixture.now.addingTimeInterval(-1), state: .review)
        fixture.context.insert(orphan)

        let noteWithoutDeck = Note(term: "t")
        let deckless = Card(due: fixture.now.addingTimeInterval(-1), state: .review, note: noteWithoutDeck)
        fixture.context.insert(noteWithoutDeck)
        fixture.context.insert(deckless)

        #expect(try fixture.build().count == 1)
    }

    @Test("deleting a deck removes its cards from the queue entirely")
    func deletedDeck() throws {
        let fixture = try QueueFixture()
        let deck = fixture.deck("d")
        fixture.card(in: deck)
        try fixture.context.save()

        fixture.context.delete(deck)
        try fixture.context.save()

        #expect(try fixture.build().isEmpty)
        #expect(try fixture.counts(deckID: nil) == Queue.Counts(due: 0, newAvailable: 0))
    }
}

@Suite("Queue order")
@MainActor
struct QueueOrderTests {
    @Test("learning comes before review, review before new")
    func ordering() throws {
        let fixture = try QueueFixture()
        let deck = fixture.deck("d", newPerDay: 5)
        fixture.card(in: deck, state: .new)
        fixture.card(in: deck, state: .review)
        fixture.card(in: deck, state: .relearning)
        fixture.card(in: deck, state: .learning)

        let states = try fixture.build().map(\.state)
        #expect(states[0].isLearning)
        #expect(states[1].isLearning)
        #expect(states[2] == .review)
        #expect(states[3] == .new)
    }

    @Test("within a band, the oldest due date comes first")
    func oldestFirst() throws {
        let fixture = try QueueFixture()
        let deck = fixture.deck("d")
        let recent = fixture.card(in: deck, dueOffset: -10)
        let ancient = fixture.card(in: deck, dueOffset: -10_000)
        let middling = fixture.card(in: deck, dueOffset: -100)

        #expect(try fixture.build().map(\.id) == [ancient.id, middling.id, recent.id])
    }

    @Test("cards due at the same instant come back in a stable order")
    func stableTieBreak() throws {
        let fixture = try QueueFixture()
        let deck = fixture.deck("d")
        for _ in 0..<5 { fixture.card(in: deck, dueOffset: -1) }

        let first = try fixture.build().map(\.id)
        let second = try fixture.build().map(\.id)
        #expect(first == second)
    }

    @Test("a card due exactly now is included, not held back")
    func dueNowIncluded() throws {
        let fixture = try QueueFixture()
        let deck = fixture.deck("d")
        fixture.card(in: deck, dueOffset: 0)

        #expect(try fixture.build().count == 1)
    }
}

@Suite("New card allowance")
@MainActor
struct NewCardAllowanceTests {
    @Test("new cards are capped at the deck's daily allowance")
    func capped() throws {
        let fixture = try QueueFixture()
        let deck = fixture.deck("d", newPerDay: 2)
        for _ in 0..<3 { fixture.card(in: deck, state: .new) }

        #expect(try fixture.build().count == 2)
        #expect(try fixture.counts(deckID: deck.id) == Queue.Counts(due: 0, newAvailable: 2))
    }

    @Test("newAvailable never exceeds the cards the deck actually holds")
    func availabilityIsBounded() throws {
        let fixture = try QueueFixture()
        let deck = fixture.deck("d", newPerDay: 20)
        fixture.card(in: deck, state: .new)

        #expect(try fixture.counts(deckID: deck.id) == Queue.Counts(due: 0, newAvailable: 1))
    }

    @Test("introducing new cards reduces later sessions the same day")
    func counterReducesAllowance() throws {
        let fixture = try QueueFixture()
        let deck = fixture.deck("d", newPerDay: 2)
        for _ in 0..<3 { fixture.card(in: deck, state: .new) }

        fixture.counter.note(2, deckID: deck.id, on: fixture.now)

        #expect(try fixture.build().isEmpty)
        #expect(try fixture.counts(deckID: deck.id).newAvailable == 0)
    }

    @Test("lowering newPerDay below what was introduced gives zero, not a negative")
    func allowanceFloorsAtZero() throws {
        let fixture = try QueueFixture()
        let deck = fixture.deck("d", newPerDay: 5)
        fixture.counter.note(9, deckID: deck.id, on: fixture.now)
        deck.newPerDay = 1

        #expect(fixture.counter.allowance(for: deck, on: fixture.now) == 0)
    }

    @Test("each deck spends its own allowance, not a shared pool")
    func perDeckAllowance() throws {
        let fixture = try QueueFixture()
        let first = fixture.deck("one", newPerDay: 2)
        let second = fixture.deck("two", newPerDay: 1)
        for _ in 0..<3 { fixture.card(in: first, state: .new) }
        for _ in 0..<3 { fixture.card(in: second, state: .new) }

        let queue = try fixture.build()
        #expect(queue.count == 3)
        #expect(queue.filter { $0.note?.deck?.id == first.id }.count == 2)
        #expect(queue.filter { $0.note?.deck?.id == second.id }.count == 1)
    }

    @Test("exhausting one deck's allowance leaves the other's alone")
    func allowanceIsIsolated() throws {
        let fixture = try QueueFixture()
        let first = fixture.deck("one", newPerDay: 2)
        let second = fixture.deck("two", newPerDay: 2)
        fixture.card(in: first, state: .new)
        fixture.card(in: second, state: .new)

        fixture.counter.note(2, deckID: first.id, on: fixture.now)

        let queue = try fixture.build()
        #expect(queue.count == 1)
        #expect(queue.first?.note?.deck?.id == second.id)
    }
}

@Suite("Due counts")
@MainActor
struct DueCountsTests {
    @Test("new cards are never counted as due, however old their due date")
    func newIsNotDue() throws {
        let fixture = try QueueFixture()
        let deck = fixture.deck("d", newPerDay: 20)
        fixture.card(in: deck, state: .new, dueOffset: -86_400)

        #expect(try fixture.counts(deckID: deck.id) == Queue.Counts(due: 0, newAvailable: 1))
    }

    @Test("counts with no deck sum every deck")
    func globalCounts() throws {
        let fixture = try QueueFixture()
        let first = fixture.deck("one", newPerDay: 1)
        let second = fixture.deck("two", newPerDay: 1)
        fixture.card(in: first)
        fixture.card(in: first, state: .new)
        fixture.card(in: second)
        fixture.card(in: second, state: .new)

        #expect(try fixture.counts(deckID: nil) == Queue.Counts(due: 2, newAvailable: 2))
    }

    @Test("every deck appears in the per-deck map, including empty ones")
    func emptyDecksArePresent() throws {
        let fixture = try QueueFixture()
        let empty = fixture.deck("empty")

        let all = try Queue.counts(in: fixture.context, now: fixture.now, counter: fixture.counter)
        #expect(all[empty.id] == Queue.Counts(due: 0, newAvailable: 0))
    }

    @Test("an unknown deck id counts as nothing rather than failing")
    func unknownDeck() throws {
        let fixture = try QueueFixture()
        #expect(try fixture.counts(deckID: UUID()) == Queue.Counts(due: 0, newAvailable: 0))
    }
}

@Suite("Day counter")
struct NewCardCounterTests {
    private func counter() throws -> NewCardCounter {
        NewCardCounter(defaults: try #require(UserDefaults(suiteName: "counter-tests-\(UUID().uuidString)")))
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return Calendar(identifier: .gregorian).date(from: components) ?? Date()
    }

    @Test("day keys are zero-padded local dates")
    func dayKeyFormat() {
        #expect(NewCardCounter.dayKey(date(2026, 1, 5)) == "2026-01-05")
        #expect(NewCardCounter.dayKey(date(2026, 9, 9)) == "2026-09-09")
    }

    /// The counter is a per-device, per-local-day notion. Rolling over on UTC midnight would reset
    /// someone's allowance in the middle of their evening.
    @Test("the day rolls over at local midnight")
    func localMidnight() {
        #expect(NewCardCounter.dayKey(date(2026, 6, 30, hour: 23)) == "2026-06-30")
        #expect(NewCardCounter.dayKey(date(2026, 7, 1, hour: 0)) == "2026-07-01")
    }

    @Test("counts accumulate within a day")
    func accumulates() throws {
        let counter = try counter()
        let deck = UUID()
        let today = date(2026, 3, 3)

        counter.note(2, deckID: deck, on: today)
        counter.note(3, deckID: deck, on: today)

        #expect(counter.introduced(deckID: deck, on: today) == 5)
    }

    @Test("a new day starts from zero")
    func resetsDaily() throws {
        let counter = try counter()
        let deck = UUID()

        counter.note(5, deckID: deck, on: date(2026, 3, 3))
        #expect(counter.introduced(deckID: deck, on: date(2026, 3, 4)) == 0)
    }

    @Test("decks count separately")
    func perDeck() throws {
        let counter = try counter()
        let first = UUID()
        let second = UUID()
        let today = date(2026, 3, 3)

        counter.note(4, deckID: first, on: today)
        #expect(counter.introduced(deckID: second, on: today) == 0)
    }

    /// Without the sweep, every deck leaves one dead key behind per day, forever.
    @Test("writing today's count sweeps away older days")
    func prunesOldKeys() throws {
        let counter = try counter()
        let deck = UUID()

        counter.note(5, deckID: deck, on: date(2026, 3, 3))
        counter.note(1, deckID: deck, on: date(2026, 3, 4))

        #expect(counter.introduced(deckID: deck, on: date(2026, 3, 3)) == 0)
        #expect(counter.introduced(deckID: deck, on: date(2026, 3, 4)) == 1)
    }

    @Test("noting zero is a no-op, not a write")
    func zeroIsNoop() throws {
        let counter = try counter()
        let deck = UUID()
        let today = date(2026, 3, 3)

        counter.note(0, deckID: deck, on: today)
        #expect(counter.introduced(deckID: deck, on: today) == 0)
    }
}
