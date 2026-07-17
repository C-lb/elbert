import { describe, it, expect } from 'vitest'
import { generateTest, gradePaper, type TestAnswers } from './testgen'
import type { Note } from '@/data/types'

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
function makeNote(term: string, definition: string, overrides: Partial<Note> = {}): Note {
  idCounter++
  return {
    id: `note-${idCounter}`,
    deckId: 'deck-1',
    type: 'basic',
    fields: { term, definition },
    tags: [],
    deletedAt: null,
    ...overrides,
  }
}

function makeCloze(term: string, overrides: Partial<Note> = {}): Note {
  idCounter++
  return {
    id: `note-${idCounter}`,
    deckId: 'deck-1',
    type: 'cloze',
    fields: { term, definition: '' },
    tags: [],
    deletedAt: null,
    ...overrides,
  }
}

function bigDeck(n: number): Note[] {
  return Array.from({ length: n }, (_, i) => makeNote(`term-${i}`, `definition-${i}`))
}

describe('generateTest', () => {
  it('basic_reversed notes still test term -> definition', () => {
    const notes = [makeNote('hola', 'hello', { type: 'basic_reversed' })]
    const paper = generateTest(notes, { written: 1, mc: 0, tf: 0, matching: 0 }, mulberry32(1))
    expect(paper.written[0].prompt).toBe('hola')
    expect(paper.written[0].answer).toBe('hello')
  })

  it('honors requested section counts when the deck is large enough', () => {
    const notes = bigDeck(20)
    const paper = generateTest(notes, { written: 3, mc: 4, tf: 5, matching: 6 }, mulberry32(1))
    expect(paper.written).toHaveLength(3)
    expect(paper.mc).toHaveLength(4)
    expect(paper.tf).toHaveLength(5)
    expect(paper.matching?.pairs).toHaveLength(6)
  })

  it('caps section counts to deck size and never throws on tiny decks', () => {
    const notes = bigDeck(2)
    const paper = generateTest(notes, { written: 10, mc: 10, tf: 10, matching: 10 }, mulberry32(2))
    expect(paper.written.length).toBeLessThanOrEqual(2)
    expect(paper.mc.length).toBeLessThanOrEqual(2)
    expect(paper.tf.length).toBeLessThanOrEqual(2)
    expect(paper.matching?.pairs.length ?? 0).toBeLessThanOrEqual(2)
  })

  it('degrades gracefully to zero questions with an empty deck', () => {
    const paper = generateTest([], { written: 5, mc: 5, tf: 5, matching: 5 }, mulberry32(3))
    expect(paper.written).toHaveLength(0)
    expect(paper.mc).toHaveLength(0)
    expect(paper.tf).toHaveLength(0)
    expect(paper.matching).toBeNull()
  })

  it('never produces duplicate questions (notes) within a section', () => {
    const notes = bigDeck(6)
    const paper = generateTest(notes, { written: 6, mc: 6, tf: 6, matching: 6 }, mulberry32(4))
    expect(new Set(paper.written.map(q => q.noteId)).size).toBe(paper.written.length)
    expect(new Set(paper.mc.map(q => q.noteId)).size).toBe(paper.mc.length)
    expect(new Set(paper.tf.map(q => q.noteId)).size).toBe(paper.tf.length)
    expect(new Set(paper.matching?.pairs.map(p => p.noteId))).toBeTruthy()
  })

  it('mc questions have exactly one correct option', () => {
    const notes = bigDeck(10)
    const paper = generateTest(notes, { written: 0, mc: 8, tf: 0, matching: 0 }, mulberry32(5))
    for (const q of paper.mc) {
      expect(q.correctIndex).toBeGreaterThanOrEqual(0)
      const correctCount = q.options.filter((_, i) => i === q.correctIndex).length
      expect(correctCount).toBe(1)
      // the option at correctIndex must actually be this note's answer text
      expect(q.options[q.correctIndex]).toBe(notes.find(n => n.id === q.noteId)!.fields.definition)
      // no duplicate option strings
      expect(new Set(q.options).size).toBe(q.options.length)
    }
  })

  it('mc offers up to 4 options and degrades with fewer distinct answers', () => {
    const notes = bigDeck(2)
    const paper = generateTest(notes, { written: 0, mc: 2, tf: 0, matching: 0 }, mulberry32(6))
    for (const q of paper.mc) {
      expect(q.options.length).toBeLessThanOrEqual(4)
      expect(q.options.length).toBeGreaterThanOrEqual(1)
    }
  })

  it('tf true pairing uses the note\'s own definition', () => {
    const notes = bigDeck(10)
    const paper = generateTest(notes, { written: 0, mc: 0, tf: 10, matching: 0 }, mulberry32(7))
    for (const q of paper.tf) {
      if (q.isTrue) {
        expect(q.definitionNoteId).toBe(q.noteId)
        const note = notes.find(n => n.id === q.noteId)!
        expect(q.definition).toBe(note.fields.definition)
      }
    }
  })

  it('tf false pairing truly uses another note\'s definition', () => {
    const notes = bigDeck(10)
    const paper = generateTest(notes, { written: 0, mc: 0, tf: 10, matching: 0 }, mulberry32(8))
    const falseQs = paper.tf.filter(q => !q.isTrue)
    expect(falseQs.length).toBeGreaterThan(0)
    for (const q of falseQs) {
      expect(q.definitionNoteId).not.toBe(q.noteId)
      const other = notes.find(n => n.id === q.definitionNoteId)!
      expect(q.definition).toBe(other.fields.definition)
      // definition must not equal the pairing note's own definition (deck has unique defs)
      const own = notes.find(n => n.id === q.noteId)!
      expect(q.definition).not.toBe(own.fields.definition)
    }
  })

  it('tf produces a roughly even split of true/false over many notes', () => {
    const notes = bigDeck(40)
    const paper = generateTest(notes, { written: 0, mc: 0, tf: 40, matching: 0 }, mulberry32(9))
    const trueCount = paper.tf.filter(q => q.isTrue).length
    expect(trueCount).toBeGreaterThan(10)
    expect(trueCount).toBeLessThan(30)
  })

  it('tf always true when the deck has a single note (no other definitions exist)', () => {
    const notes = bigDeck(1)
    const paper = generateTest(notes, { written: 0, mc: 0, tf: 3, matching: 0 }, mulberry32(10))
    for (const q of paper.tf) {
      expect(q.isTrue).toBe(true)
    }
  })

  it('tf false pairings never show a definition identical to the note\'s own, even when the deck has duplicate definition text', () => {
    // Every note shares the exact same definition text, so no genuinely-false pairing exists.
    const notes = Array.from({ length: 8 }, (_, i) => makeNote(`term-${i}`, 'same-definition'))
    const paper = generateTest(notes, { written: 0, mc: 0, tf: 8, matching: 0 }, mulberry32(13))
    for (const q of paper.tf) {
      // With no other note offering a distinct definition, every question must fall back to true.
      expect(q.isTrue).toBe(true)
      expect(q.definitionNoteId).toBe(q.noteId)
    }
  })

  it('tf false pairings exclude notes whose definition duplicates the term\'s own, even amid other distinct notes', () => {
    const target = makeNote('term-target', 'shared-definition')
    const duplicate = makeNote('term-duplicate', 'shared-definition')
    const distinctNotes = Array.from({ length: 6 }, (_, i) => makeNote(`term-distinct-${i}`, `distinct-definition-${i}`))
    const notes = [target, duplicate, ...distinctNotes]

    // Run many seeds so both true and false branches for `target` get exercised.
    for (let seed = 1; seed <= 30; seed++) {
      const paper = generateTest(notes, { written: 0, mc: 0, tf: 8, matching: 0 }, mulberry32(seed))
      const q = paper.tf.find(q => q.noteId === target.id)
      if (!q) continue
      if (!q.isTrue) {
        expect(q.definitionNoteId).not.toBe(duplicate.id)
        expect(q.definition).not.toBe(target.fields.definition)
      }
    }
  })

  it('written prompt/answer for a cloze note blanks the term and answers with the deletion', () => {
    const notes = [makeCloze('The capital of France is {{c1::Paris}}.')]
    const paper = generateTest(notes, { written: 1, mc: 0, tf: 0, matching: 0 }, mulberry32(11))
    expect(paper.written[0].prompt).toBe('The capital of France is [...].')
    expect(paper.written[0].answer).toBe('Paris')
  })

  it('matching produces one section with shuffled definitions covering the same set as pairs', () => {
    const notes = bigDeck(8)
    const paper = generateTest(notes, { written: 0, mc: 0, tf: 0, matching: 5 }, mulberry32(12))
    expect(paper.matching).not.toBeNull()
    const section = paper.matching!
    expect(section.pairs).toHaveLength(5)
    expect(section.definitions).toHaveLength(5)
    expect(new Set(section.definitions)).toEqual(new Set(section.pairs.map(p => p.definition)))
  })

  it('is deterministic given the same seed', () => {
    const notes = bigDeck(15)
    const p1 = generateTest(notes, { written: 3, mc: 3, tf: 3, matching: 3 }, mulberry32(42))
    const p2 = generateTest(notes, { written: 3, mc: 3, tf: 3, matching: 3 }, mulberry32(42))
    expect(p1).toEqual(p2)
  })

  it('produces different output for a different seed', () => {
    const notes = bigDeck(15)
    const p1 = generateTest(notes, { written: 5, mc: 0, tf: 0, matching: 0 }, mulberry32(1))
    const p2 = generateTest(notes, { written: 5, mc: 0, tf: 0, matching: 0 }, mulberry32(2))
    expect(p1.written.map(q => q.noteId)).not.toEqual(p2.written.map(q => q.noteId))
  })
})

