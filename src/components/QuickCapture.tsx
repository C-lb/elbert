import { useEffect, useRef, useState } from 'react'
import { v4 as uuid } from 'uuid'
import { db } from '@/data/db'
import { repo } from '@/data/repo'
import { syncCardsWithNote } from '@/engine/cards-from-note'
import type { Note } from '@/data/types'

interface QuickCaptureProps {
  onClose: () => void
  onSaved: () => void
}

const INBOX_DECK_NAME = 'Inbox'

async function findOrCreateInbox(): Promise<string> {
  const existing = await db.decks.filter(d => d.name === INBOX_DECK_NAME && d.deletedAt == null).first()
  if (existing) return existing.id
  const id = uuid()
  await repo.put('decks', {
    id,
    name: INBOX_DECK_NAME,
    parentId: null,
    newPerDay: 20,
    desiredRetention: 0.9,
    deletedAt: null,
  })
  return id
}

function CloseIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round">
      <path d="M18 6L6 18M6 6l12 12" />
    </svg>
  )
}

export default function QuickCapture({ onClose, onSaved }: QuickCaptureProps) {
  const [term, setTerm] = useState('')
  const [definition, setDefinition] = useState('')
  const [saving, setSaving] = useState(false)
  const termRef = useRef<HTMLInputElement>(null)

  useEffect(() => {
    termRef.current?.focus()
  }, [])

  const save = async () => {
    const t = term.trim()
    const d = definition.trim()
    if (!t || saving) return
    setSaving(true)
    try {
      const deckId = await findOrCreateInbox()
      const note: Note = {
        id: uuid(),
        deckId,
        type: 'basic',
        fields: { term: t, definition: d },
        tags: [],
        deletedAt: null,
      }
      await repo.put('notes', note)
      await syncCardsWithNote(note)
      onSaved()
    } finally {
      setSaving(false)
    }
  }

  const onKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Escape') onClose()
    if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) save()
  }

  return (
    <div className="sheet-backdrop" onClick={onClose}>
      <div className="sheet" onClick={e => e.stopPropagation()} onKeyDown={onKeyDown}>
        <div className="sheet-header">
          <div className="sheet-title">Quick capture</div>
          <button className="sheet-close" onClick={onClose} aria-label="Close">
            <CloseIcon />
          </button>
        </div>

        <div className="form-field">
          <label htmlFor="qc-term">Term</label>
          <input
            id="qc-term"
            ref={termRef}
            className="field"
            value={term}
            onChange={e => setTerm(e.target.value)}
            placeholder="What do you want to remember?"
          />
        </div>

        <div className="form-field">
          <label htmlFor="qc-definition">Definition</label>
          <input
            id="qc-definition"
            className="field"
            value={definition}
            onChange={e => setDefinition(e.target.value)}
            placeholder="Answer, translation, or meaning"
          />
        </div>

        <div className="hint">Saves to your Inbox deck.</div>

        <button className="btn btn-accent btn-block" onClick={save} disabled={!term.trim() || saving}>
          {saving ? 'Saving…' : 'Save card'}
        </button>
      </div>
    </div>
  )
}
