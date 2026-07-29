import Foundation

// The three enums the model layer stores. All of them are persisted as raw values with a
// default, never as a custom `Codable` enum, because the CloudKit mirror rejects a stored
// property it cannot express as a plain CloudKit field. See spec section 5, constraint 4.

/// What a note produces when it is turned into cards.
///
/// Raw values match the web app's `NoteType` strings in `src/data/types.ts` exactly. There is
/// no migration between the two apps, but keeping the wire spelling identical means the
/// TypeScript engine tests can be lifted as-is when tasks 4 and 5 port them.
enum NoteType: String, CaseIterable, Sendable {
    case basic
    case basicReversed = "basic_reversed"
    case cloze

    var label: String {
        switch self {
        case .basic: "Basic"
        case .basicReversed: "Basic reversed"
        case .cloze: "Cloze"
        }
    }
}

/// FSRS card state. Raw values match `ts-fsrs`'s `State` enum, which the web app stores as
/// `0 | 1 | 2 | 3`, so the ported scheduler tests compare like for like.
enum CardState: Int, CaseIterable, Sendable {
    case new = 0
    case learning = 1
    case review = 2
    case relearning = 3

    /// Learning and relearning cards come first in the queue, ahead of reviews.
    /// `Engine/Queue.swift` (task 7) is the only thing that should need this.
    var isLearning: Bool { self == .learning || self == .relearning }
}

/// The four grades on the rating bar. Raw values match `ts-fsrs`'s `Rating`.
enum Rating: Int, CaseIterable, Sendable {
    case again = 1
    case hard = 2
    case good = 3
    case easy = 4

    var label: String {
        switch self {
        case .again: "Again"
        case .hard: "Hard"
        case .good: "Good"
        case .easy: "Easy"
        }
    }
}
