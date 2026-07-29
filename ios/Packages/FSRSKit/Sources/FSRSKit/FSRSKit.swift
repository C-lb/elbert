import FSRS
import Foundation

// Why this package exists.
//
// `swift-fsrs` declares a class called `FSRS` inside a module called `FSRS`. In Swift a type
// shadows a module of the same name, so from any module that imports it, `FSRS.Card` resolves as
// "the member `Card` of the class `FSRS`", which does not exist. That is only a problem for a
// client that has its own `Card`, `Rating`, or `CardState` to disambiguate against, which Elbert
// does for all three.
//
// Inside this module there is no such clash, so the library's types can be named normally and
// re-exposed under names Elbert can actually reach. The wrapper earns its keep twice over: it is
// also the only place that touches an untagged upstream revision, so if the pin ever moves, this
// is the file that breaks rather than the app.

/// The four gradings Elbert offers. The library also has a rating 0, "manual", which is a
/// rescheduling hook rather than something a person can press, and is deliberately not here.
public enum FSRSGrade: Int, CaseIterable, Sendable {
    case again = 1
    case hard = 2
    case good = 3
    case easy = 4

    fileprivate var libraryRating: Rating {
        switch self {
        case .again: .again
        case .hard: .hard
        case .good: .good
        case .easy: .easy
        }
    }
}

/// A card's scheduling state, as a plain value with no library types in it.
///
/// `stateRaw` stays an `Int` rather than becoming an enum because the mapping is already spelled
/// out on Elbert's own `CardState`, and one authority for it is enough.
public struct FSRSCardValue: Equatable, Sendable {
    public var due: Date
    public var stability: Double
    public var difficulty: Double
    public var reps: Int
    public var lapses: Int
    public var learningSteps: Int
    public var stateRaw: Int
    public var lastReview: Date?

    public init(
        due: Date = Date(),
        stability: Double = 0,
        difficulty: Double = 0,
        reps: Int = 0,
        lapses: Int = 0,
        learningSteps: Int = 0,
        stateRaw: Int = 0,
        lastReview: Date? = nil
    ) {
        self.due = due
        self.stability = stability
        self.difficulty = difficulty
        self.reps = reps
        self.lapses = lapses
        self.learningSteps = learningSteps
        self.stateRaw = stateRaw
        self.lastReview = lastReview
    }

    fileprivate var libraryCard: Card {
        Card(
            due: due,
            stability: stability,
            difficulty: difficulty,
            // Both are recomputed by the library from `lastReview` and the review time, so
            // passing zero is not a shortcut. The web app passes zero for the same reason.
            elapsedDays: 0,
            scheduledDays: 0,
            learningSteps: learningSteps,
            reps: reps,
            lapses: lapses,
            state: CardState(rawValue: stateRaw) ?? .new,
            lastReview: lastReview
        )
    }

    fileprivate init(_ card: Card) {
        self.due = card.due
        self.stability = card.stability
        self.difficulty = card.difficulty
        self.reps = card.reps
        self.lapses = card.lapses
        self.learningSteps = card.learningSteps
        self.stateRaw = card.state.rawValue
        self.lastReview = card.lastReview
    }
}

/// The parameter vectors, and what they select.
///
/// The library keys the algorithm generation on the length of the weight vector: 19 weights is
/// FSRS-5, 21 is FSRS-6. It defaults to FSRS-5 and refuses to migrate 19 to 21 on its own, which
/// is correct of it, and means FSRS-6 has to be asked for by name.
public enum FSRSWeights {
    /// FSRS-6. Matches the web app's `ts-fsrs` 5.4.1 defaults, decay term included.
    public static let v6: [Double] = FSRSDefaults.defaultWv6

    /// FSRS-5, the library's own default. Kept so the generation choice is visible in one place
    /// rather than implied by an omission.
    public static let v5: [Double] = FSRSParameters().w
}

/// A configured scheduler.
public struct FSRSEngine: Sendable {
    private let parameters: FSRSParameters

    /// - Parameters:
    ///   - requestRetention: the probability of recall being scheduled for, 0 to 1.
    ///   - weights: see ``FSRSWeights``.
    public init(requestRetention: Double, weights: [Double] = FSRSWeights.v6) {
        self.parameters = FSRSParameters(requestRetention: requestRetention, w: weights)
    }

    /// The weight vector actually in force, so a caller can assert which generation it got.
    public var weights: [Double] { parameters.w }

    /// Where the card lands under each of the four gradings, without committing to any of them.
    public func preview(card: FSRSCardValue, now: Date) throws -> [FSRSGrade: FSRSCardValue] {
        let scheduled = try FSRS(parameters: parameters).repeat(card: card.libraryCard, now: now)

        var outcomes: [FSRSGrade: FSRSCardValue] = [:]
        for grade in FSRSGrade.allCases {
            guard let item = scheduled[grade.libraryRating] else { continue }
            outcomes[grade] = FSRSCardValue(item.card)
        }
        return outcomes
    }

    /// Where the card lands under one grading.
    public func next(card: FSRSCardValue, now: Date, grade: FSRSGrade) throws -> FSRSCardValue {
        let item = try FSRS(parameters: parameters)
            .next(card: card.libraryCard, now: now, grade: grade.libraryRating)
        return FSRSCardValue(item.card)
    }
}
