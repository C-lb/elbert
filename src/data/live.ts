import { db } from './db'
import type { Note } from './types'

/**
 * Notes that are actually alive: not soft-deleted, and belonging to a deck
 * that exists and is not soft-deleted. Mirrors the exclusion semantics of
 * the study queue builder (engine/queue.ts eligibleCards/liveDecks).
 */
export async function liveNotes(deckId?: string): Promise<Note[]> {
  const liveDeckIds = new Set((await db.decks.filter(d => d.deletedAt == null).toArray()).map(d => d.id))
  return db.notes
    .filter(n => n.deletedAt == null && (!deckId || n.deckId === deckId) && liveDeckIds.has(n.deckId))
    .toArray()
}