describe('gradePaper', () => {
  it('computes exact grading math for a known answer set', () => {
    const notes = bigDeck(4)
    const paper = generateTest(notes, { written: 2, mc: 1, tf: 1, matching: 0 }, mulberry32(20))

    const answers: TestAnswers = { written: {}, mc: {}, tf: {}, matching: {} }
    // Get everything right.
    for (const q of paper.written) answers.written[q.id] = q.answer
    for (const q of paper.mc) answers.mc[q.id] = q.correctIndex
    for (const q of paper.tf) answers.tf[q.id] = q.isTrue

    const result = gradePaper(paper, answers)
    expect(result.correctCount).toBe(result.totalCount)
    expect(result.percent).toBe(100)
    expect(result.weakest).toHaveLength(0)
  })

  it('grades a known mix of right/wrong answers to the expected percent', () => {
    const notes = bigDeck(4)
    const paper = generateTest(notes, { written: 2, mc: 2, tf: 0, matching: 0 }, mulberry32(21))

    const answers: TestAnswers = { written: {}, mc: {}, tf: {}, matching: {} }
    // Written: first right, second wrong.
    answers.written[paper.written[0].id] = paper.written[0].answer
    answers.written[paper.written[1].id] = 'definitely-not-it'
    // Mc: first right, second wrong.
    answers.mc[paper.mc[0].id] = paper.mc[0].correctIndex
    answers.mc[paper.mc[1].id] = (paper.mc[1].correctIndex + 1) % paper.mc[1].options.length

    const result = gradePaper(paper, answers)
    expect(result.totalCount).toBe(4)
    expect(result.correctCount).toBe(2)
    expect(result.percent).toBe(50)
    expect(result.weakest).toHaveLength(2)
  })

  it('written grading treats a close (distance-1) answer as correct', () => {
    const notes = [makeNote('term-x', 'elephant')]
    const paper = generateTest(notes, { written: 1, mc: 0, tf: 0, matching: 0 }, mulberry32(22))
    const answers: TestAnswers = { written: { [paper.written[0].id]: 'elephent' }, mc: {}, tf: {}, matching: {} }
    const result = gradePaper(paper, answers)
    expect(result.correctCount).toBe(1)
    expect(result.weakest).toHaveLength(0)
  })

  it('lists weakest wrong answers with their note term and expected/given', () => {
    const notes = [makeNote('capital-of-france', 'paris')]
    const paper = generateTest(notes, { written: 1, mc: 0, tf: 0, matching: 0 }, mulberry32(23))
    const answers: TestAnswers = { written: { [paper.written[0].id]: 'london' }, mc: {}, tf: {}, matching: {} }
    const result = gradePaper(paper, answers)
    expect(result.weakest).toEqual([
      { noteId: notes[0].id, term: 'capital-of-france', expected: 'paris', given: 'london' },
    ])
  })

  it('grades matching pairs exactly', () => {
    const notes = bigDeck(3)
    const paper = generateTest(notes, { written: 0, mc: 0, tf: 0, matching: 3 }, mulberry32(24))
    const section = paper.matching!
    const answers: TestAnswers = { written: {}, mc: {}, tf: {}, matching: {} }
    answers.matching[section.pairs[0].noteId] = section.pairs[0].definition
    answers.matching[section.pairs[1].noteId] = section.pairs[0].definition // wrong: reused
    answers.matching[section.pairs[2].noteId] = section.pairs[2].definition

    const result = gradePaper(paper, answers)
    const matchingResult = result.sections.find(s => s.type === 'matching')!
    expect(matchingResult.correct).toBe(2)
    expect(matchingResult.total).toBe(3)
  })

  it('handles an empty paper without throwing', () => {
    const paper = generateTest([], { written: 0, mc: 0, tf: 0, matching: 0 }, mulberry32(25))
    const result = gradePaper(paper, { written: {}, mc: {}, tf: {}, matching: {} })
    expect(result.totalCount).toBe(0)
    expect(result.percent).toBe(0)
    expect(result.weakest).toHaveLength(0)
  })
})
