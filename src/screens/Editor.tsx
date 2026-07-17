import { useEffect, useRef, useState } from 'react'
import { v4 as uuid } from 'uuid'
import { db } from '@/data/db'
import { repo } from '@/data/repo'
import { syncCardsWithNote } from '@/engine/cards-from-note'
import type { Deck, Note, NoteType } from '@/data/types'

interface EditorProps {
  deckId: string
  onOpenSettings: (deckId: string) => void
}

interface UIRow {
  id: string
  persisted: boolean
  type: NoteType
  term: string
  definition: string
  example: string
  hint: string
  imageId?: string
}

const TYPE_LABELS: Record<NoteType, string> = {
  basic: 'Basic',
  basic_reversed: 'Basic + reversed',
  cloze: 'Cloze',
}

function blankRow(): UIRow {
  return { id: uuid(), persisted: false, type: 'basic', term: '', definition: '', example: '', hint: '' }
}

function noteFromRow(deckId: string, row: UIRow): Note {
  const fields: Note['fields'] = { term: row.term, definition: row.definition }
  if (row.example.trim()) fields.example = row.example
  if (row.hint.trim()) fields.hint = row.hint
  if (row.imageId) fields.imageId = row.imageId
  return { id: row.id, deckId, type: row.type, fields, tags: [], deletedAt: null }
}

function rowFromNote(note: Note): UIRow {
  return {
    id: note.id,
    persisted: true,
    type: note.type,
    term: note.fields.term,
    definition: note.fields.definition,
    example: note.fields.example ?? '',
    hint: note.fields.hint ?? '',
    imageId: note.fields.imageId,
  }
}

// First delimiter found, tab or comma, splits term from definition. No delimiter -> whole line is the term.
function parseDelimitedLine(line: string): { term: string; definition: string } {
  const tabIdx = line.indexOf('\t')
  const commaIdx = line.indexOf(',')
  const candidates = [tabIdx, commaIdx].filter(i => i !== -1)
  if (candidates.length === 0) return { term: line.trim(), definition: '' }
  const idx = Math.min(...candidates)
  return { term: line.slice(0, idx).trim(), definition: line.slice(idx + 1).trim() }
}

async function hashBlob(blob: Blob): Promise<string> {
  const buf = await blob.arrayBuffer()
  const digest = await crypto.subtle.digest('SHA-256', buf)
  return Array.from(new Uint8Array(digest)).map(b => b.toString(16).padStart(2, '0')).join('')
}

function GearIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="12" cy="12" r="3" />
      <path d="M19.4 15a1.7 1.7 0 0 0 .34 1.87l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.7 1.7 0 0 0-1.87-.34 1.7 1.7 0 0 0-1.04 1.56V21a2 2 0 0 1-4 0v-.09A1.7 1.7 0 0 0 9 19.35a1.7 1.7 0 0 0-1.87.34l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06A1.7 1.7 0 0 0 4.65 15a1.7 1.7 0 0 0-1.56-1.04H3a2 2 0 0 1 0-4h.09A1.7 1.7 0 0 0 4.65 9a1.7 1.7 0 0 0-.34-1.87l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06A1.7 1.7 0 0 0 9 4.65a1.7 1.7 0 0 0 1.04-1.56V3a2 2 0 0 1 4 0v.09A1.7 1.7 0 0 0 15 4.65a1.7 1.7 0 0 0 1.87-.34l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06A1.7 1.7 0 0 0 19.35 9a1.7 1.7 0 0 0 1.56 1.04H21a2 2 0 0 1 0 4h-.09a1.7 1.7 0 0 0-1.51 1.04z" />
    </svg>
  )
}

function TrashIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
      <path d="M3 6h18" />
      <path d="M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2m3 0-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6" />
    </svg>
  )
}

