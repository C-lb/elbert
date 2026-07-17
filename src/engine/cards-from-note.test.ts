import 'fake-indexeddb/auto'
import { describe, it, expect, beforeEach } from 'vitest'
import { db } from '@/data/db'
import { parseCloze, renderCloze } from './cloze'
import { cardsForNote, syncCardsWithNote } from './cards-from-note'

const note = (type: any, term: string): any => ({ id: 'n1', deckId: 'd1', type, fields: { term, definition: 'def' }, tags: [], deletedAt: null })

beforeEach(async () => { await Promise.all(db.tables.map(t => t.clear())) })

describe('cloze', () => {
  it('finds distinct ordinals and hints', () => {
    expect(parseCloze('{{c1::Madrid::capital}} is in {{c2::Spain}}, {{c1::Madrid}}')).toEqual([{ ord: 1, hint: 'capital' }, { ord: 2 }])
  })
  it('renders hidden target, shows others', () => {
    expect(renderCloze('{{c1::Madrid::capital}} is in {{c2::Spain}}', 1, false)).toBe('[capital] is in Spain')
    expect(renderCloze('{{c1::Madrid}} is in {{c2::Spain}}', 1, true)).toBe('Madrid is in Spain')
  })
})

describe('cardsForNote', () => {
  it('basic → 1, reversed → 2, cloze → per ordinal', () => {
    expect(cardsForNote(note('basic', 'hola'))).toHaveLength(1)
    expect(cardsForNote(note('basic_reversed', 'hola')).map(c => c.ord)).toEqual([0, 1])
    expect(cardsForNote(note('cloze', '{{c1::a}} {{c2::b}}')).map(c => c.ord)).toEqual([1, 2])
  })
  it('new cards start due now, state 0', () => {
    const [c] = cardsForNote(note('basic', 'hola'))
    expect(c.state).toBe(0)
    expect(c.due).toBeLessThanOrEqual(Date.now())
  })
})

describe('syncCardsWithNote', () => {
  it('new note with no cards yet creates all via cardsForNote', async () => {
    const n = note('basic', 'hola')
    await syncCardsWithNote(n)
    const cards = await db.cards.where('noteId').equals('n1').toArray()
    expect(cards).toHaveLength(1)
    expect(cards[0].ord).toBe(0)
    expect(cards[0].deletedAt).toBeNull()
  })

  it('cloze: adding a new ordinal creates a missing card, leaves existing untouched', async () => {
    const n = note('cloze', '{{c1::a}} {{c2::b}}')
    await syncCardsWithNote(n)
    const before = await db.cards.where('noteId').equals('n1').toArray()
    const c1 = before.find(c => c.ord === 1)!
    // simulate FSRS progress on card ord=1
    await db.cards.put({ ...c1, reps: 5, stability: 12.3, dirty: 0 })

    const n2 = note('cloze', '{{c1::a}} {{c2::b}} {{c3::c}}')
    n2.id = 'n1'
    await syncCardsWithNote(n2)

    const after = await db.cards.where('noteId').equals('n1').toArray()
    const live = after.filter(c => c.deletedAt == null)
    expect(live.map(c => c.ord).sort()).toEqual([1, 2, 3])
    const c1After = after.find(c => c.ord === 1)!
    expect(c1After.reps).toBe(5)
    expect(c1After.stability).toBe(12.3)
  })

  it('cloze: removing an ordinal soft-deletes its card', async () => {
    const n = note('cloze', '{{c1::a}} {{c2::b}}')
    await syncCardsWithNote(n)

    const n2 = note('cloze', '{{c1::a}}')
    n2.id = 'n1'
    await syncCardsWithNote(n2)

    const after = await db.cards.where('noteId').equals('n1').toArray()
    const ord2 = after.find(c => c.ord === 2)!
    expect(ord2.deletedAt).not.toBeNull()
    const ord1 = after.find(c => c.ord === 1)!
    expect(ord1.deletedAt).toBeNull()
  })

  it('type change basic -> basic_reversed adds ord-1 card', async () => {
    const n = note('basic', 'hola')
    await syncCardsWithNote(n)

    const n2 = note('basic_reversed', 'hola')
    n2.id = 'n1'
    await syncCardsWithNote(n2)

    const after = await db.cards.where('noteId').equals('n1').toArray()
    const live = after.filter(c => c.deletedAt == null)
    expect(live.map(c => c.ord).sort()).toEqual([0, 1])
  })

  it('type change basic_reversed -> basic soft-deletes ord 1', async () => {
    const n = note('basic_reversed', 'hola')
    await syncCardsWithNote(n)

    const n2 = note('basic', 'hola')
    n2.id = 'n1'
    await syncCardsWithNote(n2)

    const after = await db.cards.where('noteId').equals('n1').toArray()
    const live = after.filter(c => c.deletedAt == null)
    expect(live.map(c => c.ord)).toEqual([0])
    const ord1 = after.find(c => c.ord === 1)!
    expect(ord1.deletedAt).not.toBeNull()
  })

  it('resurrects a soft-deleted card at a reappearing ordinal with fresh FSRS state, same id', async () => {
    const n = note('basic_reversed', 'hola')
    await syncCardsWithNote(n)
    const firstOrd1 = (await db.cards.where('noteId').equals('n1').toArray()).find(c => c.ord === 1)!

    const toBasic = note('basic', 'hola')
    toBasic.id = 'n1'
    await syncCardsWithNote(toBasic) // ord 1 soft-deleted

    // simulate the deleted card having old FSRS state before it comes back
    const deletedOrd1 = (await db.cards.where('noteId').equals('n1').toArray()).find(c => c.ord === 1)!
    await db.cards.put({ ...deletedOrd1, reps: 9, stability: 42, state: 2, dirty: 0 })

    const backToReversed = note('basic_reversed', 'hola')
    backToReversed.id = 'n1'
    await syncCardsWithNote(backToReversed)

    const after = await db.cards.where('noteId').equals('n1').toArray()
    const live = after.filter(c => c.deletedAt == null)
    expect(live.map(c => c.ord).sort()).toEqual([0, 1])
    const resurrected = live.find(c => c.ord === 1)!
    expect(resurrected.id).toBe(firstOrd1.id) // same id reused, not a new row
    expect(resurrected.reps).toBe(0) // fresh FSRS state, not the stale progress
    expect(resurrected.stability).toBe(0)
    expect(resurrected.state).toBe(0)
  })

  it('round trip basic -> reversed -> basic -> reversed ends with exactly 2 card rows total, none duplicated', async () => {
    const n = note('basic', 'hola')
    await syncCardsWithNote(n)

    const reversed1 = note('basic_reversed', 'hola')
    reversed1.id = 'n1'
    await syncCardsWithNote(reversed1)

    const basic2 = note('basic', 'hola')
    basic2.id = 'n1'
    await syncCardsWithNote(basic2)

    const reversed2 = note('basic_reversed', 'hola')
    reversed2.id = 'n1'
    await syncCardsWithNote(reversed2)

    const after = await db.cards.where('noteId').equals('n1').toArray()
    expect(after).toHaveLength(2) // no dead duplicate rows accumulated across the round trip
    const live = after.filter(c => c.deletedAt == null)
    expect(live.map(c => c.ord).sort()).toEqual([0, 1])
  })
})
