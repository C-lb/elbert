import { useEffect, useState } from 'react'
import { v4 as uuid } from 'uuid'
import { db } from '@/data/db'
import { repo } from '@/data/repo'
import { getSettings } from '@/lib/settings'
import { cardsForNote } from '@/engine/cards-from-note'
import DraftList, { type DraftRow } from '@/screens/DraftList'
import type { Deck, Note, NoteType } from '@/data/types'

type Mode = 'text' | 'pdf'
type Style = 'basic' | 'basic_reversed' | 'cloze' | 'mix'

const MAX_PDF_BYTES = 10 * 1024 * 1024

interface Draft {
  type: NoteType
  fields: { term: string; definition: string; example?: string; hint?: string }
}

function readFileAsBase64(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader()
    reader.onload = () => {
      const result = reader.result as string
      resolve(result.slice(result.indexOf(',') + 1))
    }
    reader.onerror = () => reject(reader.error)
    reader.readAsDataURL(file)
  })
}

function toRows(drafts: Draft[]): DraftRow[] {
  return drafts.map(d => ({
    id: uuid(),
    checked: true,
    type: d.type,
    term: d.fields.term,
    definition: d.fields.definition,
    example: d.fields.example,
    hint: d.fields.hint,
  }))
}

export default function Generate() {
  const [mode, setMode] = useState<Mode>('text')
  const [text, setText] = useState('')
  const [pdfBase64, setPdfBase64] = useState<string | null>(null)
  const [pdfName, setPdfName] = useState<string | null>(null)
  const [pdfError, setPdfError] = useState<string | null>(null)
  const [style, setStyle] = useState<Style>('mix')
  const [count, setCount] = useState(20)

  const [decks, setDecks] = useState<Deck[] | null>(null)
  const [targetDeckId, setTargetDeckId] = useState('')
  const [newDeckName, setNewDeckName] = useState('')

  const [generating, setGenerating] = useState(false)
  const [genError, setGenError] = useState<string | null>(null)
  const [rows, setRows] = useState<DraftRow[] | null>(null)
  const [approving, setApproving] = useState(false)
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

  const onPdfFile = async (file: File) => {
    setPdfError(null)
    setPdfBase64(null)
    if (file.size > MAX_PDF_BYTES) {
      setPdfError('That PDF is over 10MB. Try a smaller file.')
      return
    }
    setPdfName(file.name)
    setPdfBase64(await readFileAsBase64(file))
  }

  const canGenerate = (mode === 'text' ? text.trim().length > 0 : !!pdfBase64) && !generating

  const generate = async () => {
    if (!canGenerate) return
    setGenerating(true)
    setGenError(null)
    setRows(null)
    try {
      const settings = await getSettings()
      const res = await fetch('/api/generate', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'x-elbert-key': settings.syncKey },
        body: JSON.stringify({
          text: mode === 'text' ? text : undefined,
          pdfBase64: mode === 'pdf' ? pdfBase64 : undefined,
          style,
          count,
        }),
      })
      const body = await res.json().catch(() => null)
      if (!res.ok) {
        setGenError(body?.error || `Generation failed: ${res.status}`)
        return
      }
      setRows(toRows(body.drafts ?? []))
    } catch {
      setGenError('Network error, could not reach the server.')
    } finally {
      setGenerating(false)
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

  const approve = async () => {
    const selected = rows?.filter(r => r.checked) ?? []
    if (selected.length === 0 || approving) return
    setApproving(true)
    try {
      const deckId = await resolveDeckId()
      if (!deckId) return
      for (const row of selected) {
        const fields: Note['fields'] = { term: row.term, definition: row.definition }
        if (row.example?.trim()) fields.example = row.example
        if (row.hint?.trim()) fields.hint = row.hint
        const note: Note = { id: uuid(), deckId, type: row.type, fields, tags: [], deletedAt: null }
        await repo.put('notes', note)
        for (const card of cardsForNote(note)) await repo.put('cards', card)
      }
      setToast(`Approved ${selected.length} card${selected.length === 1 ? '' : 's'}`)
      setRows(null)
      setText('')
      setPdfBase64(null)
      setPdfName(null)
      setNewDeckName('')
    } finally {
      setApproving(false)
    }
  }

  const checkedCount = rows?.filter(r => r.checked).length ?? 0

  return (
    <div className="screen">
      <div className="section-title">Generate cards</div>

      {rows === null && (
        <>
          <div className="import-tabs">
            <button
              className={`btn import-tab${mode === 'text' ? ' import-tab-active' : ''}`}
              onClick={() => setMode('text')}
            >
              Notes
            </button>
            <button
              className={`btn import-tab${mode === 'pdf' ? ' import-tab-active' : ''}`}
              onClick={() => setMode('pdf')}
            >
              PDF
            </button>
          </div>

          {mode === 'text' && (
            <div className="form-field">
              <label htmlFor="gen-text">Paste your notes</label>
              <textarea
                id="gen-text"
                className="field import-textarea"
                value={text}
                onChange={e => setText(e.target.value)}
                placeholder="Paste lecture notes, a textbook excerpt, anything to turn into cards"
                rows={8}
              />
            </div>
          )}

          {mode === 'pdf' && (
            <div className="form-field">
              <label htmlFor="gen-pdf-file">PDF file (up to 10MB)</label>
              <input
                id="gen-pdf-file"
                type="file"
                accept="application/pdf"
                className="field"
                onChange={e => {
                  const file = e.target.files?.[0]
                  if (file) onPdfFile(file)
                }}
              />
              {pdfName && !pdfError && <div className="hint">Selected {pdfName}</div>}
              {pdfError && <div className="hint import-error">{pdfError}</div>}
            </div>
          )}

          <div className="form-field">
            <label htmlFor="gen-style">Card style</label>
            <select
              id="gen-style"
              className="editor-type-select"
              value={style}
              onChange={e => setStyle(e.target.value as Style)}
            >
              <option value="mix">Mix (model decides)</option>
              <option value="basic">Basic</option>
              <option value="basic_reversed">Basic + reversed</option>
              <option value="cloze">Cloze</option>
            </select>
          </div>

          <div className="stepper-row">
            <div>
              <div className="stepper-label">Card count</div>
              <div className="hint">Target number of cards</div>
            </div>
            <div className="stepper-controls">
              <button
                type="button"
                className="btn stepper-btn"
                disabled={count <= 1}
                onClick={() => setCount(Math.max(1, count - 5))}
                aria-label="Fewer cards"
              >
                −
              </button>
              <span className="stepper-value">{count}</span>
              <button
                type="button"
                className="btn stepper-btn"
                disabled={count >= 50}
                onClick={() => setCount(Math.min(50, count + 5))}
                aria-label="More cards"
              >
                +
              </button>
            </div>
          </div>

          <div className="form-field">
            <label htmlFor="gen-deck-select">Target deck</label>
            <select
              id="gen-deck-select"
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

          {genError && <div className="hint import-error">{genError}</div>}

          <button className="btn btn-accent btn-block" onClick={generate} disabled={!canGenerate}>
            {generating ? (
              <span className="btn-loading">
                <span className="spinner" aria-hidden="true" />
                Generating…
              </span>
            ) : (
              'Generate cards'
            )}
          </button>
        </>
      )}

      {rows !== null && (
        <>
          <div className="hint">Nothing is saved yet. Review, edit, or uncheck cards before approving.</div>
          <DraftList drafts={rows} onChange={setRows} />
          <div className="draft-actions">
            <button className="btn" onClick={() => setRows(null)} disabled={approving}>
              Back
            </button>
            <button
              className="btn btn-accent btn-block"
              onClick={approve}
              disabled={checkedCount === 0 || approving || (!targetDeckId && !newDeckName.trim())}
            >
              {approving ? (
                <span className="btn-loading">
                  <span className="spinner" aria-hidden="true" />
                  Approving…
                </span>
              ) : (
                `Approve ${checkedCount} card${checkedCount === 1 ? '' : 's'}`
              )}
            </button>
          </div>
        </>
      )}

      {toast && <div className="toast toast-success">{toast}</div>}
    </div>
  )
}
