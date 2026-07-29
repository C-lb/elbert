import SwiftData
import SwiftUI

/// What is waiting, across everything, and one way to start.
///
/// Home is a summary rather than a second deck list: the same numbers as Decks, aggregated, with
/// the single action that matters. The per-deck rows are here so a person can see where the work
/// is, not so they can manage decks from two places.
struct HomeScreen: View {
    @Query(sort: \Deck.name) private var decks: [Deck]
    @Query private var cards: [Card]

    @Binding var selectedTab: AppTab

    private let counter = NewCardCounter()

    private var countsByDeck: [UUID: Queue.Counts] {
        Queue.counts(decks: decks, cards: Queue.eligible(cards: cards), counter: counter)
    }

    private var total: Queue.Counts {
        countsByDeck.values.reduce(into: Queue.Counts()) { running, entry in
            running.due += entry.due
            running.newAvailable += entry.newAvailable
        }
    }

    /// Decks with something waiting, busiest first. A deck with nothing due is not news.
    private var active: [(deck: Deck, counts: Queue.Counts)] {
        decks
            .compactMap { deck -> (Deck, Queue.Counts)? in
                guard let counts = countsByDeck[deck.id], !counts.isEmpty else { return nil }
                return (deck, counts)
            }
            .sorted { $0.1.total > $1.1.total }
    }

    var body: some View {
        HouseScreen(title: "Home") {
            if decks.isEmpty {
                HouseEmptyState(
                    icon: .decks,
                    title: "Nothing here yet",
                    message: "Make a deck and write a few notes. What is due will show up here.",
                    action: .init(label: "Go to decks") { selectedTab = .decks }
                )
            } else {
                summary

                if !active.isEmpty {
                    VStack(alignment: .leading, spacing: Space.s3) {
                        HouseText("Where the work is", role: .eyebrow, ink: \.ink2)

                        ForEach(active, id: \.deck.id) { entry in
                            DeckSummaryRow(deck: entry.deck, counts: entry.counts)
                        }
                    }
                }
            }
        }
    }

    private var summary: some View {
        HouseCard {
            VStack(alignment: .leading, spacing: Space.s4) {
                HStack(spacing: Space.s6) {
                    StatBlock(value: total.due, label: "due")
                    StatBlock(value: total.newAvailable, label: "new")
                }

                if total.isEmpty {
                    HouseText(
                        "Nothing is waiting. Everything you have studied is scheduled further out.",
                        role: .body,
                        ink: \.ink2
                    )
                } else {
                    Button("Start studying") { selectedTab = .study }
                        .buttonStyle(HouseButtonStyle(tier: .accent, size: .medium))
                }
            }
        }
    }
}

private struct StatBlock: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text("\(value)")
                .typeRole(.display)
                .foregroundStyle(value > 0 ? Theme.ink : Theme.ink3)
                .monospacedDigit()

            Text(label)
                .typeRole(.caption)
                .foregroundStyle(Theme.ink3)
                .lineLimit(1)
        }
    }
}

private struct DeckSummaryRow: View {
    let deck: Deck
    let counts: Queue.Counts

    var body: some View {
        NavigationLink(value: DeckRoute.notes(deck.id)) {
            HouseCard(elevation: .flat) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                    HouseText(deck.name, role: .bodyStrong)
                        .lineLimit(1)

                    Spacer(minLength: Space.s3)

                    Text(countLabel)
                        .typeRole(.caption)
                        .foregroundStyle(Theme.ink2)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(deck.name), \(countLabel)")
    }

    private var countLabel: String {
        switch (counts.due, counts.newAvailable) {
        case (let due, 0): "\(due) due"
        case (0, let new): "\(new) new"
        case (let due, let new): "\(due) due, \(new) new"
        }
    }
}
