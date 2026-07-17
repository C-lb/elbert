import type { Note, NoteType } from '@/data/types'

export interface UIRow {
  id: string
  persisted: boolean
  type: NoteType
  term: string
  definition: string
  example: string
  hint: string
  imageId?: string
}

// Builds the note to store for a row. When the note already exists, everything the grid
// doesn't edit (tags, sync bookkeeping, any future fields) is carried over from it — the
// grid only owns type + the five field cells.
export function noteFromRow(deckId: string, row: UIRow, existing?: Note): Note {
  const fields: Note['fields'] = { ...existing?.fields, term: row.term, definition: row.definition }
  if (row.example.trim()) fields.example = row.example
  else delete fields.example
  if (row.hint.trim()) fields.hint = row.hint
  else delete fields.hint
  if (row.imageId) fields.imageId = row.imageId
  else delete fields.imageId
  return { ...existing, id: row.id, deckId, type: row.type, fields, tags: existing?.tags ?? [], deletedAt: existing?.deletedAt ?? null }
}

// True when the two notes agree on everything the grid can edit. Used to skip the DB write
// (and the dirty flag) on blur when nothing actually changed.
export function sameNoteContent(a: Note, b: Note): boolean {
  return (
    a.deckId === b.deckId &&
    a.type === b.type &&
    a.fields.term === b.fields.term &&
    a.fields.definition === b.fields.definition &&
    (a.fields.example ?? '') === (b.fields.example ?? '') &&
    (a.fields.hint ?? '') === (b.fields.hint ?? '') &&
    (a.fields.imageId ?? '') === (b.fields.imageId ?? '')
  )
}
