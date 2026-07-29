import Foundation
import SwiftData

/// What a reconcile did, for tests and for the editor to report.
struct Reconciliation: Equatable, Sendable {
    /// Ordinals that gained a fresh card.
    var added: [Int] = []
    /// Ordinals whose card was deleted because the note no longer produces it.
    var removed: [Int] = []
    /// Ordinals that had more than one live card and were collapsed back to one.
    var deduplicated: [Int] = []

    var isEmpty: Bool { added.isEmpty && removed.isEmpty && deduplicated.isEmpty }
}

/// Turns a note into its set of cards, and keeps that set correct as the note is edited.
///
/// Port of `src/engine/cards-from-note.ts`, minus soft delete. Section 6 of the spec spells out
/// what that costs: a removed ordinal is now hard-deleted, so a basic → reversed → basic round
/// trip mints a new card id on the way back rather than resurrecting the old row. The card was
/// already given fresh FSRS state on resurrection in the web version, so the only thing lost is
/// id stability, and nothing depends on it now that sync is CloudKit's problem.
enum CardsFromNote {
    /// Which ordinals a note should have cards for.
    ///
    /// Basic is one card. Basic reversed is term → definition and definition → term. Cloze is one
    /// card per distinct `{{c<n>::…}}` ordinal, in the order `Cloze.parse` returns them.
    static func wantedOrdinals(for note: Note) -> [Int] {
        switch note.type {
        case .basic: [0]
        case .basicReversed: [0, 1]
        case .cloze: Cloze.parse(note.term).map(\.ord)
        }
    }

    /// A fresh, unscheduled card set for a note that has none yet.
    ///
    /// The cards are attached to `note` but not inserted; the caller owns the context.
    static func cards(for note: Note) -> [Card] {
        wantedOrdinals(for: note).map { Card(ord: $0, note: note) }
    }

    /// Brings a note's cards back in line with its content after an edit.
    ///
    /// Cards for ordinals that survive the edit are left completely alone, which is the whole
    /// point: retyping a typo in a cloze must not reset the schedule of the card it belongs to.
    ///
    /// A cloze note whose text no longer contains any deletion reconciles to zero cards. That is
    /// faithful to the web version, and the editor is what stops it happening by refusing to save
    /// a cloze note with no blanks in it.
    @discardableResult
    static func reconcile(_ note: Note, in context: ModelContext) -> Reconciliation {
        let wanted = wantedOrdinals(for: note)
        let wantedSet = Set(wanted)
        var result = Reconciliation()

        var byOrdinal: [Int: [Card]] = [:]
        for card in note.cards ?? [] {
            byOrdinal[card.ord, default: []].append(card)
        }

        // Duplicates are not a theoretical worry. Identity is a plain UUID with no unique
        // constraint (the CloudKit mirror rejects those), so two devices editing the same note
        // offline can each mint a card for the same ordinal and both survive the merge. Keeping
        // the most-studied one loses the least history.
        for (ord, cards) in byOrdinal where cards.count > 1 {
            let survivor = mostStudied(cards)
            for card in cards where card.id != survivor.id {
                context.delete(card)
            }
            byOrdinal[ord] = [survivor]
            result.deduplicated.append(ord)
        }

        for ord in wanted where byOrdinal[ord] == nil {
            let card = Card(ord: ord, note: note)
            context.insert(card)
            result.added.append(ord)
        }

        for (ord, cards) in byOrdinal where !wantedSet.contains(ord) {
            for card in cards {
                context.delete(card)
            }
            result.removed.append(ord)
        }

        result.deduplicated.sort()
        result.removed.sort()
        return result
    }

    /// The card to keep when an ordinal has more than one. Most reps wins, then most lapses,
    /// then lowest id, so the outcome is the same on every device that runs this merge.
    private static func mostStudied(_ cards: [Card]) -> Card {
        cards.max { left, right in
            if left.reps != right.reps { return left.reps < right.reps }
            if left.lapses != right.lapses { return left.lapses < right.lapses }
            return left.id.uuidString > right.id.uuidString
        } ?? cards[0]
    }
}
