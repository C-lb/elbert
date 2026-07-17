import { db } from './db'
import { SYNCED_TABLES, type SyncedTable, type Review } from './types'

const stamp = <T extends object>(row: T) => ({ ...row, updatedAt: Date.now(), dirty: 1 as const })

/**
 * Callback fired after every dirtying mutation (put / softDelete / addReview).
 * The sync layer registers a debounced sync here (see App.tsx wiring) — repo is
 * the data layer and cannot import the sync client directly (sync/client
 * already imports repo), so the dependency points the other way via this hook.
 */
type MutationListener = () => void
let mutationListener: MutationListener | null = null
export function setMutationListener(fn: MutationListener | null) { mutationListener = fn }
const notifyMutation = () => {
  try { mutationListener?.() } catch { /* scheduling a sync must never break a local write */ }
}

export const repo = {
  async put(table: SyncedTable, row: any) {
    await (db as any)[table].put(stamp(row))
    notifyMutation()
  },
  async softDelete(table: Exclude<SyncedTable, 'reviews'>, id: string) {
    if ((table as string) === 'reviews') throw new Error('softDelete forbidden on append-only reviews table')
    const row = await (db as any)[table].get(id)
    if (row) {
      await (db as any)[table].put(stamp({ ...row, deletedAt: Date.now() }))
      notifyMutation()
    }
  },
  async addReview(review: Review) {
    await db.reviews.add(stamp(review))
    notifyMutation()
  },
  async dirtyRows() {
    const out: { table: SyncedTable; rows: any[] }[] = []
    for (const t of SYNCED_TABLES) {
      const rows = await (db as any)[t].where('dirty').equals(1).toArray()
      if (rows.length) out.push({ table: t, rows })
    }
    return out
  },
  async clearDirty(table: SyncedTable, ids: string[]) {
    await (db as any)[table].where('id').anyOf(ids).modify({ dirty: 0 })
  },
  async getMeta<T>(key: string) { return (await db.meta.get(key))?.value as T | undefined },
  async setMeta(key: string, value: unknown) { await db.meta.put({ key, value }) },
}
