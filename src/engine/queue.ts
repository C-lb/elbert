import { db } from '@/data/db'
import { repo } from '@/data/repo'
import type { Card, Deck } from '@/data/types'

export const dayKey = (d: Date = new Date()) =>
  `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
const counterKey = (deckId: string) => `newIntroduced:${deckId}:${dayKey()}`

async function deletedNoteIds(): Promise<Set<string>> {
  const notes = await db.notes.filter(n => n.deletedAt != null).toArray()
  return new Set(notes.map(n => n.id))
}

async function liveDecks(deckId?: string): Promise<Deck[]> {
  if (deckId) {
    const deck = await db.decks.get(deckId)
    return deck && deck.deletedAt == null ? [deck] : []
  }
  return db.decks.filter(d => d.deletedAt == null).toArray()
}

async function eligibleCards(deckId?: string): Promise<Card[]> {
  const deadNotes = await deletedNoteIds()
  const cards = await db.cards.toArray()
  const noteById = new Map((await db.notes.toArray()).map(n => [n.id, n]))
  const deadDecks = new Set((await db.decks.filter(d => d.deletedAt != null).toArray()).map(d => d.id))
  return cards.filter(c => {
    if (c.deletedAt != null) return false
    if (c.suspended === 1) return false
    if (deadNotes.has(c.noteId)) return false
    const note = noteById.get(c.noteId)
    if (!note) return false
    if (deadDecks.has(note.deckId)) return false
    if (deckId && note.deckId !== deckId) return false
    return true
  })
}

async function newAllowance(deckId: string): Promise<number> {
  const deck = await db.decks.get(deckId)
  if (!deck) return 0
  const introduced = (await repo.getMeta<number>(counterKey(deckId))) ?? 0
  return Math.max(0, deck.newPerDay - introduced)
}

export async function dueCountsAll(now = Date.now()): Promise<Map<string, { due: number; newAvailable: number }>> {
  const decks = await liveDecks()
  const cards = await eligibleCards()
  const noteById = new Map((await db.notes.toArray()).map(n => [n.id, n]))

  const counts = new Map<string, { due: number; newAvailable: number }>()
  const newInDeck = new Map<string, number>()
  for (const deck of decks) {
    counts.set(deck.id, { due: 0, newAvailable: 0 })
    newInDeck.set(deck.id, 0)
  }

  for (const c of cards) {
    const deckId = noteById.get(c.noteId)?.deckId
    if (deckId == null) continue
    const entry = counts.get(deckId)
    if (!entry) continue
    if (c.state === 0) newInDeck.set(deckId, (newInDeck.get(deckId) ?? 0) + 1)
    else if (c.due <= now) entry.due += 1
  }

  for (const deck of decks) {
    const introduced = (await repo.getMeta<number>(counterKey(deck.id))) ?? 0
    const allowance = Math.max(0, deck.newPerDay - introduced)
    counts.get(deck.id)!.newAvailable = Math.min(allowance, newInDeck.get(deck.id) ?? 0)
  }

  return counts
}

export async function dueCounts(deckId?: string): Promise<{ due: number; newAvailable: number }> {
  const all = await dueCountsAll()
  if (deckId) return all.get(deckId) ?? { due: 0, newAvailable: 0 }
  let due = 0
  let newAvailable = 0
  for (const entry of all.values()) {
    due += entry.due
    newAvailable += entry.newAvailable
  }
  return { due, newAvailable }
}

export async function buildQueue(deckId?: string): Promise<Card[]> {
  const now = Date.now()
  const cards = await eligibleCards(deckId)
  const decks = await liveDecks(deckId)
  const noteById = new Map((await db.notes.toArray()).map(n => [n.id, n]))

  const learning = cards.filter(c => (c.state === 1 || c.state === 3) && c.due <= now).sort((a, b) => a.due - b.due)
  const review = cards.filter(c => c.state === 2 && c.due <= now).sort((a, b) => a.due - b.due)

  const newCards: Card[] = []
  for (const deck of decks) {
    const allowance = await newAllowance(deck.id)
    if (allowance <= 0) continue
    const candidates = cards
      .filter(c => c.state === 0 && noteById.get(c.noteId)?.deckId === deck.id)
      .sort((a, b) => a.due - b.due)
      .slice(0, allowance)
    newCards.push(...candidates)
  }

  return [...learning, ...review, ...newCards]
}

export async function noteNewIntroduced(deckId: string, n: number): Promise<void> {
  const current = (await repo.getMeta<number>(counterKey(deckId))) ?? 0
  await repo.setMeta(counterKey(deckId), current + n)
}
