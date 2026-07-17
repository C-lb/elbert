// POST /api/sync — the client's IndexedDB replication target.
//
// Auth: header `x-elbert-key` must strictly equal env ELBERT_KEY, else 401
// (enforced by assertKey() in api/_lib/auth.ts).
//
// Wire contract:
//   Request  body: { push: [{ table, rows: [...] }], cursor: number }
//   Response body: { pulled: [{ table, rows: [...] }], cursor: number }
//
// `table` is one of decks | notes | cards | reviews | media. Rows on the
// wire are FLAT JSON IN SNAKE_CASE — the server never sees or produces
// camelCase. Mapping camelCase (client, src/data/types.ts) <-> snake_case
// (wire/DB) is entirely the Task 10 sync client's job; this endpoint just
// whitelists columns and passes values through.
//
// Row shapes (payload columns only — every table also carries the shared
// `id text`, `updated_at bigint`, `deleted_at bigint | null`; `seq` is
// server-assigned via the bump_seq() trigger and never accepted from a
// client push):
//
//   decks:   { name, parent_id, new_per_day, desired_retention }
//   notes:   { deck_id, type, fields, tags }              -- fields/tags are JSON
//   cards:   { note_id, ord, due, stability, difficulty, reps, lapses,
//              state, last_review, suspended, learning_steps }
//   reviews: { card_id, ts, rating, elapsed_ms, snapshot } -- snapshot is JSON;
//              insert-only, see below
//   media:   { hash, data_base64, mime }
//
// Push: for each row, upsert `ON CONFLICT (id) DO UPDATE ... WHERE
// <table>.updated_at < excluded.updated_at` (last-write-wins by updated_at).
// `reviews` is append-only: `ON CONFLICT (id) DO NOTHING`, no update path —
// a review is an immutable log entry, never edited after the fact.
//
// Pull: for every one of the 5 tables (not just the ones pushed to), select
// all rows with `seq > cursor`. The response cursor is read AFTER the pull
// selects, all inside the same transaction, so a client that stores the
// returned cursor and pulls again is guaranteed to see nothing new until
// another push lands.
//
// Concurrency (deviation from the original "SELECT last_value FROM
// sync_seq" plan text, controller-approved): `last_value` on a sequence is
// NOT transactional — it's a global counter mutated outside MVCC snapshot
// isolation. A pull racing a concurrent, not-yet-committed push could read
// a `last_value` past rows that commit a moment later, permanently skipping
// them for that client. Fixed by making `SELECT pg_advisory_xact_lock(42)`
// the FIRST query of every sync transaction (both driver paths — it's just
// another statement in the batch): it serializes all sync requests against
// each other, held until COMMIT, so no push can commit while another
// request's pull is still running. Also: `last_value` is defined even
// before a sequence's first `nextval()`, so on a virgin schema (no rows
// ever synced) a naive `SELECT last_value` returns 1, not 0 — which would
// skip the very first row (seq=1). Guarded with
// `SELECT CASE WHEN is_called THEN last_value ELSE 0 END`.
//
// Table/column names below are a fixed whitelist — never interpolate a
// client-supplied identifier into SQL.
import { assertKey, UnauthorizedError } from './_lib/auth.ts'
import { getDb, type QueryDesc } from './_lib/pg.ts'

export const SYNCED_TABLES = ['decks', 'notes', 'cards', 'reviews', 'media'] as const
export type SyncedTable = (typeof SYNCED_TABLES)[number]

interface TableConfig {
  columns: string[]
  jsonbColumns: Set<string>
  insertOnly: boolean
}

const TABLES: Record<SyncedTable, TableConfig> = {
  decks: {
    columns: ['name', 'parent_id', 'new_per_day', 'desired_retention'],
    jsonbColumns: new Set(),
    insertOnly: false,
  },
  notes: {
    columns: ['deck_id', 'type', 'fields', 'tags'],
    jsonbColumns: new Set(['fields', 'tags']),
    insertOnly: false,
  },
  cards: {
    columns: [
      'note_id', 'ord', 'due', 'stability', 'difficulty', 'reps', 'lapses',
      'state', 'last_review', 'suspended', 'learning_steps',
    ],
    jsonbColumns: new Set(),
    insertOnly: false,
  },
  reviews: {
    columns: ['card_id', 'ts', 'rating', 'elapsed_ms', 'snapshot'],
    jsonbColumns: new Set(['snapshot']),
    insertOnly: true,
  },
  media: {
    columns: ['hash', 'data_base64', 'mime'],
    jsonbColumns: new Set(),
    insertOnly: false,
  },
}

function isSyncedTable(table: unknown): table is SyncedTable {
  return typeof table === 'string' && (SYNCED_TABLES as readonly string[]).includes(table)
}

const REQUIRED_COLUMNS = ['id', 'updated_at'] as const

