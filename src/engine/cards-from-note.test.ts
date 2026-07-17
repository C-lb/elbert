import { describe, it, expect } from 'vitest'
import { parseCloze, renderCloze } from './cloze'
import { cardsForNote } from './cards-from-note'

const note = (type: any, term: string): any => ({ id: 'n1', deckId: 'd1', type, fields: { term, definition: 'def' }, tags: [], deletedAt: null })

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
