import { db } from '@/data/db'
import type { SyncedTable } from '@/data/types'

/** camelCase field per table (excluding shared id/updatedAt/deletedAt) <-> snake_case wire column. */
export const FIELD_MAPS: Record<SyncedTable, [string, string][]> = {
  decks: [
    ['name', 'name'],
    ['parentId', 'parent_id'],
    ['newPerDay', 'new_per_day'],
    ['desiredRetention', 'desired_retention'],
  ],
  notes: [
    ['deckId', 'deck_id'],
    ['type', 'type'],
    ['fields', 'fields'],
    ['tags', 'tags'],
  ],
  cards: [
    ['noteId', 'note_id'],
    ['ord', 'ord'],
    ['due', 'due'],
    ['stability', 'stability'],
    ['difficulty', 'difficulty'],
    ['reps', 'reps'],
    ['lapses', 'lapses'],
    ['state', 'state'],
    ['lastReview', 'last_review'],
    ['suspended', 'suspended'],
    ['learningSteps', 'learning_steps'],
  ],
  reviews: [
    ['cardId', 'card_id'],
    ['ts', 'ts'],
    ['rating', 'rating'],
    ['elapsedMs', 'elapsed_ms'],
    ['snapshot', 'snapshot'],
  ],
  media: [
    ['hash', 'hash'],
    ['mime', 'mime'],
    // blob <-> data_base64 handled specially, not in this generic map
  ],
}

/** Bigint-ish columns Postgres hands back as strings; must be Number()ed on pull. */
const BIGINT_WIRE_COLUMNS = new Set([
  'due', 'ts', 'elapsed_ms', 'updated_at', 'deleted_at', 'seq', 'last_review',
])

function wireNumber(v: unknown): number | null {
  if (v === null || v === undefined) return null
  return typeof v === 'string' ? Number(v) : (v as number)
}

function base64ToBlob(base64: string, mime: string): Blob {
  const binary = atob(base64)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i)
  return new Blob([bytes], { type: mime })
}

export async function blobToBase64(blob: Blob): Promise<string> {
  const buf = await blob.arrayBuffer()
  let binary = ''
  const bytes = new Uint8Array(buf)
  for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i])
  return btoa(binary)
}

/** Convert one wire (snake_case) row to a client (camelCase) row for the given table. */
export function wireToClient(table: SyncedTable, wire: Record<string, any>): any {
  const out: Record<string, any> = {
    id: wire.id,
    updatedAt: wireNumber(wire.updated_at),
    deletedAt: wireNumber(wire.deleted_at),
    dirty: 0 as const,
  }
  if (table === 'media') {
    out.hash = wire.hash
    out.mime = wire.mime
    out.blob = wire.data_base64 != null ? base64ToBlob(wire.data_base64, wire.mime) : undefined
    return out
  }
  for (const [camel, snake] of FIELD_MAPS[table]) {
    let v = wire[snake]
    if (BIGINT_WIRE_COLUMNS.has(snake)) v = wireNumber(v)
    out[camel] = v
  }
  return out
}

/**
 * Write pulled rows locally with dirty: 0.
 * Non-review tables: skip any pulled row older (by updatedAt) than the local copy — last-write-wins,
 * but a stale pull must never clobber a newer local edit made between snapshot and apply.
 * Reviews: always bulkPut keyed by id — append-only log, applying twice is a no-op either way.
 */
export async function applyPulled(tables: { table: SyncedTable; rows: Record<string, any>[] }[]): Promise<number> {
  let applied = 0
  for (const { table, rows } of tables) {
    if (!rows.length) continue
    const clientRows = rows.map(r => wireToClient(table, r))

    if (table === 'reviews') {
      await db.reviews.bulkPut(clientRows as any)
      applied += clientRows.length
      continue
    }

    const t = (db as any)[table]
    const ids = clientRows.map(r => r.id)
    const existing = await t.bulkGet(ids)
    const toPut: any[] = []
    clientRows.forEach((row, i) => {
      const local = existing[i]
      const localUpdatedAt = local?.updatedAt ?? -Infinity
      if ((row.updatedAt ?? 0) >= localUpdatedAt) toPut.push(row)
    })
    if (toPut.length) {
      await t.bulkPut(toPut)
      applied += toPut.length
    }
  }
  return applied
}
