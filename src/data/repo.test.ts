import 'fake-indexeddb/auto'
import { describe, it, expect, beforeEach } from 'vitest'
import { db } from './db'
import { repo } from './repo'

beforeEach(async () => { await Promise.all(db.tables.map(t => t.clear())) })

describe('repo', () => {
  it('put stamps updatedAt and dirty', async () => {
    await repo.put('decks', { id: 'd1', name: 'Spanish', parentId: null, newPerDay: 15, desiredRetention: 0.9, deletedAt: null })
    const row = await db.decks.get('d1')
    expect(row!.dirty).toBe(1)
    expect(row!.updatedAt).toBeGreaterThan(0)
  })
  it('softDelete sets deletedAt, keeps row', async () => {
    await repo.put('decks', { id: 'd1', name: 'x', parentId: null, newPerDay: 15, desiredRetention: 0.9, deletedAt: null })
    await repo.softDelete('decks', 'd1')
    const row = await db.decks.get('d1')
    expect(row!.deletedAt).not.toBeNull()
  })
  it('addReview appends and repo exposes no review update', async () => {
    await repo.addReview({ id: 'r1', cardId: 'c1', ts: 1, rating: 3, elapsedMs: 900, snapshot: {}, deletedAt: null })
    expect(await db.reviews.count()).toBe(1)
    expect((repo as any).updateReview).toBeUndefined()
  })
  it('dirtyRows / clearDirty round-trip', async () => {
    await repo.put('decks', { id: 'd1', name: 'x', parentId: null, newPerDay: 15, desiredRetention: 0.9, deletedAt: null })
    const dirty = await repo.dirtyRows()
    expect(dirty.find(d => d.table === 'decks')!.rows).toHaveLength(1)
    await repo.clearDirty('decks', ['d1'])
    expect((await repo.dirtyRows()).find(d => d.table === 'decks')?.rows ?? []).toHaveLength(0)
  })
})
