import { useCallback, useEffect, useState } from 'react'
import { db } from '@/data/db'
import { repo } from '@/data/repo'
import type { Deck } from '@/data/types'

interface DeckSettingsProps {
  deckId: string
  onDeleted: () => void
  onBack: () => void
}

const RETENTION_OPTIONS = [0.8, 0.85, 0.9, 0.93, 0.95, 0.97]

// Would this parent choice create a cycle (deck becomes its own ancestor)?
async function isDescendant(candidateParentId: string, deckId: string, allDecks: Deck[]): Promise<boolean> {
  let cur: string | null = candidateParentId
  const byId = new Map(allDecks.map(d => [d.id, d]))
  const seen = new Set<string>()
  while (cur) {
    if (cur === deckId) return true
    if (seen.has(cur)) return false
    seen.add(cur)
    cur = byId.get(cur)?.parentId ?? null
  }
  return false
}

export default function DeckSettings({ deckId, onDeleted, onBack }: DeckSettingsProps) {
  const [deck, setDeck] = useState<Deck | null>(null)
  const [allDecks, setAllDecks] = useState<Deck[]>([])
  const [name, setName] = useState('')
  const [parentId, setParentId] = useState<string>('')
  const [newPerDay, setNewPerDay] = useState(20)
  const [desiredRetention, setDesiredRetention] = useState(0.9)
  const [saved, setSaved] = useState(false)
  const [invalidParent, setInvalidParent] = useState(false)

  const load = useCallback(async () => {
    const [d, decks] = await Promise.all([
      db.decks.get(deckId),
      db.decks.filter(x => x.deletedAt == null).toArray(),
    ])
    if (!d) return
    setDeck(d)
    setAllDecks(decks)
    setName(d.name)
    setParentId(d.parentId ?? '')
    setNewPerDay(d.newPerDay)
    setDesiredRetention(d.desiredRetention)
  }, [deckId])

  useEffect(() => {
    load()
  }, [load])

  const save = async () => {
    if (!deck) return
    const trimmed = name.trim()
    if (!trimmed) return

    const nextParentId = parentId || null
    if (nextParentId) {
      const cycle = await isDescendant(nextParentId, deckId, allDecks)
      if (cycle) {
        setInvalidParent(true)
        return
      }
    }
    setInvalidParent(false)

    await repo.put('decks', {
      ...deck,
      name: trimmed,
      parentId: nextParentId,
      newPerDay: Math.max(0, Math.round(newPerDay)),
      desiredRetention,
    })
    setSaved(true)
    setTimeout(() => setSaved(false), 1200)
    load()
  }

  const remove = async () => {
    if (!deck) return
    if (!window.confirm(`Delete "${deck.name}"? Its cards stay saved but won't appear in study.`)) return
    await repo.softDelete('decks', deck.id)
    onDeleted()
  }

  if (!deck) {
    return (
      <div className="screen">
        <div className="stub">Loading…</div>
      </div>
    )
  }

  const parentOptions = allDecks.filter(d => d.id !== deckId)

  return (
    <div className="screen">
      <div className="form-field">
        <label htmlFor="deck-name">Deck name</label>
        <input
          id="deck-name"
          className="field"
          value={name}
          onChange={e => setName(e.target.value)}
        />
      </div>

      <div className="form-field">
        <label htmlFor="deck-parent">Nest under</label>
        <select
          id="deck-parent"
          className="editor-type-select"
          value={parentId}
          onChange={e => setParentId(e.target.value)}
        >
          <option value="">No parent (top level)</option>
          {parentOptions.map(d => (
            <option key={d.id} value={d.id}>{d.name}</option>
          ))}
        </select>
        {invalidParent && <div className="hint" style={{ color: 'var(--danger)' }}>Can't nest a deck under its own descendant.</div>}
      </div>

      <div className="form-field">
        <label htmlFor="deck-new-per-day">New cards per day</label>
        <input
          id="deck-new-per-day"
          className="field"
          type="number"
          min={0}
          value={newPerDay}
          onChange={e => setNewPerDay(Number(e.target.value))}
        />
      </div>

      <div className="form-field">
        <label htmlFor="deck-retention">Desired retention</label>
        <div className="range-row">
          <select
            id="deck-retention"
            className="editor-type-select"
            value={desiredRetention}
            onChange={e => setDesiredRetention(Number(e.target.value))}
          >
            {RETENTION_OPTIONS.map(r => (
              <option key={r} value={r}>{Math.round(r * 100)}%</option>
            ))}
          </select>
          <span className="range-value">{Math.round(desiredRetention * 100)}%</span>
        </div>
        <div className="hint">Higher retention means more frequent reviews.</div>
      </div>

      <button className="btn btn-accent" onClick={save}>
        {saved ? 'Saved' : 'Save changes'}
      </button>

      <button className="btn" onClick={onBack}>
        Back to editor
      </button>

      <div className="danger-zone">
        <div className="section-title">Danger zone</div>
        <div className="hint">Deleting a deck hides it and its due cards, but keeps the notes so nothing is lost.</div>
        <button className="btn btn-danger" onClick={remove}>
          Delete deck
        </button>
      </div>
    </div>
  )
}
