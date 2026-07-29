import Foundation
import SwiftData

/// What to study, in what order, and how much of it there is.
///
/// Port of `src/engine/queue.ts`. The soft-delete filtering the web version needs is gone, since
/// deleting a note or deck now cascades to its cards for real, but the orphan checks stay: without
/// a unique constraint or a foreign key the CloudKit mirror can hand over a card whose note never
/// arrived, and a card with no note has nothing to show.
enum Queue {
    /// What a deck has waiting.
    struct Counts: Equatable, Sendable {
        /// Cards past their due time. New cards are never counted here, however overdue their
        /// nominal due date, because they have not been introduced yet.
        var due: Int = 0
        /// New cards that could be introduced right now: the smaller of what the deck has left in
        /// its daily allowance and what it actually holds.
        var newAvailable: Int = 0

        var total: Int { due + newAvailable }
        var isEmpty: Bool { total == 0 }
    }

    // MARK: - Eligibility

    /// Every card that could be studied at all, ignoring due dates.
    ///
    /// Excluded: suspended cards, cards whose note is missing, and cards whose note has no deck.
    static func eligibleCards(
        in context: ModelContext,
        deckID: UUID? = nil
    ) throws -> [Card] {
        eligible(cards: try context.fetch(FetchDescriptor<Card>()), deckID: deckID)
    }

    /// The same filter, over rows that have already been fetched. What a `@Query`-backed screen
    /// passes its cards through before counting or queueing them.
    static func eligible(cards: [Card], deckID: UUID? = nil) -> [Card] {
        cards.filter { card in
            guard !card.suspended, let note = card.note, let deck = note.deck else { return false }
            guard let deckID else { return true }
            return deck.id == deckID
        }
    }

    // MARK: - Counts

    /// Counts for every deck, keyed by deck id. Decks with nothing waiting are still present, with
    /// zeroes, so a caller can render a full deck list from this alone.
    static func counts(
        in context: ModelContext,
        now: Date = Date(),
        counter: NewCardCounter = NewCardCounter()
    ) throws -> [UUID: Counts] {
        counts(
            decks: try context.fetch(FetchDescriptor<Deck>()),
            cards: try eligibleCards(in: context),
            now: now,
            counter: counter
        )
    }

    /// The same counting, over rows that have already been fetched.
    ///
    /// This is the overload SwiftUI screens use. A view holds its decks and cards in `@Query`, so
    /// it already re-renders when either changes; asking it to fetch again through a `ModelContext`
    /// would compute the same numbers off a second, unobserved read, and the counts would be stale
    /// exactly when a card was rated.
    ///
    /// `cards` is expected to be pre-filtered by ``eligibleCards(in:deckID:)``. Passing a raw fetch
    /// of every card counts suspended and orphaned ones.
    static func counts(
        decks: [Deck],
        cards: [Card],
        now: Date = Date(),
        counter: NewCardCounter = NewCardCounter()
    ) -> [UUID: Counts] {
        var counts: [UUID: Counts] = [:]
        var newInDeck: [UUID: Int] = [:]
        for deck in decks {
            counts[deck.id] = Counts()
            newInDeck[deck.id] = 0
        }

        for card in cards {
            guard let deckID = card.note?.deck?.id, counts[deckID] != nil else { continue }
            if card.state == .new {
                newInDeck[deckID, default: 0] += 1
            } else if card.due <= now {
                counts[deckID]?.due += 1
            }
        }

        for deck in decks {
            counts[deck.id]?.newAvailable = min(
                counter.allowance(for: deck, on: now),
                newInDeck[deck.id] ?? 0
            )
        }

        return counts
    }

    /// Counts for one deck, or for everything at once when `deckID` is nil.
    static func counts(
        in context: ModelContext,
        deckID: UUID?,
        now: Date = Date(),
        counter: NewCardCounter = NewCardCounter()
    ) throws -> Counts {
        let all = try counts(in: context, now: now, counter: counter)

        if let deckID {
            return all[deckID] ?? Counts()
        }
        return all.values.reduce(into: Counts()) { total, entry in
            total.due += entry.due
            total.newAvailable += entry.newAvailable
        }
    }

    // MARK: - The queue

    /// The study queue, in order.
    ///
    /// Learning and relearning cards that are due come first, because they are mid-acquisition and
    /// waiting costs more there than anywhere else. Then reviews that are due, oldest first. Then
    /// new cards, up to each deck's remaining allowance for today.
    ///
    /// Nothing not yet due appears at all: a queue that hands over a card early is quietly
    /// undoing the schedule.
    static func build(
        in context: ModelContext,
        deckID: UUID? = nil,
        now: Date = Date(),
        counter: NewCardCounter = NewCardCounter()
    ) throws -> [Card] {
        build(
            decks: try decks(in: context, deckID: deckID),
            cards: try eligibleCards(in: context, deckID: deckID),
            now: now,
            counter: counter
        )
    }

    /// The same queue, over rows that have already been fetched.
    ///
    /// `cards` is expected to be pre-filtered by ``eligible(cards:deckID:)``, and `decks` scoped to
    /// match. What a `@Query`-backed screen calls.
    static func build(
        decks: [Deck],
        cards: [Card],
        now: Date = Date(),
        counter: NewCardCounter = NewCardCounter()
    ) -> [Card] {
        let learning = cards
            .filter { $0.state.isLearning && $0.due <= now }
            .sorted(by: dueThenID)

        let review = cards
            .filter { $0.state == .review && $0.due <= now }
            .sorted(by: dueThenID)

        var new: [Card] = []
        for deck in decks {
            let allowance = counter.allowance(for: deck, on: now)
            guard allowance > 0 else { continue }

            new += cards
                .filter { $0.state == .new && $0.note?.deck?.id == deck.id }
                .sorted(by: dueThenID)
                .prefix(allowance)
        }

        return learning + review + new
    }

    // MARK: - Helpers

    private static func decks(in context: ModelContext, deckID: UUID?) throws -> [Deck] {
        let all = try context.fetch(FetchDescriptor<Deck>())
        guard let deckID else { return all }
        return all.filter { $0.id == deckID }
    }

    /// Due date, then id. The tie-break is not cosmetic: two cards created in the same millisecond
    /// are common, and a queue that shuffles them between builds makes a session feel unstable.
    private static func dueThenID(_ left: Card, _ right: Card) -> Bool {
        if left.due != right.due { return left.due < right.due }
        return left.id.uuidString < right.id.uuidString
    }
}
