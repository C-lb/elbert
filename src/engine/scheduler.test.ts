import 'fake-indexeddb/auto'
import { describe, it, expect, beforeEach } from 'vitest'
import { db } from '@/data/db'
import { applyReview, previewIntervals } from './scheduler'

const newCard = (): any => ({ id: 'c1', noteId: 'n1', ord: 0, due: Date.now(), stability: 0, difficulty: 0, reps: 0, lapses: 0, state: 0, lastReview: null, suspended: 0, deletedAt: null })

beforeEach(async () => { await Promise.all(db.tables.map(t => t.clear())) })

describe('scheduler', () => {
  it('Good on a new card schedules forward and logs a review', async () => {
    const updated = await applyReview(newCard(), 3, 1200, 0.9)
    expect(updated.due).toBeGreaterThan(Date.now())
    expect(updated.reps).toBe(1)
    expect(await db.reviews.count()).toBe(1)
    const r = await db.reviews.toCollection().first()
    expect(r!.rating).toBe(3)
    expect((r!.snapshot as any).reps).toBe(0) // prior state captured
  })
  it('Again increments lapses on a review-state card', async () => {
    let c = await applyReview(newCard(), 3, 1000, 0.9)
    c = await applyReview({ ...c }, 4, 1000, 0.9)
    const lapsed = await applyReview({ ...c }, 1, 1000, 0.9)
    expect(lapsed.lapses).toBeGreaterThanOrEqual(1)
  })
  it('previewIntervals returns labels for all four ratings', () => {
    const p = previewIntervals(newCard(), 0.9)
    expect(Object.keys(p)).toEqual(['1', '2', '3', '4'])
  })
})
