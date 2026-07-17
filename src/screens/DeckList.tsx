import { useEffect, useState } from 'react'
import { v4 as uuid } from 'uuid'
import { db } from '@/data/db'
import { repo } from '@/data/repo'
import { dueCountsAll } from '@/engine/queue'
import type { Deck } from '@/data/types'

interface DeckRow {
  deck: Deck
  due: number
  newAvailable: number
}

interface DeckListProps {
  onOpenDeck: (deckId: string) => void
}

function EditIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
      <path d="M12 20h9" />
      <path d="M16.5 3.5a2.12 2.12 0 0 1 3 3L7 19l-4 1 1-4Z" />
    </svg>
  )
}

export default function DeckList({ onOpenDeck }: DeckListProps) {
  const [rows, setRows] = useState<DeckRow[] | null>(null)
  const [newName, setNewName] = useState('')
  const [creating, setCreating] = useState(false)

  const load = async () => {
    const decks = await db.decks.filter(d => d.deletedAt == null).toArray()
    const counts = await dueCountsAll()
    const withCounts = decks.map(deck => {
      const c = counts.get(deck.id) ?? { due: 0, newAvailable: 0 }
      return { deck, due: c.due, newAvailable: c.newAvailable }
    })
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
          <div key={deck.id} className="deck-row">
            <button className="deck-row-main" onClick={() => onOpenDeck(deck.id)}>
              <span className="deck-name">{deck.name}</span>
              <span className="deck-counts">
                <span className="deck-count-due">{due} due</span>
                <span className="deck-count-new">{newAvailable} new</span>
              </span>
            </button>
            <a className="nav-icon-btn deck-row-edit" href={`#/edit/${deck.id}`} aria-label={`Edit ${deck.name}`} data-tip="Edit notes">
              <EditIcon />
            </a>
          </div>
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
