import { db } from './db'
import { SYNCED_TABLES, type SyncedTable, type Review } from './types'

const stamp = <T extends object>(row: T) => ({ ...row, updatedAt: Date.now(), dirty: 1 as const })

export const repo = {
  async put(table: SyncedTable, row: any) { await (db as any)[table].put(stamp(row)) },
  async softDelete(table: Exclude<SyncedTable, 'reviews'>, id: string) {
    if (table === 'reviews') throw new Error('softDelete forbidden on append-only reviews table')
    const row = await (db as any)[table].get(id)
    if (row) await (db as any)[table].put(stamp({ ...row, deletedAt: Date.now() }))
  },
  async addReview(review: Review) { await db.reviews.add(stamp(review)) },
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
