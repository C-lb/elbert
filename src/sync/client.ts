import { repo } from '@/data/repo'
import { db } from '@/data/db'
import { getSettings } from '@/lib/settings'
import { SYNCED_TABLES, type SyncedTable } from '@/data/types'
import { applyPulled, blobToBase64, FIELD_MAPS } from './apply'

const CURSOR_KEY = 'syncCursor'
const ENDPOINT = '/api/sync'

export type SyncResult = { pushed: number; pulled: number } | { error: string }

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

interface DirtySnapshot {
  table: SyncedTable
  ids: string[]
  updatedAtById: Map<string, number | undefined>
}

/**
 * Push local dirty rows, then pull remote changes since the stored cursor.
 * Never throws — network/validation failures surface as { error }, leaving
 * dirty flags and the stored cursor untouched so the next sync retries cleanly.
 */
export async function sync(): Promise<SyncResult> {
  const settings = await getSettings()
  if (!settings.syncKey) return { error: 'no key' }

  const dirty = await repo.dirtyRows()

  // Snapshot each dirty row's updatedAt at push time. A row edited again before
  // the response comes back must stay dirty even though this sync clears it below.
  const snapshots: DirtySnapshot[] = dirty.map(({ table, rows }) => ({
    table,
    ids: rows.map(r => r.id),
    updatedAtById: new Map(rows.map(r => [r.id, r.updatedAt])),
  }))

  const cursor = (await repo.getMeta<number>(CURSOR_KEY)) ?? 0

  let push: { table: SyncedTable; rows: Record<string, any>[] }[]
  try {
    push = await Promise.all(
      dirty.map(async ({ table, rows }) => ({
        table,
        rows: await Promise.all(rows.map(r => clientToWire(table, r))),
      }))
    )
  } catch {
    return { error: 'failed to serialize local changes' }
  }

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

  // Clear dirty only for rows whose updatedAt is unchanged since the snapshot —
  // a mid-sync edit bumps updatedAt and must remain dirty for the next sync.
  let pushedCount = 0
  for (const snap of snapshots) {
    const unchangedIds: string[] = []
    for (const id of snap.ids) {
      const row = await (db as any)[snap.table].get(id)
      const snapshotUpdatedAt = snap.updatedAtById.get(id)
      if (row && row.updatedAt === snapshotUpdatedAt) unchangedIds.push(id)
    }
    if (unchangedIds.length) {
      await repo.clearDirty(snap.table, unchangedIds)
      pushedCount += unchangedIds.length
    }
  }

  const pulledTables = (body.pulled ?? []).filter(p => (SYNCED_TABLES as readonly string[]).includes(p.table))
  const pulledCount = await applyPulled(pulledTables)

  await repo.setMeta(CURSOR_KEY, body.cursor)

  return { pushed: pushedCount, pulled: pulledCount }
}
