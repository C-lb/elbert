import type { NoteType } from '@/data/types'

export interface DraftRow {
  id: string
  checked: boolean
  type: NoteType
  term: string
  definition: string
  example?: string
  hint?: string
}

interface DraftListProps {
  drafts: DraftRow[]
  onChange: (drafts: DraftRow[]) => void
}

const TYPE_LABELS: Record<NoteType, string> = {
  basic: 'Basic',
  basic_reversed: 'Basic + reversed',
  cloze: 'Cloze',
}

export default function DraftList({ drafts, onChange }: DraftListProps) {
  const patch = (id: string, fields: Partial<DraftRow>) => {
    onChange(drafts.map(d => (d.id === id ? { ...d, ...fields } : d)))
  }

  return (
    <div className="draft-list">
      {drafts.map(d => (
        <div className={`draft-row${d.checked ? '' : ' draft-row-off'}`} key={d.id}>
          <div className="draft-row-head">
            <label className="draft-checkbox">
              <input
                type="checkbox"
                checked={d.checked}
                onChange={e => patch(d.id, { checked: e.target.checked })}
              />
            </label>
            <span className="draft-badge">{TYPE_LABELS[d.type]}</span>
          </div>
          <input
            className="field draft-field"
            value={d.term}
            onChange={e => patch(d.id, { term: e.target.value })}
            placeholder="Term"
            aria-label="Term"
          />
          <input
            className="field draft-field"
            value={d.definition}
            onChange={e => patch(d.id, { definition: e.target.value })}
            placeholder="Definition"
            aria-label="Definition"
          />
        </div>
      ))}
    </div>
  )
}
