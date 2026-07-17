import type { NoteType } from '@/data/types'
import { parseCloze } from './cloze'

/** A cloze draft with no {{c1::...}} marker would approve into a note with zero cards. */
export function isUnmarkedCloze(row: { type: NoteType; term: string }): boolean {
  return row.type === 'cloze' && parseCloze(row.term).length === 0
}
