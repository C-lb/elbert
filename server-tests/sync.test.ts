// Integration tests against a real Postgres. Only run when PG_TEST_URL is
// set (colima docker container, see task brief); plain `npm test` skips
// this whole file and stays green.
import { describe, it, expect, beforeAll, beforeEach } from 'vitest'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { Client } from 'pg'
import handler, { type SyncRequest, type SyncResponse } from '../api/sync.ts'
import { resetDbCache } from '../api/_lib/pg.ts'

const PG_TEST_URL = process.env.PG_TEST_URL

const SCHEMA_PATH = fileURLToPath(new URL('../db/schema.sql', import.meta.url))
const ELBERT_KEY = 'test-key-123'

// `key: null` means "send no auth header at all" — distinct from omitting
// the argument (which defaults to a valid key). Passing `undefined`
// explicitly would NOT work here since JS default params trigger on it too.
function makeReq(body: unknown, key: string | null = ELBERT_KEY): SyncRequest {
  return {
    method: 'POST',
    headers: key === null ? {} : { 'x-elbert-key': key },
    body,
  }
}

function makeRes(): SyncResponse & { statusCode: number; body: unknown } {
  const res = {
    statusCode: 200,
    body: undefined as unknown,
    status(code: number) {
      res.statusCode = code
      return res
    },
    json(b: unknown) {
      res.body = b
    },
  }
  return res
}

async function call(body: unknown, key?: string | null) {
  const res = makeRes()
  await handler(makeReq(body, key), res)
  return res
}

describe.skipIf(!PG_TEST_URL)('POST /api/sync', () => {
  beforeAll(async () => {
    process.env.ELBERT_KEY = ELBERT_KEY
    process.env.PG_TEST_URL = PG_TEST_URL
    resetDbCache()

    const admin = new Client({ connectionString: PG_TEST_URL })
    await admin.connect()
    try {
      await admin.query(readFileSync(SCHEMA_PATH, 'utf8'))
    } finally {
      await admin.end()
    }
  })

  beforeEach(async () => {
    const admin = new Client({ connectionString: PG_TEST_URL })
    await admin.connect()
    try {
      await admin.query('TRUNCATE decks, notes, cards, reviews, media')
      await admin.query('ALTER SEQUENCE sync_seq RESTART WITH 1')
    } finally {
      await admin.end()
    }
  })

  it('401s without a valid key', async () => {
    const res = await call({ push: [], cursor: 0 }, null)
    expect(res.statusCode).toBe(401)

    const wrongKey = await call({ push: [], cursor: 0 }, 'wrong-key')
    expect(wrongKey.statusCode).toBe(401)
  })

  it('pushes a deck and pulls it back from cursor 0', async () => {
    const deck = {
      id: 'deck-1',
      updated_at: 1000,
      deleted_at: null,
      name: 'Spanish',
      parent_id: null,
      new_per_day: 20,
      desired_retention: 0.9,
    }
    const res = await call({ push: [{ table: 'decks', rows: [deck] }], cursor: 0 })
    expect(res.statusCode).toBe(200)

    const body = res.body as { pulled: { table: string; rows: unknown[] }[]; cursor: number }
    const decksPulled = body.pulled.find((p) => p.table === 'decks')!.rows as Record<string, unknown>[]
    expect(decksPulled).toHaveLength(1)
    expect(decksPulled[0]).toMatchObject({ id: 'deck-1', name: 'Spanish', new_per_day: 20 })
    expect(body.cursor).toBeGreaterThan(0)
  })

  it('does not overwrite on a stale updated_at push', async () => {
    await call({
      push: [{
        table: 'decks',
        rows: [{ id: 'deck-2', updated_at: 2000, deleted_at: null, name: 'Fresh', parent_id: null, new_per_day: 10, desired_retention: 0.9 }],
      }],
      cursor: 0,
    })

    const stale = await call({
      push: [{
        table: 'decks',
        rows: [{ id: 'deck-2', updated_at: 1000, deleted_at: null, name: 'Stale', parent_id: null, new_per_day: 5, desired_retention: 0.8 }],
      }],
      cursor: 0,
    })

    const body = stale.body as { pulled: { table: string; rows: unknown[] }[] }
    const decksPulled = body.pulled.find((p) => p.table === 'decks')!.rows as Record<string, unknown>[]
    expect(decksPulled).toHaveLength(1)
    expect(decksPulled[0]).toMatchObject({ name: 'Fresh', new_per_day: 10 })
  })

  it('ignores a duplicate review id (insert-only)', async () => {
    const first = await call({
      push: [{
        table: 'reviews',
        rows: [{ id: 'rev-1', updated_at: 1000, deleted_at: null, card_id: 'card-1', ts: 1000, rating: 3, elapsed_ms: 1500, snapshot: { due: 1234 } }],
      }],
      cursor: 0,
    })
    expect(first.statusCode).toBe(200)

    const second = await call({
      push: [{
        table: 'reviews',
        rows: [{ id: 'rev-1', updated_at: 9999, deleted_at: null, card_id: 'card-1', ts: 9999, rating: 1, elapsed_ms: 500, snapshot: { due: 9999 } }],
      }],
      cursor: 0,
    })

    const body = second.body as { pulled: { table: string; rows: unknown[] }[] }
    const reviewsPulled = body.pulled.find((p) => p.table === 'reviews')!.rows as Record<string, unknown>[]
    expect(reviewsPulled).toHaveLength(1)
    expect(reviewsPulled[0]).toMatchObject({ rating: 3, elapsed_ms: '1500' })
  })

  it('advances the cursor monotonically; a re-pull from the new cursor returns nothing', async () => {
    const first = await call({
      push: [{
        table: 'decks',
        rows: [{ id: 'deck-3', updated_at: 1000, deleted_at: null, name: 'Cursor Test', parent_id: null, new_per_day: 15, desired_retention: 0.9 }],
      }],
      cursor: 0,
    })
    const firstBody = first.body as { cursor: number }
    expect(firstBody.cursor).toBeGreaterThan(0)

    const second = await call({ push: [], cursor: firstBody.cursor })
    const secondBody = second.body as { pulled: { table: string; rows: unknown[] }[]; cursor: number }
    for (const entry of secondBody.pulled) {
      expect(entry.rows).toHaveLength(0)
    }
    expect(secondBody.cursor).toBe(firstBody.cursor)
  })
})
