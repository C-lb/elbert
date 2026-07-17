import { grade } from './grader'
import { clozeAnswer } from './cloze'
import type { Card, Note } from '@/data/types'

export type LearnRound = 1 | 2

export interface LearnStep {
  card: Card
  note: Note
  round: LearnRound
  choices?: string[]
}

export interface LearnOpts {
  /** Seedable RNG for shuffling choices, e.g. a mulberry32 generator. Never call Math.random directly. */
  rng?: () => number
  /** Fired once per card, the moment it clears round 2, if the card was due at session start. */
  onDueReview?: (card: Card) => void
}

export interface LearnSession {
  next(): LearnStep | null
  answerMc(correct: boolean): void
  answerTyped(text: string): 'correct' | 'close' | 'wrong'
  overrideCorrect(): void
  progress(): { cleared: number; total: number }
}

interface Entry {
  card: Card
  note: Note
  round: LearnRound
}

function answerFor(card: Card, note: Note): string {
  return note.type === 'cloze' ? clozeAnswer(note.fields.term, card.ord) : note.fields.definition
}

function shuffle<T>(arr: T[], rng: () => number): T[] {
  const a = [...arr]
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1))
    ;[a[i], a[j]] = [a[j], a[i]]
  }
  return a
}

export function createLearnSession(cards: Card[], notes: Note[], opts: LearnOpts = {}): LearnSession {
  const rng = opts.rng ?? (() => Math.random())
  const onDueReview = opts.onDueReview ?? (() => {})
  const sessionStart = Date.now()

  const noteById = new Map(notes.map(n => [n.id, n]))
  const entries: Entry[] = cards
    .filter(c => noteById.has(c.noteId))
    .map(c => ({ card: c, note: noteById.get(c.noteId)!, round: 1 as LearnRound }))

  const total = entries.length
  let cleared = 0
  const reviewedDue = new Set<string>()
  const dueAtStart = new Set(
    entries.filter(e => e.card.state !== 0 && e.card.due <= sessionStart).map(e => e.card.id)
  )

  // Fixed pool of answers across the whole set, used for round-1 distractors throughout the session.
  const allAnswers = entries.map(e => ({ id: e.card.id, answer: answerFor(e.card, e.note) }))

  const queue: Entry[] = [...entries]

  function buildChoices(entry: Entry): string[] {
    const correct = answerFor(entry.card, entry.note)
    const pool = [...new Set(allAnswers.filter(a => a.id !== entry.card.id && a.answer !== correct).map(a => a.answer))]
    const distractors = shuffle(pool, rng).slice(0, 3)
    return shuffle([correct, ...distractors], rng)
  }

  function requeue() {
    const entry = queue.shift()!
    queue.push(entry)
  }

  function clearCurrent() {
    const entry = queue.shift()!
    cleared++
    if (dueAtStart.has(entry.card.id) && !reviewedDue.has(entry.card.id)) {
      reviewedDue.add(entry.card.id)
      onDueReview(entry.card)
    }
  }

  return {
    next() {
      const entry = queue[0]
      if (!entry) return null
      if (entry.round === 1) {
        return { card: entry.card, note: entry.note, round: 1, choices: buildChoices(entry) }
      }
      return { card: entry.card, note: entry.note, round: 2 }
    },

    answerMc(correct: boolean) {
      const entry = queue[0]
      if (!entry) return
      entry.round = correct ? 2 : 1
      requeue()
    },

    answerTyped(text: string) {
      const entry = queue[0]
      if (!entry) throw new Error('no current card')
      const result = grade(answerFor(entry.card, entry.note), text)
      if (result === 'correct') {
        clearCurrent()
      } else if (result === 'wrong') {
        entry.round = 1
        requeue()
      }
      // 'close': leave the entry in place at round 2, awaiting overrideCorrect().
      return result
    },

    overrideCorrect() {
      if (!queue[0]) return
      clearCurrent()
    },

    progress() {
      return { cleared, total }
    },
  }
}
