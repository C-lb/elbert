import Dexie, { type Table } from 'dexie'
import type { Deck, Note, Card, Review, Media } from './types'

export class ElbertDB extends Dexie {
  decks!: Table<Deck, string>; notes!: Table<Note, string>; cards!: Table<Card, string>
  reviews!: Table<Review, string>; media!: Table<Media, string>
  meta!: Table<{ key: string; value: unknown }, string>
  constructor() {
    super('elbert')
    this.version(1).stores({
      decks: 'id, parentId, dirty',
      notes: 'id, deckId, dirty',
      cards: 'id, noteId, due, state, dirty',
      reviews: 'id, cardId, ts, dirty',
      media: 'id, hash, dirty',
      meta: 'key',
    })
  }
}
export const db = new ElbertDB()
