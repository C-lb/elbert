import { describe, it, expect, vi } from 'vitest'
import { createLearnSession } from './learn'
import type { Card, Note } from '@/data/types'

function mulberry32(seed: number): () => number {
  let a = seed
  return function () {
    a |= 0
    a = (a + 0x6d2b79f5) | 0
    let t = Math.imul(a ^ (a >>> 15), 1 | a)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

let idCounter = 0
function makeNote(definition: string, overrides: Partial<Note> = {}): Note {
  idCounter++
  return {
    id: `note-${idCounter}`,
    deckId: 'deck-1',
    type: 'basic',
    fields: { term: `term-${idCounter}`, definition },
    tags: [],
    deletedAt: null,
    ...overrides,
  }
}

function makeCard(note: Note, overrides: Partial<Card> = {}): Card {
  idCounter++
  return {
    id: `card-${idCounter}`,
    noteId: note.id,
    ord: 0,
    due: Date.now() + 100000,
    stability: 0,
    difficulty: 0,
    reps: 0,
    lapses: 0,
    state: 0,
    lastReview: null,
    suspended: 0,
    learningSteps: 0,
    deletedAt: null,
    ...overrides,
  }
}

describe('createLearnSession', () => {
  it('clears a card only after passing both round 1 (mc) and round 2 (typed)', () => {
    const note = makeNote('perro')
    const card = makeCard(note)
    const session = createLearnSession([card], [note], { rng: mulberry32(1) })

    let step = session.next()
    expect(step?.round).toBe(1)
    expect(session.progress()).toEqual({ cleared: 0, total: 1 })

    session.answerMc(true)
    expect(session.progress()).toEqual({ cleared: 0, total: 1 })

    step = session.next()
    expect(step?.round).toBe(2)

    const result = session.answerTyped('perro')
    expect(result).toBe('correct')
    expect(session.progress()).toEqual({ cleared: 1, total: 1 })
    expect(session.next()).toBeNull()
  })

  it('resets a card to round 1 on a miss at round 1', () => {
    const note = makeNote('perro')
    const card = makeCard(note)
    const other = makeNote('gato')
    const otherCard = makeCard(other)
    const session = createLearnSession([card, otherCard], [note, other], { rng: mulberry32(2) })

    // Find and fail the first card's round 1
    let step = session.next()!
    session.answerMc(false)

    // Cycle through until we see that card's round again — should be round 1 again
    let seenAgain = false
    for (let i = 0; i < 10; i++) {
      const s = session.next()
      if (!s) break
      if (s.card.id === step.card.id) {
        expect(s.round).toBe(1)
        seenAgain = true
        break
      }
      // answer whatever's current so we can advance
      if (s.round === 1) session.answerMc(true)
      else session.answerTyped('nonsense-wrong-answer')
    }
    expect(seenAgain).toBe(true)
  })

  it('resets a card to round 1 on a miss at round 2 (typed wrong)', () => {
    const note = makeNote('perro')
    const card = makeCard(note)
    const session = createLearnSession([card], [note], { rng: mulberry32(3) })

    session.next()
    session.answerMc(true)
    const step2 = session.next()
    expect(step2?.round).toBe(2)

    const result = session.answerTyped('totally wrong answer')
    expect(result).toBe('wrong')
    expect(session.progress()).toEqual({ cleared: 0, total: 1 })

    const step3 = session.next()
    expect(step3?.round).toBe(1)
  })

  it('close grade allows an "I was right" override to clear the card', () => {
    const note = makeNote('perro')
    const card = makeCard(note)
    const session = createLearnSession([card], [note], { rng: mulberry32(4) })

    session.next()
    session.answerMc(true)
    session.next()

    // "perr" is levenshtein distance 1 from "perro" (5 chars) -> close
    const result = session.answerTyped('perr')
    expect(result).toBe('close')
    expect(session.progress()).toEqual({ cleared: 0, total: 1 })

    session.overrideCorrect()
    expect(session.progress()).toEqual({ cleared: 1, total: 1 })
  })

  it('declineClose resets a close-graded card to round 1, requeues it behind other cards, and never fires onDueReview', () => {
    const note = makeNote('perro')
    const dueCard = makeCard(note, { state: 2, due: Date.now() - 1000 })
    const other = makeNote('gato')
    const otherCard = makeCard(other)
    const onDueReview = vi.fn()
    const session = createLearnSession([dueCard, otherCard], [note, other], {
      rng: mulberry32(10),
      onDueReview,
    })

    // dueCard through round 1 -> round 2.
    let step = session.next()!
    expect(step.card.id).toBe(dueCard.id)
    expect(step.round).toBe(1)
    session.answerMc(true)

    // otherCard through round 1 -> round 2 (not cleared, stays in the queue).
    step = session.next()!
    expect(step.card.id).toBe(otherCard.id)
    expect(step.round).toBe(1)
    session.answerMc(true)

    // Back to dueCard's round 2, grade it 'close'.
    step = session.next()!
    expect(step.card.id).toBe(dueCard.id)
    expect(step.round).toBe(2)
    expect(session.answerTyped('perr')).toBe('close')

    session.declineClose()
    expect(session.progress()).toEqual({ cleared: 0, total: 2 })
    expect(onDueReview).not.toHaveBeenCalled()

    // The stall scenario: next() must return a DIFFERENT entry, not the same declined one stuck at front.
    const after = session.next()!
    expect(after.card.id).not.toBe(dueCard.id)
    expect(after.card.id).toBe(otherCard.id)
    expect(after.round).toBe(2)

    // Cycling back around, the declined card should be back at round 1.
    let sawDueCardAgain = false
    for (let i = 0; i < 10; i++) {
      const s = session.next()
      if (!s) break
      if (s.card.id === dueCard.id) {
        expect(s.round).toBe(1)
        sawDueCardAgain = true
        break
      }
      if (s.round === 1) session.answerMc(true)
      else session.answerTyped('nonsense')
    }
    expect(sawDueCardAgain).toBe(true)
  })

  it('offers up to 3 distractors (4 choices) when >=4 cards are in the set, and always includes the correct answer', () => {
    const notes = ['perro', 'gato', 'pajaro', 'pez', 'caballo'].map(d => makeNote(d))
    const cards = notes.map(n => makeCard(n))
    const session = createLearnSession(cards, notes, { rng: mulberry32(5) })

    const step = session.next()!
    expect(step.round).toBe(1)
    expect(step.choices).toBeDefined()
    expect(step.choices!.length).toBe(4)
    const correctAnswer = notes.find(n => n.id === step.card.noteId)!.fields.definition
    expect(step.choices).toContain(correctAnswer)
    expect(new Set(step.choices).size).toBe(step.choices!.length)
  })

  it('offers fewer choices when the set is small (2 cards)', () => {
    const notes = ['perro', 'gato'].map(d => makeNote(d))
    const cards = notes.map(n => makeCard(n))
    const session = createLearnSession(cards, notes, { rng: mulberry32(6) })

    const step = session.next()!
    expect(step.choices!.length).toBe(2)
    const correctAnswer = notes.find(n => n.id === step.card.noteId)!.fields.definition
    expect(step.choices).toContain(correctAnswer)
  })

  it('fires onDueReview exactly once for a due card that clears both rounds', () => {
    const note = makeNote('perro')
    const dueCard = makeCard(note, { state: 2, due: Date.now() - 1000 })
    const onDueReview = vi.fn()
    const session = createLearnSession([dueCard], [note], { rng: mulberry32(7), onDueReview })

    session.next()
    session.answerMc(true)
    session.next()
    session.answerTyped('perro')

    expect(onDueReview).toHaveBeenCalledTimes(1)
    expect(onDueReview).toHaveBeenCalledWith(dueCard)
  })

  it('never fires onDueReview for a non-due (new) card', () => {
    const note = makeNote('perro')
    const newCard = makeCard(note, { state: 0, due: Date.now() - 1000 })
    const onDueReview = vi.fn()
    const session = createLearnSession([newCard], [note], { rng: mulberry32(8), onDueReview })

    session.next()
    session.answerMc(true)
    session.next()
    session.answerTyped('perro')

    expect(onDueReview).not.toHaveBeenCalled()
  })

  it('never fires onDueReview for a due-but-currently-future card', () => {
    const note = makeNote('perro')
    const futureCard = makeCard(note, { state: 2, due: Date.now() + 100000 })
    const onDueReview = vi.fn()
    const session = createLearnSession([futureCard], [note], { rng: mulberry32(9), onDueReview })

    session.next()
    session.answerMc(true)
    session.next()
    session.answerTyped('perro')

    expect(onDueReview).not.toHaveBeenCalled()
  })

  it('produces a deterministic order/choice-set with a seeded rng', () => {
    const notes = ['perro', 'gato', 'pajaro', 'pez'].map(d => makeNote(d))
    const cards = notes.map(n => makeCard(n))

    const s1 = createLearnSession(cards, notes, { rng: mulberry32(42) })
    const s2 = createLearnSession(cards, notes, { rng: mulberry32(42) })

    const step1 = s1.next()!
    const step2 = s2.next()!
    expect(step1.card.id).toBe(step2.card.id)
    expect(step1.choices).toEqual(step2.choices)
  })
})
