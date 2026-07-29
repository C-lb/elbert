import Foundation
import SwiftData
import Testing

@testable import Elbert

// Ported from `src/engine/session.ts`, which has no tests of its own in the web app. The requeue
// rule is the only thing here with an edge, and it has two: the horizon and the short queue.

@Suite("Study session")
@MainActor
struct StudySessionTests {
    private let now = Date(timeIntervalSince1970: 1_767_225_600)

    /// Cards need no store to be sequenced, so these stay unattached.
    private func cards(_ count: Int, dueOffset: TimeInterval = 86_400) -> [Card] {
        (0..<count).map { _ in Card(due: now.addingTimeInterval(dueOffset)) }
    }

    @Test("an empty session is finished before it starts")
    func emptySession() {
        let session = StudySession(cards: [])
        #expect(session.current == nil)
        #expect(session.isFinished)
        #expect(session.remaining == 0)
    }

    @Test("answering a card that is not due again soon removes it")
    func cardLeavesSession() {
        let session = StudySession(cards: cards(3))
        let first = session.current

        session.answer(at: now)

        #expect(session.remaining == 2)
        #expect(session.current?.id != first?.id)
        #expect(session.answered == 1)
    }

    @Test("a card due back within the horizon is requeued five places down")
    func requeuedAtOffset() {
        let queue = cards(10)
        queue[0].due = now.addingTimeInterval(10 * 60)
        let session = StudySession(cards: queue)
        let requeued = queue[0].id

        session.answer(at: now)

        #expect(session.remaining == 10)
        #expect(session.queue[5].id == requeued)
    }

    @Test("the horizon is inclusive at exactly twenty minutes")
    func horizonBoundary() {
        let atHorizon = cards(3)
        atHorizon[0].due = now.addingTimeInterval(StudySession.requeueHorizon)
        let inside = StudySession(cards: atHorizon)
        inside.answer(at: now)
        #expect(inside.remaining == 3)

        let pastHorizon = cards(3)
        pastHorizon[0].due = now.addingTimeInterval(StudySession.requeueHorizon + 1)
        let outside = StudySession(cards: pastHorizon)
        outside.answer(at: now)
        #expect(outside.remaining == 2)
    }

    @Test("a queue shorter than the offset puts the card at the end")
    func shortQueueClamps() {
        let queue = cards(3)
        queue[0].due = now.addingTimeInterval(60)
        let session = StudySession(cards: queue)
        let requeued = queue[0].id

        session.answer(at: now)

        #expect(session.remaining == 3)
        #expect(session.queue.last?.id == requeued)
    }

    @Test("the last card requeued becomes the only card, not a lost one")
    func singleCardRequeue() {
        let queue = cards(1)
        queue[0].due = now.addingTimeInterval(60)
        let session = StudySession(cards: queue)

        session.answer(at: now)

        #expect(session.remaining == 1)
        #expect(session.current?.id == queue[0].id)
        #expect(!session.isFinished)
    }

    @Test("a requeued card counts again when it is answered again")
    func answeredCountsRequeues() {
        let queue = cards(1)
        queue[0].due = now.addingTimeInterval(60)
        let session = StudySession(cards: queue)

        session.answer(at: now)
        queue[0].due = now.addingTimeInterval(86_400)
        session.answer(at: now)

        #expect(session.answered == 2)
        #expect(session.isFinished)
    }

    @Test("a session ends once every card has left")
    func sessionCompletes() {
        let session = StudySession(cards: cards(3))
        for _ in 0..<3 { session.answer(at: now) }

        #expect(session.isFinished)
        #expect(session.current == nil)
        #expect(session.answered == 3)
    }

    @Test("answering an empty session does nothing rather than trapping")
    func answeringEmptyIsSafe() {
        let session = StudySession(cards: [])
        session.answer(at: now)
        #expect(session.answered == 0)
    }

    @Test("a dropped card leaves without being counted, wherever it sits")
    func dropRemovesWithoutCounting() {
        let queue = cards(3)
        let session = StudySession(cards: queue)

        session.drop(queue[2])

        #expect(session.remaining == 2)
        #expect(session.answered == 0)
        #expect(!session.queue.contains { $0.id == queue[2].id })
    }
}
