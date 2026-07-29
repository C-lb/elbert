import FSRSKit
import Foundation
import SwiftData

/// The FSRS wrapper. Everything that changes a card's schedule goes through here.
///
/// Port of `src/engine/scheduler.ts`. The library itself is reached through `FSRSKit`, a local
/// package that exists because `swift-fsrs` names a class the same as its module and so cannot be
/// disambiguated from a module that has its own `Card`. Nothing here touches library types.
///
/// **Algorithm generation: FSRS-6**, matching the web app's `ts-fsrs` 5.4.1. Decided in task 6.
/// The library defaults to the 19-weight FSRS-5 vector and treats FSRS-6 as opt-in, on purpose, so
/// the 21-weight vector is asked for by name. `SchedulerTests` holds the parity check.
enum Scheduler {
    /// Vector length is what selects the generation inside the library: 19 is FSRS-5, 21 is FSRS-6.
    static let weights = FSRSWeights.v6

    static func engine(retention: Double) -> FSRSEngine {
        FSRSEngine(requestRetention: retention, weights: weights)
    }

    // MARK: - Interval preview

    /// Where a card lands under one rating.
    struct ScheduledOutcome: Equatable, Sendable {
        var due: Date
        var stability: Double
        var difficulty: Double
        var state: CardState
        var reps: Int
        var lapses: Int
        var learningSteps: Int
    }

    /// What each of the four ratings would do to this card, in full.
    ///
    /// The rating bar only needs the labels, but the parity check against `ts-fsrs` needs the
    /// numbers, and the session summary may well want the due dates.
    static func outcomes(
        for card: Card,
        retention: Double,
        now: Date = Date()
    ) throws -> [Rating: ScheduledOutcome] {
        let scheduled = try engine(retention: retention).preview(card: value(of: card), now: now)

        var outcomes: [Rating: ScheduledOutcome] = [:]
        for rating in Rating.allCases {
            guard let value = scheduled[grade(rating)] else { continue }
            outcomes[rating] = outcome(from: value)
        }
        return outcomes
    }

    /// What each of the four ratings would do to this card, as the label shown on its button.
    ///
    /// Label format is carried over from the web app exactly: under an hour is `<Nm` with a floor
    /// of one minute, under a day is `Nh`, under thirty days is `Nd`, and beyond that is `N.Nmo`.
    static func preview(
        for card: Card,
        retention: Double,
        now: Date = Date()
    ) throws -> [Rating: String] {
        try outcomes(for: card, retention: retention, now: now)
            .mapValues { intervalLabel(from: now, to: $0.due) }
    }

    /// The web app's `label`, to the digit.
    ///
    /// The `<` on the minutes case is deliberate: under an hour the interval is a learning step,
    /// and "less than 10m" is honest in a way "10m" is not, since the card comes back inside the
    /// same session anyway.
    static func intervalLabel(from start: Date, to end: Date) -> String {
        let minutes = end.timeIntervalSince(start) / 60

        if minutes < 60 {
            return "<\(max(1, Int(minutes.rounded())))m"
        }
        if minutes < 60 * 24 {
            return "\(Int((minutes / 60).rounded()))h"
        }

        let days = minutes / (60 * 24)
        if days < 30 {
            return "\(Int(days.rounded()))d"
        }
        return String(format: "%.1fmo", days / 30)
    }

    // MARK: - Applying a review

    /// Applies a rating to a card, writes the new schedule, and appends the `Review` row.
    ///
    /// The snapshot is taken before anything changes, so the review record says what the card
    /// looked like going in rather than coming out.
    @discardableResult
    static func apply(
        _ rating: Rating,
        to card: Card,
        retention: Double,
        elapsedMs: Int,
        at now: Date = Date(),
        in context: ModelContext
    ) throws -> Review {
        let snapshot = CardSnapshot(card: card)
        let scheduled = try engine(retention: retention)
            .next(card: value(of: card), now: now, grade: grade(rating))

        write(scheduled, to: card)

        let review = Review(
            ts: now,
            rating: rating,
            elapsedMs: elapsedMs,
            snapshot: snapshot,
            card: card
        )
        context.insert(review)
        return review
    }

    // MARK: - Bridging

    private static func value(of card: Card) -> FSRSCardValue {
        FSRSCardValue(
            due: card.due,
            stability: card.stability,
            difficulty: card.difficulty,
            reps: card.reps,
            lapses: card.lapses,
            learningSteps: card.learningSteps,
            stateRaw: card.stateRaw,
            lastReview: card.lastReview
        )
    }

    private static func write(_ scheduled: FSRSCardValue, to card: Card) {
        card.due = scheduled.due
        card.stability = scheduled.stability
        card.difficulty = scheduled.difficulty
        card.reps = scheduled.reps
        card.lapses = scheduled.lapses
        card.learningSteps = scheduled.learningSteps
        card.stateRaw = scheduled.stateRaw
        card.lastReview = scheduled.lastReview
    }

    private static func outcome(from scheduled: FSRSCardValue) -> ScheduledOutcome {
        ScheduledOutcome(
            due: scheduled.due,
            stability: scheduled.stability,
            difficulty: scheduled.difficulty,
            state: CardState(rawValue: scheduled.stateRaw) ?? .new,
            reps: scheduled.reps,
            lapses: scheduled.lapses,
            learningSteps: scheduled.learningSteps
        )
    }

    /// Elbert's `Rating` and `FSRSGrade` are the same four values, kept as separate types so the
    /// app's domain vocabulary does not leak into the package boundary or the other way round.
    private static func grade(_ rating: Rating) -> FSRSGrade {
        switch rating {
        case .again: .again
        case .hard: .hard
        case .good: .good
        case .easy: .easy
        }
    }
}
