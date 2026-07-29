import SwiftData
import SwiftUI

/// The review loop: a card, a reveal, four ratings, and a summary at the end.
///
/// The session is built once when studying starts, not recomputed per card. A queue that rebuilt
/// itself after every rating would reorder underneath the person studying it, and the requeue rule
/// in ``StudySession`` would have nothing to act on.
struct StudyScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(ToastCentre.self) private var toasts
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Set when Home or a deck starts a session for one deck. Nil studies everything due.
    var deckID: UUID?

    @Query(sort: \Deck.name) private var decks: [Deck]
    @Query private var cards: [Card]

    @State private var session: StudySession?
    @State private var revealed = false
    @State private var shownAt = Date()
    @State private var summary: SessionSummary?
    @State private var tally = SessionSummary()
    @State private var previews: [Rating: String] = [:]

    private let counter = NewCardCounter()

    var body: some View {
        Group {
            if let session, let card = session.current {
                reviewing(session: session, card: card)
            } else if let summary {
                finished(summary)
            } else {
                idle
            }
        }
    }

    // MARK: - Idle

    private var waiting: Queue.Counts {
        Queue.counts(
            decks: scopedDecks,
            cards: Queue.eligible(cards: cards, deckID: deckID),
            counter: counter
        )
        .values
        .reduce(into: Queue.Counts()) { total, entry in
            total.due += entry.due
            total.newAvailable += entry.newAvailable
        }
    }

    private var scopedDecks: [Deck] {
        guard let deckID else { return decks }
        return decks.filter { $0.id == deckID }
    }

    private var idle: some View {
        HouseScreen(title: "Study") {
            if waiting.isEmpty {
                HouseEmptyState(
                    icon: .confirm,
                    title: decks.isEmpty ? "Nothing to study" : "You are done for now",
                    message: decks.isEmpty
                        ? "Make a deck and add a note, and it will show up here."
                        : "Nothing is due. Come back later, or add new cards to a deck."
                )
            } else {
                VStack(spacing: Space.s4) {
                    HouseCard {
                        VStack(alignment: .leading, spacing: Space.s3) {
                            HouseText("Waiting for you", role: .eyebrow, ink: \.ink2)

                            HStack(spacing: Space.s5) {
                                CountBlock(value: waiting.due, label: "due")
                                CountBlock(value: waiting.newAvailable, label: "new")
                            }
                        }
                    }

                    Button("Start studying", action: start)
                        .buttonStyle(HouseButtonStyle(tier: .accent, size: .medium))
                }
            }
        }
    }

    // MARK: - Reviewing

    private func reviewing(session: StudySession, card: Card) -> some View {
        VStack(spacing: 0) {
            progressBar(session: session)

            ScrollView {
                VStack(alignment: .leading, spacing: Space.s5) {
                    CardFace(card: card, revealed: revealed)
                }
                .padding(.horizontal, Space.s4)
                .padding(.top, Space.s5)
                .padding(.bottom, Space.s6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)

            controls(card: card)
        }
        .background(Theme.canvas)
    }

    private func progressBar(session: StudySession) -> some View {
        HStack(spacing: Space.s3) {
            Text("\(session.remaining) left")
                .typeRole(.caption)
                .foregroundStyle(Theme.ink3)
                .monospacedDigit()
                .lineLimit(1)

            Spacer(minLength: Space.s3)

            Button("End session") { finish() }
                .buttonStyle(HouseButtonStyle(tier: .neutral, size: .small))
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
    }

    @ViewBuilder
    private func controls(card: Card) -> some View {
        VStack(spacing: Space.s3) {
            if revealed {
                RatingBar(previews: previews) { rating in
                    rate(rating, card: card)
                }
            } else {
                Button("Show answer") { reveal(card) }
                    .buttonStyle(HouseButtonStyle(tier: .accent, size: .medium))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.top, Space.s3)
        .padding(.bottom, Space.s4)
        .background(alignment: .top) { Theme.stroke.frame(height: 1) }
        .background(Theme.surface1)
    }

    // MARK: - Summary

    private func finished(_ summary: SessionSummary) -> some View {
        HouseScreen(title: "Session done") {
            VStack(spacing: Space.s4) {
                HouseCard {
                    VStack(alignment: .leading, spacing: Space.s4) {
                        HouseText(summary.headline, role: .h3)

                        HStack(spacing: Space.s5) {
                            CountBlock(value: summary.answered, label: summary.answered == 1 ? "rating" : "ratings")
                            CountBlock(value: summary.cards, label: summary.cards == 1 ? "card" : "cards")
                        }

                        if summary.again > 0 {
                            HouseText(
                                "\(summary.again) went back to Again. Those come round again soon.",
                                role: .caption,
                                ink: \.ink2
                            )
                        }
                    }
                }

                if waiting.total > 0 {
                    Button("Keep going", action: start)
                        .buttonStyle(HouseButtonStyle(tier: .accent, size: .medium))
                }

                Button("Done") { self.summary = nil }
                    .buttonStyle(HouseButtonStyle(tier: .neutral, size: .medium))
            }
        }
    }

    // MARK: - Actions

    private func start() {
        let eligible = Queue.eligible(cards: cards, deckID: deckID)
        let queue = Queue.build(
            decks: scopedDecks,
            cards: eligible,
            counter: counter
        )

        guard !queue.isEmpty else { return }

        // The new cards in this queue are introduced now, not when they are first rated. Counting
        // them at rating time would let someone start a session, close the app, and start another
        // one, drawing the daily allowance twice.
        for (deckID, count) in newCardsPerDeck(in: queue) {
            counter.note(count, deckID: deckID)
        }

        summary = nil
        tally = SessionSummary()
        revealed = false
        session = StudySession(cards: queue)
        shownAt = Date()
    }

    private func newCardsPerDeck(in queue: [Card]) -> [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for card in queue where card.state == .new {
            guard let deckID = card.note?.deck?.id else { continue }
            counts[deckID, default: 0] += 1
        }
        return counts
    }

    private func reveal(_ card: Card) {
        // Intervals are computed at reveal, once, so the four buttons cannot disagree with what
        // the rating actually does a moment later.
        previews = (try? Scheduler.preview(for: card, retention: retention(for: card))) ?? [:]

        if reduceMotion {
            revealed = true
        } else {
            withAnimation(.snappy(duration: 0.18)) { revealed = true }
        }
    }

    private func rate(_ rating: Rating, card: Card) {
        guard let session else { return }

        Haptics.impact(rating == .again ? .medium : .light)

        do {
            try Scheduler.apply(
                rating,
                to: card,
                retention: retention(for: card),
                elapsedMs: Int(Date().timeIntervalSince(shownAt) * 1000),
                in: context
            )
            try context.save()
        } catch {
            toasts.show(.error("That rating did not save."))
            return
        }

        tally.record(rating, card: card)
        session.answer()
        revealed = false
        previews = [:]
        shownAt = Date()

        if session.isFinished {
            finish()
        }
    }

    private func finish() {
        guard session != nil else { return }
        summary = tally
        session = nil
        revealed = false
        previews = [:]
    }

    /// Retention is a per-deck setting, so it is read from the card's own deck rather than from
    /// whatever deck the session was started from.
    private func retention(for card: Card) -> Double {
        card.note?.deck?.desiredRetention ?? 0.9
    }
}

// MARK: - Card face

private struct CardFace: View {
    let card: Card
    let revealed: Bool

    private var note: Note? { card.note }

    var body: some View {
        HouseCard(padding: Space.s5) {
            VStack(alignment: .leading, spacing: Space.s4) {
                if let note {
                    front(note)

                    if revealed {
                        Divider().overlay(Theme.stroke)
                        back(note)
                    }
                } else {
                    HouseText("This card's note is missing.", role: .body, ink: \.ink2)
                }
            }
        }
    }

    @ViewBuilder
    private func front(_ note: Note) -> some View {
        switch note.type {
        case .cloze:
            HouseText(Cloze.render(note.term, ord: card.ord, revealed: revealed), role: .h3)
        case .basic:
            HouseText(note.term, role: .h3)
        case .basicReversed:
            // Ord 1 is the reversed card: definition on the front, term on the back.
            HouseText(card.ord == 1 ? note.definition : note.term, role: .h3)
        }
    }

    @ViewBuilder
    private func back(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            switch note.type {
            case .cloze:
                if let answer = Cloze.answer(note.term, ord: card.ord) {
                    HouseText(answer, role: .lead)
                }
                if !note.definition.isEmpty {
                    HouseText(note.definition, role: .body, ink: \.ink2)
                }
            case .basic:
                HouseText(note.definition, role: .lead)
            case .basicReversed:
                HouseText(card.ord == 1 ? note.term : note.definition, role: .lead)
            }

            if let example = note.example {
                HouseText(example, role: .caption, ink: \.ink3)
            }
        }
    }
}

// MARK: - Rating bar

private struct RatingBar: View {
    let previews: [Rating: String]
    let rate: (Rating) -> Void

    var body: some View {
        HStack(spacing: Space.s2) {
            ForEach(Rating.allCases, id: \.self) { rating in
                Button {
                    rate(rating)
                } label: {
                    VStack(spacing: Space.s1) {
                        Text(rating.label)
                            .typeRole(.label)
                            .lineLimit(1)

                        Text(previews[rating] ?? " ")
                            .typeRole(.labelSmall)
                            .foregroundStyle(Theme.ink3)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                // All four are grey. The rating bar is four equal choices, and an accent on one of
                // them would read as the recommended answer.
                .buttonStyle(HouseButtonStyle(tier: .neutral, size: .small))
                .accessibilityLabel("\(rating.label), \(previews[rating] ?? "")")
            }
        }
    }
}

// MARK: - Summary

private struct CountBlock: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text("\(value)")
                .typeRole(.display)
                .foregroundStyle(Theme.ink)
                .monospacedDigit()

            Text(label)
                .typeRole(.caption)
                .foregroundStyle(Theme.ink3)
                .lineLimit(1)
        }
    }
}

/// What happened in one session.
///
/// Ratings and cards are counted separately on purpose: a card requeued inside the twenty-minute
/// horizon is rated twice and is still one card, and reporting four ratings as four cards would
/// quietly overstate the work done.
struct SessionSummary: Equatable {
    private(set) var answered = 0
    private(set) var again = 0
    private var seenCards: Set<UUID> = []

    var cards: Int { seenCards.count }

    var headline: String {
        switch answered {
        case 0: "Nothing rated"
        case 1: "One card reviewed"
        default: "\(answered) ratings done"
        }
    }

    mutating func record(_ rating: Rating, card: Card) {
        answered += 1
        seenCards.insert(card.id)
        if rating == .again { again += 1 }
    }
}
