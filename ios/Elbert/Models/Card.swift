import Foundation
import SwiftData

/// One side of one note, carrying its own FSRS scheduling state.
///
/// `ord` is the ordinal within the note: basic gives ord 0, basic reversed gives 0 and 1, and
/// cloze gives one card per `{{c<n>::…}}` ordinal. `Engine/CardsFromNote.swift` (task 5) owns
/// the invariant that a note has exactly one live card per ordinal, since without soft delete
/// there is nothing in the store enforcing it.
@Model
final class Card {
    var id: UUID = UUID()
    var ord: Int = 0

    // FSRS state. Field-for-field the same shape the web app keeps, so the ported scheduler
    // in task 6 can be diffed against `src/engine/scheduler.ts` directly.
    var due: Date = Date()
    var stability: Double = 0
    var difficulty: Double = 0
    var reps: Int = 0
    var lapses: Int = 0
    var learningSteps: Int = 0

    /// Backing store for ``state``.
    var stateRaw: Int = CardState.new.rawValue

    var lastReview: Date?

    /// A suspended card is skipped by the queue entirely. `Bool` here where the web app uses
    /// `0 | 1`, because IndexedDB cannot index a boolean and SwiftData can.
    var suspended: Bool = false

    var note: Note?

    @Relationship(deleteRule: .cascade, inverse: \Review.card)
    var reviews: [Review]?

    var state: CardState {
        get { CardState(rawValue: stateRaw) ?? .new }
        set { stateRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        ord: Int = 0,
        due: Date = Date(),
        stability: Double = 0,
        difficulty: Double = 0,
        reps: Int = 0,
        lapses: Int = 0,
        learningSteps: Int = 0,
        state: CardState = .new,
        lastReview: Date? = nil,
        suspended: Bool = false,
        note: Note? = nil
    ) {
        self.id = id
        self.ord = ord
        self.due = due
        self.stability = stability
        self.difficulty = difficulty
        self.reps = reps
        self.lapses = lapses
        self.learningSteps = learningSteps
        self.stateRaw = state.rawValue
        self.lastReview = lastReview
        self.suspended = suspended
        self.note = note
        self.reviews = []
    }
}
