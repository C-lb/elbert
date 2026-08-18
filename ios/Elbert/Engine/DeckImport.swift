import Foundation
import SwiftData

/// What an import created, for the toast that reports it.
struct ImportSummary: Equatable, Sendable {
    let notes: Int
    let cards: Int
}

/// Turns parsed rows into notes and cards in a deck.
///
/// Every row goes through ``CardsFromNote/reconcile(_:in:)``, which is the same path
/// `EditorSheet.save()` takes. That is deliberate: imported cards then arrive exactly like
/// hand-written ones, new, with no reviews and no invented due date, rather than through a second
/// code path that would drift from the first one the moment either changed.
///
/// This does not call `context.save()`. The caller owns the transaction, so a save that throws
/// leaves nothing half-written and the screen can report it.
enum DeckImport {
    static func run(rows: [ImportRow], into deck: Deck, context: ModelContext) -> ImportSummary {
        var cards = 0

        for row in rows {
            let note = Note(type: .basic, term: row.term, definition: row.definition, deck: deck)
            context.insert(note)
            cards += CardsFromNote.reconcile(note, in: context).added.count
        }

        return ImportSummary(notes: rows.count, cards: cards)
    }
}
