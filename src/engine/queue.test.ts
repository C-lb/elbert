import 'fake-indexeddb/auto'
import { describe, it, expect, beforeEach } from 'vitest'
import { db } from '@/data/db'
import { buildQueue, dueCounts, noteNewIntroduced } from './queue'

const card = (id: string, over: any = {}): any => ({ id, noteId: id, ord: 0, due: Date.now() - 1000, stability: 1, difficulty: 5, reps: 1, lapses: 0, state: 2, lastReview: null, suspended: 0, deletedAt: null, ...over })
const note = (id: string): any => ({ id, deckId: 'd1', type: 'basic', fields: { term: 't', definition: 'd' }, tags: [], deletedAt: null })

beforeEach(async () => {
  await Promise.all(db.tables.map(t => t.clear()))
  await db.decks.add({ id: 'd1', name: 'x', parentId: null, newPerDay: 2, desiredRetention: 0.9, deletedAt: null } as any)
  await db.notes.bulkAdd(['a','b','c','d','e','f','g'].map(note))
  await db.cards.bulkAdd([
    card('a'), card('b'),
    card('c', { due: Date.now() + 86400000 }),
    card('d', { suspended: 1 }),
    card('e', { state: 0 }), card('f', { state: 0 }), card('g', { state: 0 }),
  ])
})

describe('buildQueue', () => {
  it('due + capped new, skips future/suspended', async () => {
    const q = await buildQueue('d1')
    expect(q.map(c => c.id).sort()).toEqual(['a', 'b', 'e', 'f'])
  })
  it('new counter reduces later sessions', async () => {
    await noteNewIntroduced('d1', 2)
    const q = await buildQueue('d1')
    expect(q.filter(c => c.state === 0)).toHaveLength(0)
  })
})

describe('dueCounts', () => {
  it('reports due count and newAvailable respecting the cap', async () => {
    expect(await dueCounts('d1')).toEqual({ due: 2, newAvailable: 2 })
    await noteNewIntroduced('d1', 1)
    expect(await dueCounts('d1')).toEqual({ due: 2, newAvailable: 1 })
  })
})

describe('buildQueue global path (no deckId)', () => {
  beforeEach(async () => {
    await db.decks.add({ id: 'd2', name: 'y', parentId: null, newPerDay: 1, desiredRetention: 0.9, deletedAt: null } as any)
    await db.notes.bulkAdd(['h', 'i', 'j'].map(id => ({ id, deckId: 'd2', type: 'basic', fields: { term: 't', definition: 'd' }, tags: [], deletedAt: null })))
    await db.cards.bulkAdd([
      card('h', { state: 1 }),
      card('i', { state: 0 }),
      card('j', { state: 0 }),
    ])
  })

  it('applies each deck\'s own new-card cap and orders learning -> review -> new', async () => {
    const q = await buildQueue()

    const learningIdx = q.findIndex(c => c.state === 1 || c.state === 3)
    const reviewIdx = q.findIndex(c => c.state === 2)
    const newIdx = q.findIndex(c => c.state === 0)
    expect(learningIdx).toBeLessThan(reviewIdx)
    expect(reviewIdx).toBeLessThan(newIdx)

    expect(q.filter(c => c.state === 1 || c.state === 3).map(c => c.id)).toEqual(['h'])
    expect(q.filter(c => c.state === 2).map(c => c.id).sort()).toEqual(['a', 'b'])

    const newIds = q.filter(c => c.state === 0).map(c => c.id)
    expect(newIds.filter(id => ['e', 'f', 'g'].includes(id))).toHaveLength(2) // d1 cap
    expect(newIds.filter(id => ['i', 'j'].includes(id))).toHaveLength(1) // d2 cap
    expect(newIds).toHaveLength(3)
  })
})

describe('soft-deleted deck exclusion', () => {
  it('excludes cards whose deck is soft-deleted from the global queue and counts', async () => {
    await db.decks.update('d1', { deletedAt: Date.now() })
    expect(await buildQueue()).toHaveLength(0)
    expect(await dueCounts()).toEqual({ due: 0, newAvailable: 0 })
  })
})
