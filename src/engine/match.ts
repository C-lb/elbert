import { answerForNote } from './learn'
import { parseCloze, renderCloze } from './cloze'
import type { Card, Note } from '@/data/types'

export interface MatchTile {
  id: string
  noteId: string
  kind: 'term' | 'answer'
  text: string
  matched: boolean
}

export type MatchResult = 'first' | 'match' | 'miss' | 'done' | 'ignored'

export interface MatchGame {
  tiles(): MatchTile[]
  pick(tileId: string): MatchResult
  misses(): number
}

/** The lowest cloze ordinal in a note's term text, defaulting to 1 for non-cloze notes. */
function firstOrd(note: Note): number {
  if (note.type !== 'cloze') return 1
  const ords = parseCloze(note.fields.term)
  return ords[0]?.ord ?? 1
}

/** A minimal stand-in Card carrying only the ordinal, for reuse of answerForNote(). */
function pseudoCard(note: Note, ord: number): Card {
  return {
    id: '',
    noteId: note.id,
    ord,
    due: 0,
    stability: 0,
    difficulty: 0,
    reps: 0,
    lapses: 0,
    state: 0,
    lastReview: null,
    suspended: 0,
    learningSteps: 0,
    deletedAt: null,
  }
}

function termText(note: Note, ord: number): string {
  return note.type === 'cloze' ? renderCloze(note.fields.term, ord, false) : note.fields.term
}

function shuffle<T>(arr: T[], rng: () => number): T[] {
  const a = [...arr]
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1))
    ;[a[i], a[j]] = [a[j], a[i]]
  }
  return a
}

/** Picks up to `n` notes: all of them if there are fewer, otherwise an rng-sampled subset. */
function pickNotes(notes: Note[], n: number, rng: () => number): Note[] {
  if (notes.length <= n) return notes
  return shuffle(notes, rng).slice(0, n)
}

/**
 * Builds a match game from up to 6 notes: one term tile + one answer (definition) tile per
 * note, shuffled together into a single grid order. Never uses Math.random directly — the
 * caller supplies the rng so grid order and note selection are reproducible in tests.
 */
export function createMatchGame(notes: Note[], rng: () => number): MatchGame {
  const chosen = pickNotes(notes, 6, rng)

  const pairs: MatchTile[] = []
  for (const note of chosen) {
    const ord = firstOrd(note)
    pairs.push({ id: `${note.id}-term`, noteId: note.id, kind: 'term', text: termText(note, ord), matched: false })
    pairs.push({
      id: `${note.id}-answer`,
      noteId: note.id,
      kind: 'answer',
      text: answerForNote(note, pseudoCard(note, ord)),
      matched: false,
    })
  }

  const grid = shuffle(pairs, rng)
  const byId = new Map(grid.map(t => [t.id, t]))

  let misses = 0
  let matchedCount = 0
  let firstPick: MatchTile | null = null

  return {
    tiles() {
      return grid.map(t => ({ ...t }))
    },

    pick(tileId: string): MatchResult {
      const tile = byId.get(tileId)
      if (!tile) return 'ignored'
      if (tile.matched) return 'ignored'
      if (firstPick && firstPick.id === tileId) return 'ignored'

      if (!firstPick) {
        firstPick = tile
        return 'first'
      }

      const a = firstPick
      const b = tile
      firstPick = null

      if (a.noteId === b.noteId && a.kind !== b.kind) {
        a.matched = true
        b.matched = true
        matchedCount += 2
        return matchedCount === grid.length ? 'done' : 'match'
      }

      misses++
      return 'miss'
    },

    misses() {
      return misses
    },
  }
}
