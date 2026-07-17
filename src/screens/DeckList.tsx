import { useEffect, useState } from 'react'
import { v4 as uuid } from 'uuid'
import { db } from '@/data/db'
import { repo } from '@/data/repo'
import { dueCounts } from '@/engine/queue'
import type { Deck } from '@/data/types'

interface DeckRow {
  deck: Deck
  due: number
  newAvailable: number
}

interface DeckListProps {
  onOpenDeck: (deckId: string) => void
}

export default function DeckList({ onOpenDeck }: DeckListProps) {
  const [rows, setRows] = useState<DeckRow[] | null>(null)
  const [newName, setNewName] = useState('')
  const [creating, setCreating] = useState(false)

  const load = async () => {
    const decks = await db.decks.filter(d => d.deletedAt == null).toArray()
    const withCounts = await Promise.all(
      decks.map(async deck => {
        const counts = await dueCounts(deck.id)
        return { deck, due: counts.due, newAvailable: counts.newAvailable }
      }),
    )
    setRows(withCounts)
  }

  useEffect(() => {
    load()
  }, [])

  const createDeck = async () => {
    const name = newName.trim()
    if (!name) return
    setCreating(true)
    try {
      const deck: Deck = {
        id: uuid(),
        name,
        parentId: null,
        newPerDay: 20,
        desiredRetention: 0.9,
        deletedAt: null,
      }
      await repo.put('decks', deck)
      setNewName('')
      await load()
    } finally {
      setCreating(false)
    }
  }

  return (
    <div>
      <div className="section-title">Decks</div>
      <div className="deck-list">
        {rows === null && <div className="deck-empty">Loading…</div>}
        {rows !== null && rows.length === 0 && <div className="deck-empty">No decks yet. Add one below.</div>}
        {rows?.map(({ deck, due, newAvailable }) => (
          <button key={deck.id} className="deck-row" onClick={() => onOpenDeck(deck.id)}>
            <span className="deck-name">{deck.name}</span>
            <span className="deck-counts">
              <span className="deck-count-due">{due} due</span>
              <span className="deck-count-new">{newAvailable} new</span>
            </span>
          </button>
        ))}
      </div>
      <div className="new-deck-row" style={{ marginTop: 'var(--s3)' }}>
        <input
          className="field"
          placeholder="New deck name"
          value={newName}
          onChange={e => setNewName(e.target.value)}
          onKeyDown={e => {
            if (e.key === 'Enter') createDeck()
          }}
        />
        <button className="btn" onClick={createDeck} disabled={creating || !newName.trim()}>
          Add
        </button>
      </div>
    </div>
  )
}
