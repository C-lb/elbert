import { db } from '@/data/db'
import { repo } from '@/data/repo'
import type { Card, Deck } from '@/data/types'

const dayKey = () => new Date().toISOString().slice(0, 10)
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

export async function dueCounts(deckId?: string): Promise<{ due: number; newAvailable: number }> {
  const now = Date.now()
  const cards = await eligibleCards(deckId)
  const due = cards.filter(c => c.state !== 0 && c.due <= now).length

  const decks = await liveDecks(deckId)
  let newAvailable = 0
  const noteById = new Map((await db.notes.toArray()).map(n => [n.id, n]))
  for (const deck of decks) {
    const allowance = await newAllowance(deck.id)
    const newInDeck = cards.filter(c => c.state === 0 && noteById.get(c.noteId)?.deckId === deck.id).length
    newAvailable += Math.min(allowance, newInDeck)
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
