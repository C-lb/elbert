import 'fake-indexeddb/auto'
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { db } from '@/data/db'
import { repo, setMutationListener } from '@/data/repo'
import { saveSettings } from '@/lib/settings'
import { sync } from './client'
import { scheduleSync } from './status'

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

  it('does not call fetch when no sync key is set', async () => {
    await saveSettings({ syncKey: '' })
    const fetchSpy = vi.fn()
    vi.stubGlobal('fetch', fetchSpy)

    await sync()

    expect(fetchSpy).not.toHaveBeenCalled()
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

  it('never throws when applying a pulled row fails (e.g. IndexedDB quota) — returns { error }, dirty rows stay intact', async () => {
    // A dirty row on a DIFFERENT table than the one that fails during apply: the whole
    // clear-dirty/apply/cursor sequence runs in one transaction, so if applying the pulled
    // decks row blows up, this note's dirty flag must roll back to still being set.
    await repo.put('notes', {
      id: 'n1', deckId: 'd1', type: 'basic',
      fields: { term: 'hola', definition: 'hello' }, tags: [], deletedAt: null,
    })
    await repo.setMeta('syncCursor', 1)

    vi.stubGlobal('fetch', vi.fn(async () => ({
      ok: true,
      status: 200,
      json: async () => ({
        pulled: [
          {
            table: 'decks',
            rows: [{
              id: 'd1', updated_at: '5000', deleted_at: null,
              name: 'Spanish', parent_id: null, new_per_day: 15, desired_retention: 0.9,
            }],
          },
          { table: 'notes', rows: [] },
          { table: 'cards', rows: [] },
          { table: 'reviews', rows: [] },
          { table: 'media', rows: [] },
        ],
        cursor: 99,
      }),
    })))

    const bulkPutSpy = vi.spyOn(db.decks, 'bulkPut').mockRejectedValue(new Error('quota exceeded'))

    const result = await sync()

    expect(result).toHaveProperty('error')

    const note = await db.notes.get('n1')
    expect(note!.dirty).toBe(1)
    expect(await repo.getMeta('syncCursor')).toBe(1)

    bulkPutSpy.mockRestore()
  })

  it('round-trips media through sync(): blob -> base64 on push, base64 -> blob on pull', async () => {
    const content = 'hello world'
    const blob = new Blob([content], { type: 'text/plain' })
    await repo.put('media', { id: 'm1', hash: 'h1', mime: 'text/plain', blob, deletedAt: null })

    let capturedBody: any = null
    const wireBase64 = btoa(content)

    vi.stubGlobal('fetch', vi.fn(async (_url: string, init: RequestInit) => {
      capturedBody = JSON.parse(init.body as string)
      return {
        ok: true,
        status: 200,
        json: async () => ({
          pulled: [
            { table: 'decks', rows: [] },
            { table: 'notes', rows: [] },
            { table: 'cards', rows: [] },
            { table: 'reviews', rows: [] },
            {
              table: 'media',
              rows: [{
                id: 'm1', updated_at: '9999999999999', deleted_at: null,
                hash: 'h1', mime: 'text/plain', data_base64: wireBase64,
              }],
            },
          ],
          cursor: 11,
        }),
      }
    }))

    const result = await sync()

    expect(result).toEqual({ pushed: 1, pulled: 1 })

    // push side: the blob went out as base64
    const pushedRow = capturedBody.push.find((p: any) => p.table === 'media').rows[0]
    expect(pushedRow.data_base64).toBe(wireBase64)

    // pull side: the base64 came back in as a Blob with the original content
    const stored = await db.media.get('m1')
    expect(stored!.blob).toBeInstanceOf(Blob)
    expect(await stored!.blob!.text()).toBe(content)
    expect(stored!.dirty).toBe(0)
  })
})

describe('mutation-triggered debounced sync', () => {
  afterEach(() => {
    setMutationListener(null)
    vi.clearAllTimers()
    vi.useRealTimers()
  })

  it('a burst of repo mutations coalesces into a single push after the debounce window', async () => {
    const fetchSpy = vi.fn(async () => ({ ok: true, status: 200, json: async () => emptyPullResponse() }))
    vi.stubGlobal('fetch', fetchSpy)

    // Only fake the timer APIs the debounce uses — fake-indexeddb must keep its own scheduling.
    vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] })
    setMutationListener(scheduleSync)

    await repo.put('decks', {
      id: 'd1', name: 'One', parentId: null, newPerDay: 15, desiredRetention: 0.9, deletedAt: null,
    })
    await vi.advanceTimersByTimeAsync(2000)
    await repo.put('decks', {
      id: 'd2', name: 'Two', parentId: null, newPerDay: 15, desiredRetention: 0.9, deletedAt: null,
    })
    await repo.put('decks', {
      id: 'd3', name: 'Three', parentId: null, newPerDay: 15, desiredRetention: 0.9, deletedAt: null,
    })

    // 2s after the first mutation, 0s after the last: trailing debounce, nothing fired yet.
    expect(fetchSpy).not.toHaveBeenCalled()

    await vi.advanceTimersByTimeAsync(4000)
    vi.useRealTimers()
    await vi.waitFor(() => expect(fetchSpy).toHaveBeenCalledTimes(1))

    const body = JSON.parse((fetchSpy.mock.calls[0] as any)[1].body)
    expect(body.push).toHaveLength(1)
    expect(body.push[0].table).toBe('decks')
    expect(body.push[0].rows.map((r: any) => r.id).sort()).toEqual(['d1', 'd2', 'd3'])

    await vi.waitFor(async () => {
      const rows = await db.decks.toArray()
      expect(rows.every(r => r.dirty === 0)).toBe(true)
    })
  })

  it('mutation-scheduled sync with no key configured stays a silent no-op', async () => {
    await saveSettings({ syncKey: '' })
    const fetchSpy = vi.fn()
    vi.stubGlobal('fetch', fetchSpy)

    vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] })
    setMutationListener(scheduleSync)

    await repo.put('decks', {
      id: 'd1', name: 'One', parentId: null, newPerDay: 15, desiredRetention: 0.9, deletedAt: null,
    })
    await vi.advanceTimersByTimeAsync(5000)
    vi.useRealTimers()
    await new Promise(r => setTimeout(r, 25))

    expect(fetchSpy).not.toHaveBeenCalled()
    const row = await db.decks.get('d1')
    expect(row!.dirty).toBe(1)
  })
})

