import { v4 as uuid } from 'uuid'
import type { Card, Note } from '@/data/types'
import { parseCloze } from './cloze'

const blank = (noteId: string, ord: number): Card => ({
  id: uuid(), noteId, ord, due: Date.now(), stability: 0, difficulty: 0,
  reps: 0, lapses: 0, state: 0, lastReview: null, suspended: 0, deletedAt: null, learningSteps: 0,
})

export function cardsForNote(note: Note): Card[] {
  if (note.type === 'basic') return [blank(note.id, 0)]
  if (note.type === 'basic_reversed') return [blank(note.id, 0), blank(note.id, 1)]
  return parseCloze(note.fields.term).map(c => blank(note.id, c.ord))
}
