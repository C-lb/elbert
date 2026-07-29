import Foundation
import Testing

@testable import FSRSKit

// Thin tests. The real parity check against `ts-fsrs` lives in the app's `SchedulerTests`, where
// Elbert's own model types are in play. These only guard the wrapper's own contract: that the
// generation is what was asked for, and that a value survives the round trip into the library and
// back out unchanged.

@Test("the v6 vector is 21 weights ending in the FSRS-6 decay term")
func v6Vector() {
    #expect(FSRSWeights.v6.count == 21)
    #expect(abs(FSRSWeights.v6[20] - 0.1542) < 1e-9)
}

@Test("the v5 vector is 19 weights, so the two generations are genuinely distinguishable")
func v5Vector() {
    #expect(FSRSWeights.v5.count == 19)
}

@Test("an engine reports the weights it was built with")
func engineReportsWeights() {
    #expect(FSRSEngine(requestRetention: 0.9).weights.count == 21)
    #expect(FSRSEngine(requestRetention: 0.9, weights: FSRSWeights.v5).weights.count == 19)
}

@Test("preview returns all four gradings")
func previewIsComplete() throws {
    let now = Date(timeIntervalSince1970: 1_767_225_600)
    let outcomes = try FSRSEngine(requestRetention: 0.9).preview(card: FSRSCardValue(due: now), now: now)

    #expect(outcomes.count == 4)
    for grade in FSRSGrade.allCases {
        #expect(outcomes[grade] != nil)
    }
}

@Test("next agrees with the matching entry from preview")
func nextMatchesPreview() throws {
    let now = Date(timeIntervalSince1970: 1_767_225_600)
    let engine = FSRSEngine(requestRetention: 0.9)
    let card = FSRSCardValue(due: now, stability: 15.2, difficulty: 6.4, reps: 6, stateRaw: 2)

    let previewed = try #require(engine.preview(card: card, now: now)[.good])
    let applied = try engine.next(card: card, now: now, grade: .good)

    #expect(previewed == applied)
}

@Test("a harder grading never schedules further out than an easier one")
func gradeOrdering() throws {
    let now = Date(timeIntervalSince1970: 1_767_225_600)
    let card = FSRSCardValue(due: now, stability: 15.2, difficulty: 6.4, reps: 6, stateRaw: 2)
    let outcomes = try FSRSEngine(requestRetention: 0.9).preview(card: card, now: now)

    let dues = try FSRSGrade.allCases.map { try #require(outcomes[$0]).due }
    #expect(dues == dues.sorted())
}