describe('payload batching', () => {
  it('splits an over-budget push into sequential requests, chaining each response cursor into the next', async () => {
    // Two ~1.8MB blobs -> ~2.4MB of base64 each: together over the 3.5MB budget, so two requests.
    const makeBlob = (fill: number) =>
      new Blob([new Uint8Array(1_800_000).fill(fill)], { type: 'application/octet-stream' })
    await repo.put('media', { id: 'm1', hash: 'h1', mime: 'application/octet-stream', blob: makeBlob(1), deletedAt: null })
    await repo.put('media', { id: 'm2', hash: 'h2', mime: 'application/octet-stream', blob: makeBlob(2), deletedAt: null })

    const bodies: any[] = []
    vi.stubGlobal('fetch', vi.fn(async (_url: string, init: RequestInit) => {
      bodies.push(JSON.parse(init.body as string))
      return {
        ok: true,
        status: 200,
        json: async () => emptyPullResponse(bodies.length === 1 ? 10 : 20),
      }
    }))

    const result = await sync()

    expect(result).toEqual({ pushed: 2, pulled: 0 })
    expect(bodies).toHaveLength(2)

    // Each request stays under the budget (allow slack for the {push, cursor} envelope).
    for (const body of bodies) {
      expect(JSON.stringify(body).length).toBeLessThan(3_600_000)
    }

    // Both rows went out exactly once, split across the two requests.
    const pushedIds = bodies.flatMap(b => b.push.flatMap((p: any) => p.rows.map((r: any) => r.id)))
    expect(pushedIds.sort()).toEqual(['m1', 'm2'])

    // Cursor chaining: first request uses the stored cursor, second uses the first response's.
    expect(bodies[0].cursor).toBe(0)
    expect(bodies[1].cursor).toBe(10)
    expect(await repo.getMeta('syncCursor')).toBe(20)

    const m1 = await db.media.get('m1')
    const m2 = await db.media.get('m2')
    expect(m1!.dirty).toBe(0)
    expect(m2!.dirty).toBe(0)
  })

  it('skips a single row whose own payload exceeds the limit, pushes the rest, and leaves it dirty', async () => {
    // ~3MB blob -> ~4MB base64: alone over the 3.5MB budget.
    const huge = new Blob([new Uint8Array(3_000_000)], { type: 'application/octet-stream' })
    await repo.put('media', { id: 'mBig', hash: 'hb', mime: 'application/octet-stream', blob: huge, deletedAt: null })
    await repo.put('decks', {
      id: 'd1', name: 'Spanish', parentId: null, newPerDay: 15, desiredRetention: 0.9, deletedAt: null,
    })

    const warnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {})
    const bodies: any[] = []
    vi.stubGlobal('fetch', vi.fn(async (_url: string, init: RequestInit) => {
      bodies.push(JSON.parse(init.body as string))
      return { ok: true, status: 200, json: async () => emptyPullResponse(7) }
    }))

    const result = await sync()

    expect(result).toEqual({ pushed: 1, pulled: 0, skipped: 1 })
    expect(bodies).toHaveLength(1)
    const pushedIds = bodies[0].push.flatMap((p: any) => p.rows.map((r: any) => r.id))
    expect(pushedIds).toEqual(['d1'])
    expect(warnSpy).toHaveBeenCalledOnce()
    expect(String(warnSpy.mock.calls[0][0])).toContain('mBig')

    // The oversized row stays dirty (visible as pending in the sync badge); everything else cleared.
    expect((await db.media.get('mBig'))!.dirty).toBe(1)
    expect((await db.decks.get('d1'))!.dirty).toBe(0)
    expect(await repo.getMeta('syncCursor')).toBe(7)

    warnSpy.mockRestore()
  })

  it('a failed later batch keeps its rows dirty while earlier committed batches stay cleared', async () => {
    const makeBlob = (fill: number) =>
      new Blob([new Uint8Array(1_800_000).fill(fill)], { type: 'application/octet-stream' })
    await repo.put('media', { id: 'm1', hash: 'h1', mime: 'application/octet-stream', blob: makeBlob(1), deletedAt: null })
    await repo.put('media', { id: 'm2', hash: 'h2', mime: 'application/octet-stream', blob: makeBlob(2), deletedAt: null })

    let call = 0
    vi.stubGlobal('fetch', vi.fn(async () => {
      call++
      if (call === 1) return { ok: true, status: 200, json: async () => emptyPullResponse(10) }
      throw new Error('offline')
    }))

    const result = await sync()

    expect(result).toEqual({ error: 'network error' })
    // Batch 1 committed: its row is on the server, dirty cleared, cursor advanced.
    expect((await db.media.get('m1'))!.dirty).toBe(0)
    expect(await repo.getMeta('syncCursor')).toBe(10)
    // Batch 2 failed: its row stays dirty for the next sync.
    expect((await db.media.get('m2'))!.dirty).toBe(1)
  })
})
