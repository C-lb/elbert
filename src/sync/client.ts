import { repo } from '@/data/repo'
import { db } from '@/data/db'
import { getSettings } from '@/lib/settings'
import { SYNCED_TABLES, type SyncedTable } from '@/data/types'
import { applyPulled, blobToBase64, FIELD_MAPS } from './apply'

const CURSOR_KEY = 'syncCursor'
const ENDPOINT = '/api/sync'

/**
 * Per-request payload budget. Vercel rejects bodies over ~4.5MB; media rows are
 * base64-inflated ~4/3, so cap the estimated JSON payload well under that. A
 * single row bigger than this on its own is skipped (stays dirty) rather than
 * wedging every future push.
 */
const MAX_BATCH_BYTES = 3_500_000

export type SyncResult = { pushed: number; pulled: number; skipped?: number } | { error: string }

/** Convert one client (camelCase) row to a wire (snake_case) row for the given table. */
async function clientToWire(table: SyncedTable, row: Record<string, any>): Promise<Record<string, any>> {
  const out: Record<string, any> = {
    id: row.id,
    updated_at: row.updatedAt,
    deleted_at: row.deletedAt ?? null,
  }
  if (table === 'media') {
    out.hash = row.hash
    out.mime = row.mime
    out.data_base64 = row.blob ? await blobToBase64(row.blob) : null
    return out
  }
  for (const [camel, snake] of FIELD_MAPS[table]) {
    out[snake] = row[camel] ?? null
  }
  return out
}

interface WireRowEntry {
  table: SyncedTable
  id: string
  /** updatedAt snapshotted at serialize time — a row edited again before the
   * response comes back must stay dirty even though this sync pushed it. */
  updatedAt: number | undefined
  wire: Record<string, any>
  bytes: number
}

/**
 * Push local dirty rows, then pull remote changes since the stored cursor.
 * Never throws — ANY failure (network, validation, or an IndexedDB error from
 * repo/db calls) surfaces as { error }, leaving dirty flags and the stored
 * cursor untouched so the next sync retries cleanly.
 *
 * Overlapping calls coalesce: a sync already in flight is returned to every
 * caller that asks for one while it's running, rather than starting a second
 * concurrent push/pull against the same dirty rows.
 */
export function sync(): Promise<SyncResult> {
  if (inFlight) return inFlight
  inFlight = runSync().finally(() => {
    inFlight = null
  })
  return inFlight
}

let inFlight: Promise<SyncResult> | null = null

async function runSync(): Promise<SyncResult> {
  try {
    const settings = await getSettings()
    if (!settings.syncKey) return { error: 'no key' }

    const dirty = await repo.dirtyRows()

    let entries: WireRowEntry[]
    try {
      entries = (
        await Promise.all(
          dirty.map(({ table, rows }) =>
            Promise.all(
              rows.map(async r => {
                const wire = await clientToWire(table, r)
                // JSON.stringify().length approximates serialized bytes: ids and
                // base64 media (the dominant weight) are pure ASCII, so the odd
                // multi-byte char in a text field is noise at this scale.
                return { table, id: r.id, updatedAt: r.updatedAt, wire, bytes: JSON.stringify(wire).length }
              })
            )
          )
        )
      ).flat()
    } catch {
      return { error: 'failed to serialize local changes' }
    }

    // Greedy batching under the per-request budget. A single row that alone
    // exceeds it is skipped: it stays dirty (never cleared below) and must not
    // wedge every other row's replication.
    const batches: WireRowEntry[][] = []
    let current: WireRowEntry[] = []
    let currentBytes = 0
    let skipped = 0
    for (const entry of entries) {
      if (entry.bytes > MAX_BATCH_BYTES) {
        console.warn(
          `sync: skipping oversized ${entry.table} row ${entry.id} (~${entry.bytes} bytes > ${MAX_BATCH_BYTES} limit); it stays dirty and will not block other rows`
        )
        skipped++
        continue
      }
      if (current.length && currentBytes + entry.bytes > MAX_BATCH_BYTES) {
        batches.push(current)
        current = []
        currentBytes = 0
      }
      current.push(entry)
      currentBytes += entry.bytes
    }
    if (current.length) batches.push(current)
    // Nothing to push still means one request: sync always pulls.
    if (!batches.length) batches.push([])

    let cursor = (await repo.getMeta<number>(CURSOR_KEY)) ?? 0
    let pushedCount = 0
    let pulledCount = 0

    // Sequential requests: the server upserts idempotently per row, and each
    // response's cursor (read after its pull, same server transaction) feeds the
    // next request so pull ordering stays correct. A later batch may pull back
    // rows an earlier batch pushed — harmless, LWW applies them as no-ops.
    for (const batch of batches) {
      const byTable = new Map<SyncedTable, WireRowEntry[]>()
      for (const entry of batch) {
        const list = byTable.get(entry.table)
        if (list) list.push(entry)
        else byTable.set(entry.table, [entry])
      }
      const push = [...byTable.entries()].map(([table, list]) => ({ table, rows: list.map(e => e.wire) }))

      let res: Response
      try {
        res = await fetch(ENDPOINT, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'x-elbert-key': settings.syncKey },
          body: JSON.stringify({ push, cursor }),
        })
      } catch {
        return { error: 'network error' }
      }

      if (!res.ok) {
        let message = `sync failed: ${res.status}`
        try {
          const body = await res.json()
          if (body?.error) message = body.error
        } catch {
          // ignore unparseable error body
        }
        return { error: message }
      }

      let body: { pulled: { table: SyncedTable; rows: Record<string, any>[] }[]; cursor: number }
      try {
        body = await res.json()
      } catch {
        return { error: 'malformed response' }
      }

      const pulledTables = (body.pulled ?? []).filter(p => (SYNCED_TABLES as readonly string[]).includes(p.table))

      // Everything from here on is local write side-effects of a successful server round trip:
      // clearing dirty flags, applying pulled rows, and advancing the cursor. Run them in one
      // Dexie transaction so a failure partway through (e.g. an IndexedDB quota error while
      // applying a pulled row) rolls back the whole batch instead of leaving dirty flags cleared
      // for rows whose pulled counterparts never got written. An earlier batch's committed
      // transaction stays committed — its rows really are on the server, so that's correct.
      await db.transaction('rw', [db.decks, db.notes, db.cards, db.reviews, db.media, db.meta], async () => {
        // Clear dirty only for rows whose updatedAt is unchanged since the snapshot —
        // a mid-sync edit bumps updatedAt and must remain dirty for the next sync.
        for (const [table, list] of byTable) {
          const unchangedIds: string[] = []
          for (const entry of list) {
            const row = await (db as any)[table].get(entry.id)
            if (row && row.updatedAt === entry.updatedAt) unchangedIds.push(entry.id)
          }
          if (unchangedIds.length) {
            await repo.clearDirty(table, unchangedIds)
            pushedCount += unchangedIds.length
          }
        }

        pulledCount += await applyPulled(pulledTables)

        await repo.setMeta(CURSOR_KEY, body.cursor)
      })

      cursor = body.cursor
    }

    return skipped > 0
      ? { pushed: pushedCount, pulled: pulledCount, skipped }
      : { pushed: pushedCount, pulled: pulledCount }
  } catch (err) {
    return { error: String(err instanceof Error ? err.message : err) }
  }
}
