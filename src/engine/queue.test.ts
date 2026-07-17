import 'fake-indexeddb/auto'
import { describe, it, expect, beforeEach } from 'vitest'
import { db } from '@/data/db'
import { buildQueue, dayKey, dueCounts, dueCountsAll, noteNewIntroduced } from './queue'

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

describe('dayKey', () => {
  const localKey = (d: Date) =>
    `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`

  it('is built from local date components, zero-padded', () => {
    expect(dayKey(new Date(2026, 0, 5, 12, 0))).toBe('2026-01-05')
    expect(dayKey(new Date(2026, 8, 9, 12, 0))).toBe('2026-09-09')
  })

  it('rolls over at local midnight, not UTC midnight', () => {
    const beforeMidnight = new Date(2026, 5, 30, 23, 59, 59)
    const afterMidnight = new Date(2026, 6, 1, 0, 0, 1)
    expect(dayKey(beforeMidnight)).toBe('2026-06-30')
    expect(dayKey(afterMidnight)).toBe('2026-07-01')
    // regardless of what the UTC date happens to be at those instants
    expect(dayKey(beforeMidnight)).toBe(localKey(beforeMidnight))
    expect(dayKey(afterMidnight)).toBe(localKey(afterMidnight))
  })

  it('defaults to the current local date', () => {
    const before = localKey(new Date())
    const key = dayKey()
    const after = localKey(new Date())
    expect([before, after]).toContain(key)
  })
})

describe('dueCountsAll', () => {
  beforeEach(async () => {
    await db.decks.bulkAdd([
      { id: 'd2', name: 'y', parentId: null, newPerDay: 1, desiredRetention: 0.9, deletedAt: null },
      { id: 'd3', name: 'z', parentId: null, newPerDay: 5, desiredRetention: 0.9, deletedAt: Date.now() },
    ] as any)
    await db.notes.bulkAdd([
      ...['h', 'i', 'j'].map(id => ({ id, deckId: 'd2', type: 'basic', fields: { term: 't', definition: 'd' }, tags: [], deletedAt: null })),
      ...['k', 'l'].map(id => ({ id, deckId: 'd3', type: 'basic', fields: { term: 't', definition: 'd' }, tags: [], deletedAt: null })),
    ] as any)
    await db.cards.bulkAdd([
      card('h'),
      card('i', { state: 0 }),
      card('j', { state: 0, suspended: 1 }),
      card('k'),
      card('l', { state: 0 }),
    ])
    await noteNewIntroduced('d1', 2) // exhaust d1's new quota
  })

  it('counts every live deck in one pass, skipping deleted decks and suspended cards', async () => {
    const all = await dueCountsAll()
    expect([...all.keys()].sort()).toEqual(['d1', 'd2'])
    expect(all.get('d1')).toEqual({ due: 2, newAvailable: 0 }) // quota exhausted
    expect(all.get('d2')).toEqual({ due: 1, newAvailable: 1 }) // j suspended, cap 1
  })

  it('matches per-deck dueCounts for every deck, including deleted ones', async () => {
    const all = await dueCountsAll()
    for (const deckId of ['d1', 'd2']) {
      expect(all.get(deckId)).toEqual(await dueCounts(deckId))
    }
    expect(all.has('d3')).toBe(false)
    expect(await dueCounts('d3')).toEqual({ due: 0, newAvailable: 0 })
    expect(await dueCounts()).toEqual({ due: 3, newAvailable: 1 })
  })
})

describe('soft-deleted deck exclusion', () => {
  it('excludes cards whose deck is soft-deleted from the global queue and counts', async () => {
    await db.decks.update('d1', { deletedAt: Date.now() })
    expect(await buildQueue()).toHaveLength(0)
    expect(await dueCounts()).toEqual({ due: 0, newAvailable: 0 })
  })
})
