import 'fake-indexeddb/auto'
import { describe, it, expect, beforeEach, vi } from 'vitest'
import { db } from '@/data/db'
import { repo } from '@/data/repo'
import { saveSettings } from '@/lib/settings'
import { sync } from './client'

beforeEach(async () => {
  await Promise.all(db.tables.map(t => t.clear()))
  await saveSettings({ syncKey: 'test-key' })
  vi.unstubAllGlobals()
})

function emptyPullResponse(cursor = 5) {
  return {
    pulled: [
      { table: 'decks', rows: [] },
      { table: 'notes', rows: [] },
      { table: 'cards', rows: [] },
      { table: 'reviews', rows: [] },
      { table: 'media', rows: [] },
    ],
    cursor,
  }
}

describe('sync()', () => {
  it('returns { error } when no sync key is set', async () => {
    await saveSettings({ syncKey: '' })
    const result = await sync()
    expect(result).toEqual({ error: 'no key' })
  })

  it('pushes dirty rows snake_cased and clears dirty flags on success', async () => {
    await repo.put('decks', {
      id: 'd1', name: 'Spanish', parentId: null, newPerDay: 15, desiredRetention: 0.9, deletedAt: null,
    })

    let capturedBody: any = null
    vi.stubGlobal('fetch', vi.fn(async (_url: string, init: RequestInit) => {
      capturedBody = JSON.parse(init.body as string)
      return {
        ok: true,
        status: 200,
        json: async () => emptyPullResponse(7),
      }
    }))

    const result = await sync()

    expect(result).toEqual({ pushed: 1, pulled: 0 })
    expect(capturedBody.push).toEqual([
      {
        table: 'decks',
        rows: [
          expect.objectContaining({
            id: 'd1',
            name: 'Spanish',
            parent_id: null,
            new_per_day: 15,
            desired_retention: 0.9,
            deleted_at: null,
          }),
        ],
      },
    ])

    const row = await db.decks.get('d1')
    expect(row!.dirty).toBe(0)
    expect(await repo.getMeta('syncCursor')).toBe(7)
  })

  it('leaves a row edited mid-sync dirty even though the sync that pushed it succeeded', async () => {
    // Two stamps in the same millisecond would be indistinguishable to the snapshot check,
    // so force distinct clock values: first put uses t0, the mid-sync put uses t0+1000.
    let now = 1_000_000
    const nowSpy = vi.spyOn(Date, 'now').mockImplementation(() => now)

    await repo.put('decks', {
      id: 'd1', name: 'Spanish', parentId: null, newPerDay: 15, desiredRetention: 0.9, deletedAt: null,
    })

    vi.stubGlobal('fetch', vi.fn(async () => {
      // Simulate a concurrent edit landing after the snapshot was taken but before the response arrives.
      now += 1000
      await repo.put('decks', {
        id: 'd1', name: 'Spanish (edited)', parentId: null, newPerDay: 15, desiredRetention: 0.9, deletedAt: null,
      })
      return { ok: true, status: 200, json: async () => emptyPullResponse(7) }
    }))

    const result = await sync()

    expect(result).toEqual({ pushed: 0, pulled: 0 })
    const row = await db.decks.get('d1')
    expect(row!.dirty).toBe(1)
    expect(row!.name).toBe('Spanish (edited)')

    nowSpy.mockRestore()
  })

  it('applies pulled rows snake_case -> camelCase with Numbered bigints, and stores the cursor', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => ({
      ok: true,
      status: 200,
      json: async () => ({
        pulled: [
          {
            table: 'cards',
            rows: [{
              id: 'c1', updated_at: '1000', deleted_at: null,
              note_id: 'n1', ord: 0, due: '123456789012', stability: 2.5, difficulty: 5,
              reps: 1, lapses: 0, state: 1, last_review: '999999999999', suspended: 0,
              learning_steps: 0,
            }],
          },
          { table: 'decks', rows: [] },
          { table: 'notes', rows: [] },
          { table: 'reviews', rows: [] },
          { table: 'media', rows: [] },
        ],
        cursor: 42,
      }),
    })))

    const result = await sync()

    expect(result).toEqual({ pushed: 0, pulled: 1 })
    const card = await db.cards.get('c1')
    expect(card).toBeTruthy()
    expect(card!.due).toBe(123456789012)
    expect(typeof card!.due).toBe('number')
    expect(card!.lastReview).toBe(999999999999)
    expect(card!.updatedAt).toBe(1000)
    expect(card!.dirty).toBe(0)
    expect(await repo.getMeta('syncCursor')).toBe(42)
  })

  it('a fetch rejection returns { error } and leaves dirty rows / cursor untouched', async () => {
    await repo.put('decks', {
      id: 'd1', name: 'Spanish', parentId: null, newPerDay: 15, desiredRetention: 0.9, deletedAt: null,
    })
    await repo.setMeta('syncCursor', 3)

    vi.stubGlobal('fetch', vi.fn(async () => {
      throw new Error('offline')
    }))

    const result = await sync()

    expect(result).toEqual({ error: 'network error' })
    const row = await db.decks.get('d1')
    expect(row!.dirty).toBe(1)
    expect(await repo.getMeta('syncCursor')).toBe(3)
  })

  it('skips a pulled row older than the local copy', async () => {
    await repo.put('decks', {
      id: 'd1', name: 'Local newer', parentId: null, newPerDay: 15, desiredRetention: 0.9, deletedAt: null,
    })
    const local = await db.decks.get('d1')
    await repo.clearDirty('decks', ['d1'])

    vi.stubGlobal('fetch', vi.fn(async () => ({
      ok: true,
      status: 200,
      json: async () => ({
        pulled: [
          {
            table: 'decks',
            rows: [{
              id: 'd1', updated_at: String(local!.updatedAt! - 1000), deleted_at: null,
              name: 'Stale remote', parent_id: null, new_per_day: 15, desired_retention: 0.9,
            }],
          },
          { table: 'notes', rows: [] },
          { table: 'cards', rows: [] },
          { table: 'reviews', rows: [] },
          { table: 'media', rows: [] },
        ],
        cursor: 9,
      }),
    })))

    const result = await sync()

    expect(result).toEqual({ pushed: 0, pulled: 0 })
    const row = await db.decks.get('d1')
    expect(row!.name).toBe('Local newer')
  })

  it('a 400 response returns { error } and clears nothing', async () => {
    await repo.put('decks', {
      id: 'd1', name: 'Spanish', parentId: null, newPerDay: 15, desiredRetention: 0.9, deletedAt: null,
    })
    await repo.setMeta('syncCursor', 3)

    vi.stubGlobal('fetch', vi.fn(async () => ({
      ok: false,
      status: 400,
      json: async () => ({ error: 'invalid row for table "decks"', table: 'decks', id: 'd1' }),
    })))

    const result = await sync()

    expect(result).toEqual({ error: 'invalid row for table "decks"' })
    const row = await db.decks.get('d1')
    expect(row!.dirty).toBe(1)
    expect(await repo.getMeta('syncCursor')).toBe(3)
  })
})
