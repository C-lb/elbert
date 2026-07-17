import 'fake-indexeddb/auto'
import { describe, it, expect, beforeEach } from 'vitest'
import { db } from '@/data/db'
import { buildQueue, noteNewIntroduced } from './queue'

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
