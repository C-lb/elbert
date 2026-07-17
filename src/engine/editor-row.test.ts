import 'fake-indexeddb/auto'
import { describe, it, expect } from 'vitest'
import { noteFromRow, sameNoteContent } from './editor-row'
import type { Note } from '@/data/types'

interface RowShape {
  id: string
  persisted: boolean
  type: Note['type']
  term: string
  definition: string
  example: string
  hint: string
  imageId?: string
}

const row = (over: Partial<RowShape> = {}): RowShape => ({
  id: 'n1', persisted: true, type: 'basic', term: 'hola', definition: 'hello', example: '', hint: '', ...over,
})

const existing = (over: Partial<Note> = {}): Note => ({
  id: 'n1', deckId: 'd1', type: 'basic',
  fields: { term: 'hola', definition: 'hello' },
  tags: ['anki', 'spanish'], deletedAt: null, updatedAt: 123, dirty: 0,
  ...over,
})

describe('noteFromRow', () => {
  it('defaults tags to empty for a brand new note', () => {
    const note = noteFromRow('d1', row())
    expect(note.tags).toEqual([])
    expect(note.deletedAt).toBeNull()
    expect(note.fields).toEqual({ term: 'hola', definition: 'hello' })
  })

  it('preserves the existing note tags', () => {
    const note = noteFromRow('d1', row({ definition: 'hi' }), existing())
    expect(note.tags).toEqual(['anki', 'spanish'])
    expect(note.fields.definition).toBe('hi')
  })

  it('carries over top-level props the grid does not edit', () => {
    const note = noteFromRow('d1', row(), existing())
    expect(note.updatedAt).toBe(123)
    expect(note.dirty).toBe(0)
    expect(note.deletedAt).toBeNull()
  })

  it('grid still owns the editable fields', () => {
    const note = noteFromRow('d1', row({ type: 'cloze', example: 'ex', hint: 'h', imageId: 'img1' }), existing())
    expect(note.type).toBe('cloze')
    expect(note.fields).toEqual({ term: 'hola', definition: 'hello', example: 'ex', hint: 'h', imageId: 'img1' })
  })

  it('clearing a cell removes the field even if the existing note had it', () => {
    const note = noteFromRow('d1', row(), existing({ fields: { term: 'hola', definition: 'hello', example: 'old', hint: 'old', imageId: 'old' } }))
    expect(note.fields.example).toBeUndefined()
    expect(note.fields.hint).toBeUndefined()
    expect(note.fields.imageId).toBeUndefined()
  })
})

describe('sameNoteContent', () => {
  it('true for a blur without an edit', () => {
    const a = existing()
    const b = noteFromRow('d1', row(), a)
    expect(sameNoteContent(b, a)).toBe(true)
  })

  it('treats missing optional fields and empty strings as equal', () => {
    const a = existing({ fields: { term: 'hola', definition: 'hello', example: undefined } })
    const b = noteFromRow('d1', row(), a)
    expect(sameNoteContent(b, a)).toBe(true)
  })

  it('false when a field changes', () => {
    const a = existing()
    expect(sameNoteContent(noteFromRow('d1', row({ term: 'adios' }), a), a)).toBe(false)
    expect(sameNoteContent(noteFromRow('d1', row({ hint: 'new hint' }), a), a)).toBe(false)
    expect(sameNoteContent(noteFromRow('d1', row({ imageId: 'img9' }), a), a)).toBe(false)
  })

  it('false when the type changes', () => {
    const a = existing()
    expect(sameNoteContent(noteFromRow('d1', row({ type: 'basic_reversed' }), a), a)).toBe(false)
  })

  it('false when a field is cleared', () => {
    const a = existing({ fields: { term: 'hola', definition: 'hello', example: 'ex' } })
    expect(sameNoteContent(noteFromRow('d1', row(), a), a)).toBe(false)
  })

  it('ignores tags and sync bookkeeping', () => {
    const a = existing({ tags: ['x'], dirty: 1, updatedAt: 999 })
    const b = noteFromRow('d1', row(), a)
    expect(sameNoteContent(b, a)).toBe(true)
  })
})
