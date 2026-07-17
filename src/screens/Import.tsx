import { useEffect, useMemo, useState } from 'react'
import { v4 as uuid } from 'uuid'
import { db } from '@/data/db'
import { repo } from '@/data/repo'
import { cardsForNote } from '@/engine/cards-from-note'
import { parseCsv, type ImportRow } from '@/import/csv'
import type { Deck, Note } from '@/data/types'

type Mode = 'paste' | 'anki'

interface PreviewRow {
  term: string
  definition: string
  tags: string[]
}

const PREVIEW_LIMIT = 50

function fromCsvRows(rows: ImportRow[]): PreviewRow[] {
  return rows.map(r => ({ term: r.term, definition: r.definition, tags: [] }))
}

export default function Import() {
  const [mode, setMode] = useState<Mode>('paste')
  const [pasteText, setPasteText] = useState('')
  const [ankiRows, setAnkiRows] = useState<PreviewRow[] | null>(null)
  const [ankiError, setAnkiError] = useState<string | null>(null)
  const [ankiFileName, setAnkiFileName] = useState<string | null>(null)
  const [parsingAnki, setParsingAnki] = useState(false)

  const [decks, setDecks] = useState<Deck[] | null>(null)
  const [targetDeckId, setTargetDeckId] = useState<string>('')
  const [newDeckName, setNewDeckName] = useState('')

  const [importing, setImporting] = useState(false)
  const [toast, setToast] = useState<string | null>(null)

  useEffect(() => {
    db.decks.filter(d => d.deletedAt == null).toArray().then(list => {
      setDecks(list)
      if (list.length > 0) setTargetDeckId(list[0].id)
    })
  }, [])

  useEffect(() => {
    if (!toast) return
    const t = setTimeout(() => setToast(null), 2500)
    return () => clearTimeout(t)
  }, [toast])

  const pasteRows = useMemo(() => fromCsvRows(parseCsv(pasteText)), [pasteText])
  const rows = mode === 'paste' ? pasteRows : ankiRows ?? []

  const onAnkiFile = async (file: File) => {
    setParsingAnki(true)
    setAnkiError(null)
    setAnkiRows(null)
    setAnkiFileName(file.name)
    try {
      const { parseApkg } = await import('@/import/apkg')
      const buf = await file.arrayBuffer()
      const { notes } = await parseApkg(buf)
      const preview: PreviewRow[] = notes
        .map(n => {
          const [term = '', definition = '', ...rest] = n.fields.map(f => f.trim())
          const fullDefinition = rest.length > 0 ? [definition, ...rest].join(' · ') : definition
          return { term, definition: fullDefinition, tags: n.tags }
        })
        .filter(r => r.term)
      setAnkiRows(preview)
    } catch (e) {
      setAnkiError(e instanceof Error ? e.message : 'Could not read that file')
    } finally {
      setParsingAnki(false)
    }
  }

  const resolveDeckId = async (): Promise<string> => {
    const name = newDeckName.trim()
    if (name) {
      const id = uuid()
      const deck: Deck = { id, name, parentId: null, newPerDay: 20, desiredRetention: 0.9, deletedAt: null }
      await repo.put('decks', deck)
      return id
    }
    return targetDeckId
  }

  const runImport = async () => {
    if (rows.length === 0 || importing) return
    setImporting(true)
    try {
      const deckId = await resolveDeckId()
      if (!deckId) return
      for (const row of rows) {
        const note: Note = {
          id: uuid(),
          deckId,
          type: 'basic',
          fields: { term: row.term, definition: row.definition },
          tags: row.tags,
          deletedAt: null,
        }
        await repo.put('notes', note)
        for (const card of cardsForNote(note)) await repo.put('cards', card)
      }
      setToast(`Imported ${rows.length} card${rows.length === 1 ? '' : 's'}`)
      setPasteText('')
      setAnkiRows(null)
      setAnkiFileName(null)
      setNewDeckName('')
    } finally {
      setImporting(false)
    }
  }

  return (
    <div className="screen">
      <div className="section-title">Import</div>

      <div className="import-tabs">
        <button
          className={`btn import-tab${mode === 'paste' ? ' import-tab-active' : ''}`}
          onClick={() => setMode('paste')}
        >
          Paste text
        </button>
        <button
          className={`btn import-tab${mode === 'anki' ? ' import-tab-active' : ''}`}
          onClick={() => setMode('anki')}
        >
          Anki file
        </button>
      </div>

      {mode === 'paste' && (
        <div className="form-field">
          <label htmlFor="import-paste">Paste from Quizlet, a spreadsheet, or any tab/comma/semicolon list</label>
          <textarea
            id="import-paste"
            className="field import-textarea"
            value={pasteText}
            onChange={e => setPasteText(e.target.value)}
            placeholder={'term\tdefinition\nchat\tcat'}
            rows={8}
          />
        </div>
      )}

      {mode === 'anki' && (
        <div className="form-field">
          <label htmlFor="import-anki-file">Anki deck export (.apkg)</label>
          <input
            id="import-anki-file"
            type="file"
            accept=".apkg"
            className="field"
            onChange={e => {
              const file = e.target.files?.[0]
              if (file) onAnkiFile(file)
            }}
          />
          {parsingAnki && <div className="hint">Reading {ankiFileName}…</div>}
          {ankiError && <div className="hint import-error">{ankiError}</div>}
          <div className="hint">First field becomes the term, second the definition; extra fields are appended with " · ". Tags carry over.</div>
        </div>
      )}

      <div className="hint">Imported cards arrive as new: no review history or scheduling state yet.</div>

      {rows.length > 0 && (
        <div className="import-preview">
          <div className="section-title">Preview ({rows.length})</div>
          <div className="import-preview-table">
            {rows.slice(0, PREVIEW_LIMIT).map((r, i) => (
              <div className="import-preview-row" key={i}>
                <div className="import-preview-term">{r.term}</div>
                <div className="import-preview-def">{r.definition}</div>
              </div>
            ))}
          </div>
          {rows.length > PREVIEW_LIMIT && <div className="hint">+{rows.length - PREVIEW_LIMIT} more</div>}
        </div>
      )}

      <div className="form-field">
        <label htmlFor="import-deck-select">Target deck</label>
        <select
          id="import-deck-select"
          className="editor-type-select"
          value={targetDeckId}
          disabled={!!newDeckName.trim()}
          onChange={e => setTargetDeckId(e.target.value)}
        >
          {decks === null && <option value="">Loading…</option>}
          {decks?.map(d => (
            <option key={d.id} value={d.id}>
              {d.name}
            </option>
          ))}
        </select>
        <input
          className="field"
          placeholder="Or create a new deck"
          value={newDeckName}
          onChange={e => setNewDeckName(e.target.value)}
        />
      </div>

      <button
        className="btn btn-accent btn-block"
        onClick={runImport}
        disabled={importing || rows.length === 0 || (!targetDeckId && !newDeckName.trim())}
      >
        {importing ? 'Importing…' : `Import ${rows.length || ''} card${rows.length === 1 ? '' : 's'}`}
      </button>

      {toast && <div className="toast toast-success">{toast}</div>}
    </div>
  )
}