export class InvalidRowError extends Error {
  statusCode = 400
  table: string
  id: unknown
  missing: string[]
  constructor(table: string, id: unknown, missing: string[]) {
    super(`invalid row for table "${table}": missing ${missing.join(', ')}`)
    this.table = table
    this.id = id
    this.missing = missing
  }
}

/** Every required column (shared + per-table payload) must be present and non-undefined. */
function validateRow(table: SyncedTable, row: Record<string, unknown>): void {
  const cfg = TABLES[table]
  const required = [...REQUIRED_COLUMNS, ...cfg.columns]
  const missing = required.filter((col) => row[col] === undefined)
  if (missing.length > 0) {
    throw new InvalidRowError(table, row.id, missing)
  }
}

function buildUpsert(table: SyncedTable, row: Record<string, unknown>): QueryDesc {
  const cfg = TABLES[table]
  const allCols = ['id', 'updated_at', 'deleted_at', ...cfg.columns]
  const params = allCols.map((col) => {
    const value = row[col]
    if (value !== undefined && value !== null && cfg.jsonbColumns.has(col)) {
      return JSON.stringify(value)
    }
    return value ?? null
  })
  const placeholders = allCols.map((_, i) => `$${i + 1}`).join(', ')

  if (cfg.insertOnly) {
    return {
      text: `INSERT INTO ${table} (${allCols.join(', ')}) VALUES (${placeholders}) ON CONFLICT (id) DO NOTHING`,
      params,
    }
  }

  const setClause = allCols
    .filter((c) => c !== 'id')
    .map((c) => `${c} = excluded.${c}`)
    .join(', ')
  return {
    text: `INSERT INTO ${table} (${allCols.join(', ')}) VALUES (${placeholders}) ON CONFLICT (id) DO UPDATE SET ${setClause} WHERE ${table}.updated_at < excluded.updated_at`,
    params,
  }
}

interface PushEntry {
  table: string
  rows: Record<string, unknown>[]
}

interface SyncRequestBody {
  push?: PushEntry[]
  cursor?: number
}

export interface SyncRequest {
  method?: string
  headers: Record<string, string | string[] | undefined>
  body: unknown
}

export interface SyncResponse {
  status(code: number): SyncResponse
  json(body: unknown): void
}

export default async function handler(req: SyncRequest, res: SyncResponse): Promise<void> {
  try {
    assertKey(req)
  } catch (err) {
    if (err instanceof UnauthorizedError) {
      res.status(401).json({ error: 'unauthorized' })
      return
    }
    throw err
  }

  if (req.method && req.method !== 'POST') {
    res.status(405).json({ error: 'method not allowed' })
    return
  }

  let body: SyncRequestBody
  try {
    body = (typeof req.body === 'string' ? JSON.parse(req.body) : req.body) as SyncRequestBody
  } catch {
    res.status(400).json({ error: 'malformed JSON body' })
    return
  }

  const push = Array.isArray(body?.push) ? body.push : []
  const cursor = typeof body?.cursor === 'number' ? body.cursor : 0

  const upsertQueries: QueryDesc[] = []
  try {
    for (const entry of push) {
      if (!isSyncedTable(entry.table)) continue
      for (const row of entry.rows ?? []) {
        validateRow(entry.table, row)
        upsertQueries.push(buildUpsert(entry.table, row))
      }
    }
  } catch (err) {
    if (err instanceof InvalidRowError) {
      res.status(400).json({ error: err.message, table: err.table, id: err.id })
      return
    }
    throw err
  }

  // First query in the batch: serializes all sync requests against each
  // other (held until COMMIT) so a concurrent pull can never observe a
  // cursor past rows from a push that hasn't committed yet. See the module
  // comment above for the full race explanation.
  const lockQuery: QueryDesc = { text: 'SELECT pg_advisory_xact_lock(42)', params: [] }

  const pullQueries: QueryDesc[] = SYNCED_TABLES.map((table) => ({
    text: `SELECT * FROM ${table} WHERE seq > $1`,
    params: [cursor],
  }))
  // Virgin-safe: `last_value` is defined (as 1) even before the sequence's
  // first nextval(), which would otherwise skip seq=1 on a fresh schema.
  const cursorQuery: QueryDesc = {
    text: 'SELECT CASE WHEN is_called THEN last_value ELSE 0 END AS last_value FROM sync_seq',
    params: [],
  }

  const db = getDb()
  const results = await db.transaction([lockQuery, ...upsertQueries, ...pullQueries, cursorQuery])

  const pullStart = 1 + upsertQueries.length
  const pullResults = results.slice(pullStart, pullStart + SYNCED_TABLES.length)
  const cursorRows = results[results.length - 1] as { last_value: string | number }[]
  const nextCursor = Number(cursorRows[0]?.last_value ?? cursor)

  res.status(200).json({
    pulled: SYNCED_TABLES.map((table, i) => ({ table, rows: pullResults[i] })),
    cursor: nextCursor,
  })
}
