import { useEffect, useState } from 'react'
import { db } from '@/data/db'
import { SYNCED_TABLES } from '@/data/types'
import { sync, type SyncResult } from './client'

async function countDirty(): Promise<number> {
  const counts = await Promise.all(SYNCED_TABLES.map(t => (db as any)[t].where('dirty').equals(1).count()))
  return counts.reduce((a, b) => a + b, 0)
}

export interface SyncStatus {
  pending: number
  lastResult: SyncResult | null
}

let lastResult: SyncResult | null = null
const listeners = new Set<() => void>()

function reportSyncResult(result: SyncResult): void {
  lastResult = result
  listeners.forEach(fn => fn())
}

/** Fire-and-forget sync: never awaited by callers, result recorded for every useSyncStatus() instance. */
export function requestSync(): void {
  void sync().then(reportSyncResult)
}

/** Live pending-dirty-row count plus the outcome of the most recent sync. Polls Dexie; no deps on the sync module itself. */
export function useSyncStatus(): SyncStatus {
  const [pending, setPending] = useState(0)
  const [, setTick] = useState(0)

  useEffect(() => {
    let cancelled = false
    const refresh = () => {
      countDirty().then(n => {
        if (!cancelled) setPending(n)
      })
    }
    refresh()
    const interval = setInterval(refresh, 2000)

    const onResult = () => setTick(t => t + 1)
    listeners.add(onResult)

    return () => {
      cancelled = true
      clearInterval(interval)
      listeners.delete(onResult)
    }
  }, [])

  return { pending, lastResult }
}
