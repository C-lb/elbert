import { v4 as uuid } from 'uuid'
import type { Card, Note } from '@/data/types'
import { parseCloze } from './cloze'
import { db } from '@/data/db'
import { repo } from '@/data/repo'

const blank = (noteId: string, ord: number): Card => ({
  id: uuid(), noteId, ord, due: Date.now(), stability: 0, difficulty: 0,
  reps: 0, lapses: 0, state: 0, lastReview: null, suspended: 0, deletedAt: null, learningSteps: 0,
})

export function cardsForNote(note: Note): Card[] {
  if (note.type === 'basic') return [blank(note.id, 0)]
  if (note.type === 'basic_reversed') return [blank(note.id, 0), blank(note.id, 1)]
  return parseCloze(note.fields.term).map(c => blank(note.id, c.ord))
}

function wantedOrdinals(note: Note): number[] {
  if (note.type === 'basic') return [0]
  if (note.type === 'basic_reversed') return [0, 1]
  return parseCloze(note.fields.term).map(c => c.ord)
}

// Resurrects a previously soft-deleted card at the same id/ordinal, but with fresh FSRS state:
// the card left the schedule while deleted, so its old progress is no longer meaningful. Reusing
// the id (rather than minting a new one) keeps a round trip like basic -> reversed -> basic ->
// reversed from accumulating dead duplicate rows for the same ordinal.
const resurrect = (card: Card): Card => ({ ...blank(card.noteId, card.ord), id: card.id })

/**
 * Reconcile the cards table with a note's current content after an edit.
 * - Missing ordinals (new cloze ordinal, or basic->basic_reversed) get a new blank card, unless a
 *   soft-deleted card already exists for that ordinal, in which case it's resurrected (fresh FSRS
 *   state, same id) instead of minting a duplicate.
 * - Ordinals no longer present (removed cloze ordinal, or basic_reversed->basic) get soft-deleted.
 * - Existing live cards for ordinals still present are left untouched (FSRS state preserved).
 * - A brand-new note with no cards yet gets the full set via cardsForNote.
 */
export async function syncCardsWithNote(note: Note): Promise<void> {
  const existing = await db.cards.where('noteId').equals(note.id).toArray()
  const wanted = new Set(wantedOrdinals(note))

  if (existing.length === 0) {
    for (const card of cardsForNote(note)) await repo.put('cards', card)
    return
  }

  const liveByOrd = new Map<number, Card>()
  const deletedByOrd = new Map<number, Card>()
  for (const card of existing) {
    if (card.deletedAt == null) liveByOrd.set(card.ord, card)
    else if (!deletedByOrd.has(card.ord)) deletedByOrd.set(card.ord, card)
  }

  for (const ord of wanted) {
    if (liveByOrd.has(ord)) continue
    const dead = deletedByOrd.get(ord)
    await repo.put('cards', dead ? resurrect(dead) : blank(note.id, ord))
  }

  for (const [ord, card] of liveByOrd) {
    if (!wanted.has(ord)) await repo.softDelete('cards', card.id)
  }
}
