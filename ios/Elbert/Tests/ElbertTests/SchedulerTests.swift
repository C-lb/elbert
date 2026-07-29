import Foundation
import SwiftData
import Testing

@testable import Elbert

// MARK: - Parity with ts-fsrs

/// The reference numbers below came out of the web app's own `ts-fsrs` 5.4.1, run over the same
/// synthetic cards with `request_retention: 0.9` and fuzz off. That is the whole point of the
/// exercise: the Swift scheduler is only trustworthy insofar as it agrees with the implementation
/// that is already reviewed and tested.
///
/// Regenerating them means running the script in the task 6 commit message against the web app's
/// node_modules. If these ever fail after a package bump, the dependency moved, not the maths.
@Suite("FSRS parity with ts-fsrs")
struct SchedulerParityTests {
    private static let retention = 0.9

    /// A reference row: seconds until due, then the state the card lands in.
    struct Expected {
        let seconds: Double
        let stability: Double
        let difficulty: Double
        let state: CardState
        let reps: Int
        let lapses: Int
        let learningSteps: Int
    }

    /// ts-fsrs prints stability and difficulty rounded to eight decimals, so parity is asserted to
    /// a hair tighter than a rounding error rather than to the bit.
    private func expectClose(_ actual: Double, _ expected: Double, _ label: String) {
        #expect(abs(actual - expected) < 1e-6, "\(label): \(actual) vs \(expected)")
    }

    private func check(
        card: Card,
        now: Date,
        expected: [Rating: Expected]
    ) throws {
        let outcomes = try Scheduler.outcomes(for: card, retention: Self.retention, now: now)

        for (rating, want) in expected {
            let got = try #require(outcomes[rating], "no outcome for \(rating)")
            expectClose(got.due.timeIntervalSince(now), want.seconds, "\(rating) due")
            expectClose(got.stability, want.stability, "\(rating) stability")
            expectClose(got.difficulty, want.difficulty, "\(rating) difficulty")
            #expect(got.state == want.state, "\(rating) state")
            #expect(got.reps == want.reps, "\(rating) reps")
            #expect(got.lapses == want.lapses, "\(rating) lapses")
            #expect(got.learningSteps == want.learningSteps, "\(rating) learning steps")
        }
    }

    @Test("the parameter vector is FSRS-6, not the library's FSRS-5 default")
    func generationIsSix() {
        // Vector length is what the library keys the generation on: 19 is FSRS-5, 21 is FSRS-6.
        #expect(Scheduler.weights.count == 21)
        // The decay term, and the FSRS-6 signature ts-fsrs 5.4.1 reports.
        expectClose(Scheduler.weights[20], 0.1542, "decay")
    }

    @Test("a brand-new card schedules identically to ts-fsrs")
    func newCardParity() throws {
        let now = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01T00:00:00Z
        let card = Card(due: now)

        try check(card: card, now: now, expected: [
            .again: Expected(seconds: 60, stability: 0.212, difficulty: 6.4133,
                             state: .learning, reps: 1, lapses: 0, learningSteps: 0),
            .hard: Expected(seconds: 360, stability: 1.2931, difficulty: 5.11217071,
                            state: .learning, reps: 1, lapses: 0, learningSteps: 0),
            .good: Expected(seconds: 600, stability: 2.3065, difficulty: 2.11810397,
                            state: .learning, reps: 1, lapses: 0, learningSteps: 1),
            .easy: Expected(seconds: 691_200, stability: 8.2956, difficulty: 1,
                            state: .review, reps: 1, lapses: 0, learningSteps: 0),
        ])
    }

    @Test("a card in review schedules identically to ts-fsrs, including the lapse")
    func matureCardParity() throws {
        let now = Date(timeIntervalSince1970: 1_768_867_200) // 2026-01-20T00:00:00Z
        let card = Card(
            due: now,
            stability: 15.2,
            difficulty: 6.4,
            reps: 6,
            lapses: 1,
            state: .review,
            lastReview: Date(timeIntervalSince1970: 1_767_571_200) // 2026-01-05T00:00:00Z
        )

        try check(card: card, now: now, expected: [
            .again: Expected(seconds: 600, stability: 1.68263316, difficulty: 8.80193285,
                             state: .relearning, reps: 7, lapses: 2, learningSteps: 0),
            .hard: Expected(seconds: 2_505_600, stability: 29.46102922, difficulty: 7.59538061,
                            state: .review, reps: 7, lapses: 1, learningSteps: 0),
            .good: Expected(seconds: 3_369_600, stability: 38.91305157, difficulty: 6.38882837,
                            state: .review, reps: 7, lapses: 1, learningSteps: 0),
            .easy: Expected(seconds: 5_184_000, stability: 59.61217429, difficulty: 5.18227613,
                            state: .review, reps: 7, lapses: 1, learningSteps: 0),
        ])
    }

    @Test("desired retention actually changes the schedule")
    func retentionMatters() throws {
        let now = Date(timeIntervalSince1970: 1_767_225_600)
        let card = Card(due: now, stability: 15.2, difficulty: 6.4, reps: 6, state: .review)

        let strict = try #require(Scheduler.outcomes(for: card, retention: 0.97, now: now)[.good])
        let loose = try #require(Scheduler.outcomes(for: card, retention: 0.80, now: now)[.good])

        // Wanting to remember more means seeing the card sooner.
        #expect(strict.due < loose.due)
    }
}

