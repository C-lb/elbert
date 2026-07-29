import Foundation
import Observation

/// One pass through a queue of cards.
///
/// Port of `src/engine/session.ts`. Holds no store of its own: `Card` is a reference type, so the
/// session tracks which cards are still to be seen and the scheduler owns what happens to them.
///
/// The one rule with any subtlety is requeueing. A card whose new due time is within the horizon
/// comes back inside this session rather than leaving it, which is what makes a learning step of
/// "10 minutes" mean anything on a session that lasts eight.
@Observable
final class StudySession {
    /// A card due back within twenty minutes is worth seeing again now. Beyond that it belongs to
    /// a future session, and holding it here would just pad the count.
    static let requeueHorizon: TimeInterval = 20 * 60

    /// Far enough back that a few other cards come between, close enough to still be this session.
    static let requeueOffset = 5

    private(set) var queue: [Card]

    /// How many cards have been rated, requeues included. What the summary counts.
    private(set) var answered = 0

    init(cards: [Card]) {
        self.queue = cards
    }

    var current: Card? { queue.first }

    var remaining: Int { queue.count }

    var isFinished: Bool { queue.isEmpty }

    /// Drops the current card, then puts it back five places down if it is due again soon.
    ///
    /// Call after the scheduler has updated the card, since the decision reads its new due date.
    func answer(at now: Date = Date()) {
        guard !queue.isEmpty else { return }

        let card = queue.removeFirst()
        answered += 1

        if card.due <= now.addingTimeInterval(Self.requeueHorizon) {
            // Clamped, so a queue shorter than the offset puts the card at the end rather than
            // trapping it behind an index that does not exist.
            queue.insert(card, at: min(Self.requeueOffset, queue.count))
        }
    }

    /// Removes a card from the rest of the session without counting it as answered. For suspending
    /// or deleting mid-session, where the card should stop appearing but nothing was studied.
    func drop(_ card: Card) {
        queue.removeAll { $0.id == card.id }
    }
}
