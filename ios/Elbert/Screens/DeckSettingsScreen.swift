import SwiftData
import SwiftUI

/// How much of a deck to see, and how well you want to remember it.
///
/// Two settings, both of which change the schedule, so both say what they will do in plain words
/// rather than leaving a number to be interpreted. Retention in particular is a knob people turn
/// the wrong way: "I want to remember more" reads like a free upgrade until you notice it means
/// more reviews every day, forever.
struct DeckSettingsScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(ToastCentre.self) private var toasts

    let deck: Deck

    /// The range FSRS behaves sensibly in. Below 70 percent you are deliberately forgetting most
    /// of it; above 97 the interval collapses and the workload runs away.
    private static let retentionRange: ClosedRange<Double> = 0.70...0.97

    var body: some View {
        HouseScreen(title: deck.name) {
            newCardsSection
            retentionSection
        }
        .onDisappear(perform: persist)
    }

    // MARK: - New cards per day

    private var newCardsSection: some View {
        HouseCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                SettingHeader(
                    title: "New cards per day",
                    detail: "How many cards this deck introduces before it stops handing you more. Reviews are not capped, so this is the dial that decides how big the deck's daily workload eventually gets."
                )

                Stepper(value: newPerDay, in: 0...100, step: 5) {
                    HStack(spacing: Space.s2) {
                        Text("\(deck.newPerDay)")
                            .typeRole(.h3)
                            .monospacedDigit()

                        Text(deck.newPerDay == 0 ? "paused" : "a day")
                            .typeRole(.caption)
                            .foregroundStyle(Theme.ink3)
                    }
                }
                .tint(Theme.accent)
                // A stepper folds its label into itself, so the number is not an element of its
                // own. Without this, the current value is invisible to VoiceOver and to any test
                // that wants to read it back.
                .accessibilityLabel("New cards per day")
                .accessibilityValue("\(deck.newPerDay)")
                // The label above is *appended* to what the stepper folds in, so the element reads
                // "10, a day, New cards per day" and cannot be found by its label. The identifier
                // is the only stable handle on it.
                .accessibilityIdentifier("New cards per day")

                if deck.newPerDay == 0 {
                    HouseText(
                        "Nothing new will be introduced. Cards already in the schedule still come back.",
                        role: .caption,
                        ink: \.ink2
                    )
                }
            }
        }
    }

    // MARK: - Desired retention

    private var retentionSection: some View {
        HouseCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                SettingHeader(
                    title: "Desired retention",
                    detail: "The share of cards you want to still know when they come back around."
                )

                HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                    Text(percentLabel)
                        .typeRole(.h3)
                        .monospacedDigit()

                    Text("of cards remembered")
                        .typeRole(.caption)
                        .foregroundStyle(Theme.ink3)
                        .lineLimit(1)
                }

                Slider(
                    value: retention,
                    in: Self.retentionRange,
                    step: 0.01
                )
                .tint(Theme.accent)
                .accessibilityLabel("Desired retention")
                .accessibilityValue(percentLabel)

                HouseText(plainEffect, role: .body, ink: \.ink2)

                if let interval = intervalEffect {
                    HouseText(interval, role: .caption, ink: \.ink3)
                }
            }
        }
    }

    // MARK: - Bindings

    private var newPerDay: Binding<Int> {
        Binding(
            get: { deck.newPerDay },
            set: { deck.newPerDay = max(0, $0) }
        )
    }

    private var retention: Binding<Double> {
        Binding(
            get: { min(max(deck.desiredRetention, Self.retentionRange.lowerBound), Self.retentionRange.upperBound) },
            set: { deck.desiredRetention = $0 }
        )
    }

    // MARK: - Copy

    private var percentLabel: String {
        "\(Int((deck.desiredRetention * 100).rounded()))%"
    }

    /// The trade-off, said as a trade-off. A number on its own reads as a score to maximise.
    private var plainEffect: String {
        let forgotten = Int(((1 - deck.desiredRetention) * 100).rounded())

        switch deck.desiredRetention {
        case ..<0.80:
            return "Long gaps and few reviews. Roughly \(forgotten) in 100 cards will have slipped by the time you see them again, and forgetting one costs you the time to relearn it."
        case ..<0.90:
            return "Fewer reviews for a bit more forgetting. Roughly \(forgotten) in 100 will have slipped when they come back."
        case ..<0.94:
            return "The usual setting. Roughly \(forgotten) in 100 will have slipped, which is about the point where extra reviews stop paying for themselves."
        default:
            return "Short gaps and a lot of reviews. Only about \(forgotten) in 100 will have slipped, but the daily workload climbs steeply for the last few percent."
        }
    }

    /// What the setting does to a real interval, rather than in the abstract.
    ///
    /// Runs a synthetic well-known card through the scheduler at the current retention, so the
    /// slider answers "and what does that mean in days" without the person having to study for a
    /// month to find out.
    private var intervalEffect: String? {
        let reference = Card(
            due: Date(),
            stability: 30,
            difficulty: 5,
            reps: 8,
            state: .review,
            lastReview: Date()
        )

        guard
            let outcomes = try? Scheduler.outcomes(for: reference, retention: deck.desiredRetention),
            let good = outcomes[.good]
        else { return nil }

        let label = Scheduler.intervalLabel(from: Date(), to: good.due)
        return "A card you already know well would come back in about \(label)."
    }

    // MARK: - Saving

    /// Saved on the way out rather than on every tick of the slider, which would write a hundred
    /// times per drag. Nothing reads these values mid-drag except this screen.
    private func persist() {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            toasts.show(.error("Those settings did not save."))
        }
    }
}

private struct SettingHeader: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HouseText(title, role: .h3)
            HouseText(detail, role: .caption, ink: \.ink2)
        }
    }
}