export default function Editor({ deckId, onOpenSettings }: EditorProps) {
  const [deck, setDeck] = useState<Deck | null>(null)
  const [rows, setRows] = useState<UIRow[]>([])
  const [dropTarget, setDropTarget] = useState<string | null>(null)
  const termRefs = useRef<Map<string, HTMLInputElement>>(new Map())
  const focusRowIdRef = useRef<string | null>(null)

  useEffect(() => {
    ;(async () => {
      const [d, notes] = await Promise.all([
        db.decks.get(deckId),
        db.notes.filter(n => n.deckId === deckId && n.deletedAt == null).toArray(),
      ])
      setDeck(d ?? null)
      setRows([...notes.map(rowFromNote), blankRow()])
    })()
  }, [deckId])

  useEffect(() => {
    if (!focusRowIdRef.current) return
    const el = termRefs.current.get(focusRowIdRef.current)
    if (el) {
      el.focus()
      focusRowIdRef.current = null
    }
  }, [rows])

  const ensureTrailingBlank = (list: UIRow[]): UIRow[] => {
    if (list.length === 0 || list[list.length - 1].persisted) return [...list, blankRow()]
    return list
  }

  const updateRow = (id: string, patch: Partial<UIRow>) => {
    setRows(prev => prev.map(r => (r.id === id ? { ...r, ...patch } : r)))
  }

  const commitRow = async (id: string) => {
    const row = rows.find(r => r.id === id)
    if (!row) return
    if (!row.term.trim()) return // nothing to save yet
    const note = noteFromRow(deckId, row)
    await repo.put('notes', note)
    await syncCardsWithNote(note)
    if (!row.persisted) {
      setRows(prev => ensureTrailingBlank(prev.map(r => (r.id === id ? { ...r, persisted: true } : r))))
    }
  }

  const deleteRow = async (row: UIRow) => {
    if (!row.persisted) {
      setRows(prev => prev.filter(r => r.id !== row.id))
      return
    }
    if (!window.confirm(`Delete this note ("${row.term}")? Its cards stay saved but won't appear in study.`)) return
    await repo.softDelete('notes', row.id)
    setRows(prev => prev.filter(r => r.id !== row.id))
  }

  const addBlankRow = () => {
    setRows(prev => {
      const next = ensureTrailingBlank(prev)
      // if the list already ends with a blank draft row, just focus it instead of adding another
      focusRowIdRef.current = next[next.length - 1].id
      return next
    })
  }

  const onHintTab = (e: React.KeyboardEvent, rowIndex: number, rowId: string) => {
    if (e.key !== 'Tab' || e.shiftKey) return
    if (rowIndex !== rows.length - 1) return
    e.preventDefault()
    ;(async () => {
      await commitRow(rowId)
      setRows(prev => {
        const next = ensureTrailingBlank(prev)
        const last = next[next.length - 1]
        focusRowIdRef.current = last.id
        return next
      })
    })()
  }

  const onTermPaste = async (e: React.ClipboardEvent<HTMLInputElement>, row: UIRow) => {
    if (row.persisted || row.term.trim() !== '') return // let a normal single-cell paste happen
    const text = e.clipboardData.getData('text')
    if (!text) return
    e.preventDefault()

    const lines = text.split(/\r\n|\r|\n/).filter(l => l.trim() !== '')
    if (lines.length === 0) return
    const parsed = lines.map(parseDelimitedLine).filter(p => p.term)
    if (parsed.length === 0) return

    const newRows: UIRow[] = []
    for (const p of parsed) {
      const newRow: UIRow = { ...blankRow(), term: p.term, definition: p.definition, persisted: true }
      const note = noteFromRow(deckId, newRow)
      await repo.put('notes', note)
      await syncCardsWithNote(note)
      newRows.push(newRow)
    }

    setRows(prev => {
      const idx = prev.findIndex(r => r.id === row.id)
      const next = idx === -1 ? [...prev, ...newRows] : [...prev.slice(0, idx), ...newRows, ...prev.slice(idx + 1)]
      return ensureTrailingBlank(next)
    })
  }

  const onRowDrop = async (e: React.DragEvent, row: UIRow) => {
    e.preventDefault()
    setDropTarget(null)
    const file = e.dataTransfer.files?.[0]
    if (!file || !file.type.startsWith('image/')) return

    const hash = await hashBlob(file)
    await repo.put('media', { id: hash, hash, blob: file, mime: file.type, deletedAt: null })

    updateRow(row.id, { imageId: hash })
    if (row.term.trim() || row.persisted) {
      await commitRow(row.id)
    }
  }

  if (!deck) {
    return (
      <div className="screen">
        <div className="stub">Loading…</div>
      </div>
    )
  }

  return (
    <div className="screen">
      <div className="editor-header">
        <div className="deck-name">{deck.name}</div>
        <button className="nav-icon-btn" onClick={() => onOpenSettings(deckId)} aria-label="Deck settings" data-tip="Deck settings">
          <GearIcon />
        </button>
      </div>
      <div className="editor-hint">
        Tab from the last field to add a row. Paste multiple lines into an empty term cell to bulk add. Drop an image onto a row to attach it.
      </div>

      <div className="editor-table-wrap">
        <table className="editor-table">
          <thead>
            <tr>
              <th>Term</th>
              <th>Definition</th>
              <th>Example</th>
              <th>Hint</th>
              <th>Type</th>
              <th>Image</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {rows.map((row, rowIndex) => (
              <tr
                key={row.id}
                className={dropTarget === row.id ? 'editor-row-drop' : undefined}
                onDragOver={e => {
                  e.preventDefault()
                  setDropTarget(row.id)
                }}
                onDragLeave={() => setDropTarget(t => (t === row.id ? null : t))}
                onDrop={e => onRowDrop(e, row)}
              >
                <td>
                  <input
                    ref={el => {
                      if (el) termRefs.current.set(row.id, el)
                      else termRefs.current.delete(row.id)
                    }}
                    className="editor-cell-input"
                    value={row.term}
                    placeholder="Term"
                    onChange={e => updateRow(row.id, { term: e.target.value })}
                    onBlur={() => commitRow(row.id)}
                    onPaste={e => onTermPaste(e, row)}
                  />
                </td>
                <td>
                  <input
                    className="editor-cell-input"
                    value={row.definition}
                    placeholder="Definition"
                    onChange={e => updateRow(row.id, { definition: e.target.value })}
                    onBlur={() => commitRow(row.id)}
                  />
                </td>
                <td>
                  <input
                    className="editor-cell-input"
                    value={row.example}
                    placeholder="Example"
                    onChange={e => updateRow(row.id, { example: e.target.value })}
                    onBlur={() => commitRow(row.id)}
                  />
                </td>
                <td>
                  <input
                    className="editor-cell-input"
                    value={row.hint}
                    placeholder="Hint"
                    onChange={e => updateRow(row.id, { hint: e.target.value })}
                    onBlur={() => commitRow(row.id)}
                    onKeyDown={e => onHintTab(e, rowIndex, row.id)}
                  />
                </td>
                <td>
                  <select
                    className="editor-type-select"
                    value={row.type}
                    onChange={e => {
                      const type = e.target.value as NoteType
                      updateRow(row.id, { type })
                      if (row.persisted || row.term.trim()) {
                        // commit with the new type once state has flushed
                        setTimeout(() => commitRow(row.id), 0)
                      }
                    }}
                  >
                    {(Object.keys(TYPE_LABELS) as NoteType[]).map(t => (
                      <option key={t} value={t}>{TYPE_LABELS[t]}</option>
                    ))}
                  </select>
                </td>
                <td>
                  {row.imageId ? (
                    <ThumbImage mediaId={row.imageId} />
                  ) : (
                    <span className="hint">Drop image</span>
                  )}
                </td>
                <td>
                  {row.persisted && (
                    <button className="editor-delete-btn" onClick={() => deleteRow(row)} aria-label="Delete note" data-tip="Delete">
                      <TrashIcon />
                    </button>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        <button className="editor-add-row" onClick={addBlankRow}>
          + Add row
        </button>
      </div>
    </div>
  )
}

function ThumbImage({ mediaId }: { mediaId: string }) {
  const [url, setUrl] = useState<string | null>(null)

  useEffect(() => {
    let objectUrl: string | null = null
    db.media.get(mediaId).then(media => {
      if (media?.blob) {
        objectUrl = URL.createObjectURL(media.blob)
        setUrl(objectUrl)
      }
    })
    return () => {
      if (objectUrl) URL.revokeObjectURL(objectUrl)
    }
  }, [mediaId])

  if (!url) return null
  return <img className="editor-thumb" src={url} alt="" />
}
