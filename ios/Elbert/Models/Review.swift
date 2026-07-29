import Foundation
import SwiftData

/// The scheduling state a card had *before* a review was applied.
///
/// Kept so a rating can be explained after the fact, and so a future undo has something to
/// restore. The web app types the equivalent field `unknown` and just dumps the card, so this
/// is the same idea with names on it.
struct CardSnapshot: Codable, Sendable, Equatable {
    var due: Date
    var stability: Double
    var difficulty: Double
    var reps: Int
    var lapses: Int
    var learningSteps: Int
    var stateRaw: Int
    var lastReview: Date?

    var state: CardState { CardState(rawValue: stateRaw) ?? .new }

    init(card: Card) {
        self.due = card.due
        self.stability = card.stability
        self.difficulty = card.difficulty
        self.reps = card.reps
        self.lapses = card.lapses
        self.learningSteps = card.learningSteps
        self.stateRaw = card.stateRaw
        self.lastReview = card.lastReview
    }
}

/// One rating of one card. Append-only: nothing edits a `Review` after it is written.
@Model
final class Review {
    var id: UUID = UUID()
    var ts: Date = Date()

    /// Backing store for ``rating``.
    var ratingRaw: Int = Rating.good.rawValue

    /// How long the card was on screen before the rating landed.
    var elapsedMs: Int = 0

    /// ``CardSnapshot`` as JSON.
    ///
    /// Stored as plain `Data` rather than as a `Codable` property so the CloudKit mirror sees a
    /// single binary field and never has to flatten a struct into columns it would then be stuck
    /// with, since a deployed CloudKit schema is effectively append-only. Nothing queries into
    /// the snapshot, so there is no cost to it being opaque at the store level.
    var snapshotData: Data?

    var card: Card?

    var rating: Rating {
        get { Rating(rawValue: ratingRaw) ?? .good }
        set { ratingRaw = newValue.rawValue }
    }

    /// Decoded snapshot, or `nil` if there was none or it no longer decodes.
    var snapshot: CardSnapshot? {
        get {
            guard let snapshotData else { return nil }
            return try? JSONDecoder().decode(CardSnapshot.self, from: snapshotData)
        }
        set {
            snapshotData = newValue.flatMap { try? JSONEncoder().encode($0) }
        }
    }

    init(
        id: UUID = UUID(),
        ts: Date = Date(),
        rating: Rating = .good,
        elapsedMs: Int = 0,
        snapshot: CardSnapshot? = nil,
        card: Card? = nil
    ) {
        self.id = id
        self.ts = ts
        self.ratingRaw = rating.rawValue
        self.elapsedMs = elapsedMs
        self.snapshotData = snapshot.flatMap { try? JSONEncoder().encode($0) }
        self.card = card
    }
}