// MARK: - Interval labels

@Suite("Interval labels")
struct IntervalLabelTests {
    private let start = Date(timeIntervalSince1970: 0)

    private func label(minutes: Double) -> String {
        Scheduler.intervalLabel(from: start, to: start.addingTimeInterval(minutes * 60))
    }

    private func label(days: Double) -> String {
        label(minutes: days * 24 * 60)
    }

    @Test("under an hour reads as minutes with a less-than sign")
    func minutes() {
        #expect(label(minutes: 10) == "<10m")
        #expect(label(minutes: 59) == "<59m")
    }

    @Test("sub-minute intervals floor at one minute rather than reading as zero")
    func minuteFloor() {
        #expect(label(minutes: 0) == "<1m")
        #expect(label(minutes: 0.4) == "<1m")
    }

    @Test("the hour boundary switches unit")
    func hourBoundary() {
        #expect(label(minutes: 59.9) == "<60m")
        #expect(label(minutes: 60) == "1h")
    }

    @Test("hours round to the nearest hour")
    func hours() {
        #expect(label(minutes: 90) == "2h")
        #expect(label(minutes: 89) == "1h")
    }

    @Test("the day boundary switches unit")
    func dayBoundary() {
        #expect(label(minutes: 60 * 24 - 1) == "24h")
        #expect(label(days: 1) == "1d")
    }

    @Test("days round to the nearest day")
    func days() {
        #expect(label(days: 2.4) == "2d")
        #expect(label(days: 2.6) == "3d")
        #expect(label(days: 29) == "29d")
    }

    @Test("the month boundary switches unit and gains a decimal")
    func monthBoundary() {
        #expect(label(days: 29.9) == "30d")
        #expect(label(days: 30) == "1.0mo")
    }

    @Test("months read to one decimal place")
    func months() {
        #expect(label(days: 45) == "1.5mo")
        #expect(label(days: 365) == "12.2mo")
    }
}

// MARK: - Applying a review

@Suite("Applying a review")
@MainActor
struct ApplyReviewTests {
    private func context() throws -> ModelContext {
        ModelContext(try Persistence.inMemoryContainer())
    }

    @Test("a rating updates the card in place and appends a review")
    func writesBoth() throws {
        let context = try context()
        let now = Date(timeIntervalSince1970: 1_767_225_600)
        let card = Card(due: now)
        context.insert(card)

        let review = try Scheduler.apply(.good, to: card, retention: 0.9, elapsedMs: 3_400, at: now, in: context)
        try context.save()

        #expect(card.reps == 1)
        #expect(card.state == .learning)
        #expect(card.due > now)
        #expect(card.lastReview == now)

        #expect(review.rating == .good)
        #expect(review.elapsedMs == 3_400)
        #expect(review.ts == now)
        #expect(review.card?.id == card.id)
        #expect(try context.fetch(FetchDescriptor<Review>()).count == 1)
    }

    @Test("the snapshot records the card as it was before the rating, not after")
    func snapshotIsPreState() throws {
        let context = try context()
        let now = Date(timeIntervalSince1970: 1_767_225_600)
        let card = Card(due: now, stability: 15.2, difficulty: 6.4, reps: 6, lapses: 1, state: .review)
        context.insert(card)

        let review = try Scheduler.apply(.again, to: card, retention: 0.9, elapsedMs: 1_000, at: now, in: context)
        let snapshot = try #require(review.snapshot)

        #expect(snapshot.stability == 15.2)
        #expect(snapshot.difficulty == 6.4)
        #expect(snapshot.reps == 6)
        #expect(snapshot.lapses == 1)
        #expect(snapshot.state == .review)

        // And the card really did move on from it.
        #expect(card.reps == 7)
        #expect(card.lapses == 2)
        #expect(card.state == .relearning)
    }

    @Test("applying a rating agrees with the preview for that rating")
    func applyMatchesPreview() throws {
        let context = try context()
        let now = Date(timeIntervalSince1970: 1_767_225_600)
        let card = Card(due: now, stability: 15.2, difficulty: 6.4, reps: 6, state: .review)
        context.insert(card)

        let predicted = try #require(Scheduler.outcomes(for: card, retention: 0.9, now: now)[.hard])
        try Scheduler.apply(.hard, to: card, retention: 0.9, elapsedMs: 0, at: now, in: context)

        #expect(card.due == predicted.due)
        #expect(card.stability == predicted.stability)
        #expect(card.difficulty == predicted.difficulty)
        #expect(card.state == predicted.state)
    }

    @Test("consecutive good ratings graduate a new card into review")
    func graduation() throws {
        let context = try context()
        var now = Date(timeIntervalSince1970: 1_767_225_600)
        let card = Card(due: now)
        context.insert(card)

        for _ in 0..<4 {
            try Scheduler.apply(.good, to: card, retention: 0.9, elapsedMs: 0, at: now, in: context)
            now = card.due
        }

        #expect(card.state == .review)
        #expect(card.reps == 4)
        #expect(card.lapses == 0)
        #expect(try context.fetch(FetchDescriptor<Review>()).count == 4)
    }
}
