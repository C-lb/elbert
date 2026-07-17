import 'fake-indexeddb/auto'
import { describe, it, expect, beforeEach } from 'vitest'
import { db } from '@/data/db'
import { liveNotes } from './live'

const deck = (id: string, over: any = {}): any => ({ id, name: id, parentId: null, newPerDay: 2, desiredRetention: 0.9, deletedAt: null, ...over })
const note = (id: string, deckId: string, over: any = {}): any => ({ id, deckId, type: 'basic', fields: { term: 't', definition: 'd' }, tags: [], deletedAt: null, ...over })

beforeEach(async () => {
  await Promise.all(db.tables.map(t => t.clear()))
  await db.decks.bulkAdd([deck('d1'), deck('d2', { deletedAt: Date.now() })])
  await db.notes.bulkAdd([
    note('a', 'd1'),
    note('b', 'd1', { deletedAt: Date.now() }), // soft-deleted note
    note('c', 'd2'), // live note in soft-deleted deck
    note('d', 'gone'), // note whose deck no longer exists
  ])
})

describe('liveNotes', () => {
  it('excludes soft-deleted notes, notes in soft-deleted decks, and orphaned notes', async () => {
    const notes = await liveNotes()
    expect(notes.map(n => n.id)).toEqual(['a'])
  })

  it('scopes to a deck', async () => {
    await db.decks.add(deck('d3'))
    await db.notes.add(note('e', 'd3'))
    expect((await liveNotes('d3')).map(n => n.id)).toEqual(['e'])
    expect((await liveNotes('d1')).map(n => n.id)).toEqual(['a'])
  })

  it('returns nothing for a soft-deleted or missing deck', async () => {
    expect(await liveNotes('d2')).toEqual([])
    expect(await liveNotes('gone')).toEqual([])
  })
})
