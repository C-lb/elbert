import { describe, it, expect } from 'vitest'
import { createMatchGame } from './match'
import type { Note } from '@/data/types'

function mulberry32(seed: number): () => number {
  let a = seed
  return function () {
    a |= 0
    a = (a + 0x6d2b79f5) | 0
    let t = Math.imul(a ^ (a >>> 15), 1 | a)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

function note(id: string, term = `term-${id}`, definition = `def-${id}`): Note {
  return {
    id,
    deckId: 'd1',
    type: 'basic',
    fields: { term, definition },
    tags: [],
    deletedAt: null,
  }
}

describe('createMatchGame', () => {
  it('produces 12 tiles (6 pairs) when there are 6+ notes', () => {
    const notes = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'].map(id => note(id))
    const game = createMatchGame(notes, mulberry32(1))
    expect(game.tiles()).toHaveLength(12)
  })

  it('produces 2N tiles when there are fewer than 6 notes', () => {
    const notes = ['a', 'b', 'c'].map(id => note(id))
    const game = createMatchGame(notes, mulberry32(1))
    expect(game.tiles()).toHaveLength(6)
  })

  it('each note contributes one term tile and one answer tile', () => {
    const notes = ['a', 'b', 'c'].map(id => note(id))
    const game = createMatchGame(notes, mulberry32(1))
    const tiles = game.tiles()
    for (const n of notes) {
      const forNote = tiles.filter(t => t.noteId === n.id)
      expect(forNote).toHaveLength(2)
      expect(forNote.map(t => t.kind).sort()).toEqual(['answer', 'term'])
    }
  })

  it('grid order is deterministic given the same seed', () => {
    const notes = ['a', 'b', 'c', 'd', 'e', 'f', 'g'].map(id => note(id))
    const g1 = createMatchGame(notes, mulberry32(42))
    const g2 = createMatchGame(notes, mulberry32(42))
    expect(g1.tiles().map(t => t.id)).toEqual(g2.tiles().map(t => t.id))
  })

  it('a correct pair (term + its own answer) returns match and sets matched flags', () => {
    const notes = ['a', 'b', 'c'].map(id => note(id))
    const game = createMatchGame(notes, mulberry32(2))
    const termA = game.tiles().find(t => t.noteId === 'a' && t.kind === 'term')!
    const answerA = game.tiles().find(t => t.noteId === 'a' && t.kind === 'answer')!

    expect(game.pick(termA.id)).toBe('first')
    expect(game.pick(answerA.id)).toBe('match')

    const tiles = game.tiles()
    expect(tiles.find(t => t.id === termA.id)!.matched).toBe(true)
    expect(tiles.find(t => t.id === answerA.id)!.matched).toBe(true)
    expect(game.misses()).toBe(0)
  })

  it('a wrong pair returns miss and increments the miss counter', () => {
    const notes = ['a', 'b', 'c'].map(id => note(id))
    const game = createMatchGame(notes, mulberry32(2))
    const termA = game.tiles().find(t => t.noteId === 'a' && t.kind === 'term')!
    const termB = game.tiles().find(t => t.noteId === 'b' && t.kind === 'term')!

    expect(game.pick(termA.id)).toBe('first')
    expect(game.pick(termB.id)).toBe('miss')
    expect(game.misses()).toBe(1)

    const tiles = game.tiles()
    expect(tiles.find(t => t.id === termA.id)!.matched).toBe(false)
    expect(tiles.find(t => t.id === termB.id)!.matched).toBe(false)
  })

  it('a term matched with its own answer of different kind but same note counts as match, but two terms of different notes miss', () => {
    const notes = ['a', 'b'].map(id => note(id))
    const game = createMatchGame(notes, mulberry32(3))
    const answerA = game.tiles().find(t => t.noteId === 'a' && t.kind === 'answer')!
    const answerB = game.tiles().find(t => t.noteId === 'b' && t.kind === 'answer')!
    game.pick(answerA.id)
    expect(game.pick(answerB.id)).toBe('miss')
  })

  it('picking the same tile twice is ignored, not a miss', () => {
    const notes = ['a', 'b', 'c'].map(id => note(id))
    const game = createMatchGame(notes, mulberry32(2))
    const termA = game.tiles().find(t => t.noteId === 'a' && t.kind === 'term')!

    expect(game.pick(termA.id)).toBe('first')
    expect(game.pick(termA.id)).toBe('ignored')
    expect(game.misses()).toBe(0)
  })

  it('picking an already-matched tile is ignored, not a miss', () => {
    const notes = ['a', 'b', 'c'].map(id => note(id))
    const game = createMatchGame(notes, mulberry32(2))
    const termA = game.tiles().find(t => t.noteId === 'a' && t.kind === 'term')!
    const answerA = game.tiles().find(t => t.noteId === 'a' && t.kind === 'answer')!
    const termB = game.tiles().find(t => t.noteId === 'b' && t.kind === 'term')!

    game.pick(termA.id)
    game.pick(answerA.id) // match

    expect(game.pick(termA.id)).toBe('ignored')
    expect(game.misses()).toBe(0)

    // sanity: unrelated pick still works normally afterward
    expect(game.pick(termB.id)).toBe('first')
  })

  it('returns done when the last pair matches', () => {
    const notes = ['a', 'b'].map(id => note(id))
    const game = createMatchGame(notes, mulberry32(4))
    const termA = game.tiles().find(t => t.noteId === 'a' && t.kind === 'term')!
    const answerA = game.tiles().find(t => t.noteId === 'a' && t.kind === 'answer')!
    const termB = game.tiles().find(t => t.noteId === 'b' && t.kind === 'term')!
    const answerB = game.tiles().find(t => t.noteId === 'b' && t.kind === 'answer')!

    game.pick(termA.id)
    expect(game.pick(answerA.id)).toBe('match')

    game.pick(termB.id)
    expect(game.pick(answerB.id)).toBe('done')
  })

  it('handles cloze notes via answerForNote for the answer tile text', () => {
    const clozeNote: Note = {
      id: 'z',
      deckId: 'd1',
      type: 'cloze',
      fields: { term: 'The {{c1::mitochondria}} is the powerhouse of the cell', definition: '' },
      tags: [],
      deletedAt: null,
    }
    const game = createMatchGame([clozeNote], mulberry32(1))
    const answerTile = game.tiles().find(t => t.noteId === 'z' && t.kind === 'answer')!
    expect(answerTile.text).toBe('mitochondria')
  })
})
