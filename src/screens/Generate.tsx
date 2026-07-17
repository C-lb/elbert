import { useEffect, useState } from 'react'
import { v4 as uuid } from 'uuid'
import { db } from '@/data/db'
import { repo } from '@/data/repo'
import { getSettings } from '@/lib/settings'
import { cardsForNote } from '@/engine/cards-from-note'
import DraftList, { type DraftRow } from '@/screens/DraftList'
import { isUnmarkedCloze } from '@/engine/draft'
import {
  CHUNK_BASE64_BUDGET,
  PageTooLargeError,
  projectedBase64Length,
  splitCountAcrossChunks,
  splitPdfIntoChunks,
} from '@/lib/pdf-chunks'
import type { Deck, Note, NoteType } from '@/data/types'

type Mode = 'text' | 'pdf'
type Style = 'basic' | 'basic_reversed' | 'cloze' | 'mix'

const MAX_PDF_BYTES = 10 * 1024 * 1024

interface Draft {
  type: NoteType
  fields: { term: string; definition: string; example?: string; hint?: string }
}

function readBlobAsBase64(blob: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader()
    reader.onload = () => {
      const result = reader.result as string
      resolve(result.slice(result.indexOf(',') + 1))
    }
    reader.onerror = () => reject(reader.error)
    reader.readAsDataURL(blob)
  })
}

/**
 * Wraps raw PDF bytes for FileReader. The cast narrows Uint8Array<ArrayBufferLike>
 * to the ArrayBuffer-backed view BlobPart requires; nothing here uses SharedArrayBuffer.
 */
function bytesToBlob(bytes: Uint8Array): Blob {
  return new Blob([bytes as Uint8Array<ArrayBuffer>], { type: 'application/pdf' })
}

