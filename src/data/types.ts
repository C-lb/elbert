export type NoteType = 'basic' | 'basic_reversed' | 'cloze'
export type Rating = 1 | 2 | 3 | 4 // Again Hard Good Easy
export interface Synced { id: string; updatedAt?: number; deletedAt: number | null; dirty?: 0 | 1 }
export interface Deck extends Synced { name: string; parentId: string | null; newPerDay: number; desiredRetention: number }
export interface Note extends Synced { deckId: string; type: NoteType; fields: { term: string; definition: string; example?: string; imageId?: string; hint?: string }; tags: string[] }
export interface Card extends Synced { noteId: string; ord: number; due: number; stability: number; difficulty: number; reps: number; lapses: number; state: 0 | 1 | 2 | 3; lastReview: number | null; suspended: 0 | 1; learningSteps: number }
export interface Review extends Synced { cardId: string; ts: number; rating: Rating; elapsedMs: number; snapshot: unknown }
export interface Media extends Synced { hash: string; blob?: Blob; mime: string }
export const SYNCED_TABLES = ['decks', 'notes', 'cards', 'reviews', 'media'] as const
export type SyncedTable = typeof SYNCED_TABLES[number]