/** "part 3" or "parts 2, 3 and 5". */
function formatParts(parts: number[]): string {
  if (parts.length === 1) return `part ${parts[0]}`
  const head = parts.slice(0, -1).join(', ')
  return `parts ${head} and ${parts[parts.length - 1]}`
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
  const [pdfBytes, setPdfBytes] = useState<Uint8Array | null>(null)
  const [pdfName, setPdfName] = useState<string | null>(null)
  const [pdfError, setPdfError] = useState<string | null>(null)
  const [style, setStyle] = useState<Style>('mix')
  const [count, setCount] = useState(20)

  const [decks, setDecks] = useState<Deck[] | null>(null)
  const [targetDeckId, setTargetDeckId] = useState('')
  const [newDeckName, setNewDeckName] = useState('')

  const [generating, setGenerating] = useState(false)
  const [genProgress, setGenProgress] = useState<{ current: number; total: number } | null>(null)
  const [genError, setGenError] = useState<string | null>(null)
  const [rows, setRows] = useState<DraftRow[] | null>(null)
  const [approving, setApproving] = useState(false)
  const [toast, setToast] = useState<{ text: string; tone: 'success' | 'error' } | null>(null)

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
    setPdfBytes(null)
    if (file.size > MAX_PDF_BYTES) {
      setPdfError('That PDF is over 10MB. Try a smaller file.')
      return
    }
    setPdfName(file.name)
    setPdfBytes(new Uint8Array(await file.arrayBuffer()))
  }

  const canGenerate = (mode === 'text' ? text.trim().length > 0 : !!pdfBytes) && !generating

  const requestDrafts = async (
    syncKey: string,
    payload: { text?: string; pdfBase64?: string; count: number },
  ): Promise<{ ok: true; drafts: Draft[] } | { ok: false; error: string }> => {
    try {
      const res = await fetch('/api/generate', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'x-elbert-key': syncKey },
        body: JSON.stringify({ ...payload, style }),
      })
      const body = await res.json().catch(() => null)
      if (!res.ok) return { ok: false, error: body?.error || `Generation failed: ${res.status}` }
      return { ok: true, drafts: body.drafts ?? [] }
    } catch {
      return { ok: false, error: 'Network error, could not reach the server.' }
    }
  }

  const generate = async () => {
    if (!canGenerate) return
    setGenerating(true)
    setGenProgress(null)
    setGenError(null)
    setRows(null)
    try {
      const settings = await getSettings()

      // Single-request path: notes text, or a PDF whose whole base64 payload
      // fits one request under Vercel's body size limit.
      if (mode === 'text' || (pdfBytes && projectedBase64Length(pdfBytes.length) <= CHUNK_BASE64_BUDGET)) {
        const payload =
          mode === 'text'
            ? { text, count }
            : { pdfBase64: await readBlobAsBase64(bytesToBlob(pdfBytes!)), count }
        const result = await requestDrafts(settings.syncKey, payload)
        if (!result.ok) {
          setGenError(result.error)
          return
        }
        setRows(toRows(result.drafts))
        return
      }

      // Chunked path: split the PDF by pages so each request stays under the
      // platform body limit, then generate per chunk sequentially.
      let chunks
      try {
        chunks = await splitPdfIntoChunks(pdfBytes!)
      } catch (err) {
        setGenError(
          err instanceof PageTooLargeError
            ? 'A single page of this PDF is too large to upload, and pages cannot be split further. Try a smaller export.'
            : 'Could not read that PDF. Try re-exporting it.',
        )
        return
      }
      const counts = splitCountAcrossChunks(count, chunks.map(c => c.pageCount))
      const merged: Draft[] = []
      const failedParts: number[] = []
      for (let i = 0; i < chunks.length; i++) {
        setGenProgress({ current: i + 1, total: chunks.length })
        const pdfBase64 = await readBlobAsBase64(bytesToBlob(chunks[i].bytes))
        const result = await requestDrafts(settings.syncKey, { pdfBase64, count: counts[i] })
        if (result.ok) merged.push(...result.drafts)
        else failedParts.push(i + 1)
      }
      if (merged.length === 0) {
        setGenError('Generation failed for every part of the PDF. Try again.')
        return
      }
      setRows(toRows(merged))
      if (failedParts.length > 0) {
        setToast({
          text: `Generation failed for ${formatParts(failedParts)} of ${chunks.length}, kept the cards from the rest`,
          tone: 'error',
        })
      }
    } finally {
      setGenerating(false)
      setGenProgress(null)
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
    const checked = rows?.filter(r => r.checked) ?? []
    if (checked.length === 0 || approving) return
    // A cloze row with no {{c1::...}} marker would approve into a note with
    // zero cards (cardsForNote finds no ordinals to build). Skip those
    // instead of silently creating a dead note; DraftList already flags
    // them inline so this isn't a surprise by the time approve runs.
    const skipped = checked.filter(isUnmarkedCloze)
    const selected = checked.filter(r => !isUnmarkedCloze(r))
    if (selected.length === 0) return
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
      const approvedMsg = `Approved ${selected.length} card${selected.length === 1 ? '' : 's'}`
      const skippedMsg = skipped.length > 0 ? `, skipped ${skipped.length} cloze with no blanks` : ''
      setToast({ text: approvedMsg + skippedMsg, tone: 'success' })
      setRows(null)
      setText('')
      setPdfBytes(null)
      setPdfName(null)
      setNewDeckName('')
    } finally {
      setApproving(false)
    }
  }

  const checkedCount = rows?.filter(r => r.checked).length ?? 0
  const checkedSkippedCount = rows?.filter(r => r.checked && isUnmarkedCloze(r)).length ?? 0
  const checkedApprovableCount = checkedCount - checkedSkippedCount

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
                {genProgress ? `Generating ${genProgress.current}/${genProgress.total}` : 'Generating…'}
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
              disabled={checkedApprovableCount === 0 || approving || (!targetDeckId && !newDeckName.trim())}
            >
              {approving ? (
                <span className="btn-loading">
                  <span className="spinner" aria-hidden="true" />
                  Approving…
                </span>
              ) : (
                `Approve ${checkedApprovableCount} card${checkedApprovableCount === 1 ? '' : 's'}`
              )}
            </button>
          </div>
        </>
      )}

      {toast && <div className={`toast toast-${toast.tone}`}>{toast.text}</div>}
    </div>
  )
}
