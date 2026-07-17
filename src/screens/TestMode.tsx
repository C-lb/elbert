import { useEffect, useState } from 'react'
import { db } from '@/data/db'
import { generateTest, gradePaper, type TestAnswers, type TestCounts, type TestPaper, type TestResult } from '@/engine/testgen'
import type { Note } from '@/data/types'

interface TestModeProps {
  deckId?: string
}

type Phase = 'loading' | 'setup' | 'paper' | 'results'

const SECTION_LABELS: Record<'written' | 'mc' | 'tf' | 'matching', string> = {
  written: 'Written',
  mc: 'Multiple choice',
  tf: 'True or false',
  matching: 'Matching',
}

function emptyAnswers(): TestAnswers {
  return { written: {}, mc: {}, tf: {}, matching: {} }
}

function Stepper({
  label,
  value,
  max,
  onChange,
}: {
  label: string
  value: number
  max: number
  onChange: (v: number) => void
}) {
  return (
    <div className="stepper-row">
      <div>
        <div className="stepper-label">{label}</div>
        <div className="hint">{max} available</div>
      </div>
      <div className="stepper-controls">
        <button
          type="button"
          className="btn stepper-btn"
          disabled={value <= 0}
          onClick={() => onChange(Math.max(0, value - 1))}
          aria-label={`Fewer ${label} questions`}
        >
          −
        </button>
        <span className="stepper-value">{value}</span>
        <button
          type="button"
          className="btn stepper-btn"
          disabled={value >= max}
          onClick={() => onChange(Math.min(max, value + 1))}
          aria-label={`More ${label} questions`}
        >
          +
        </button>
      </div>
    </div>
  )
}

export default function TestMode({ deckId }: TestModeProps) {
  const [phase, setPhase] = useState<Phase>('loading')
  const [notes, setNotes] = useState<Note[]>([])
  const [counts, setCounts] = useState<TestCounts>({ written: 0, mc: 0, tf: 0, matching: 0 })
  const [paper, setPaper] = useState<TestPaper | null>(null)
  const [answers, setAnswers] = useState<TestAnswers>(emptyAnswers())
  const [result, setResult] = useState<TestResult | null>(null)
  const [selectedTerm, setSelectedTerm] = useState<string | null>(null)

  useEffect(() => {
    let cancelled = false
    ;(async () => {
      const loaded = await db.notes.filter(n => n.deletedAt == null && (!deckId || n.deckId === deckId)).toArray()
      if (cancelled) return
      setNotes(loaded)
      const n = loaded.length
      setCounts({
        written: Math.min(5, n),
        mc: Math.min(5, n),
        tf: Math.min(5, n),
        matching: Math.min(5, n),
      })
      setPhase('setup')
    })()
    return () => {
      cancelled = true
    }
  }, [deckId])

  const start = () => {
    const rng = () => Math.random()
    const generated = generateTest(notes, counts, rng)
    setPaper(generated)
    setAnswers(emptyAnswers())
    setSelectedTerm(null)
    setPhase('paper')
  }

  const submit = () => {
    if (!paper) return
    setResult(gradePaper(paper, answers))
    setPhase('results')
  }

  const setWritten = (id: string, value: string) => {
    setAnswers(a => ({ ...a, written: { ...a.written, [id]: value } }))
  }
  const setMc = (id: string, index: number) => {
    setAnswers(a => ({ ...a, mc: { ...a.mc, [id]: index } }))
  }
  const setTf = (id: string, value: boolean) => {
    setAnswers(a => ({ ...a, tf: { ...a.tf, [id]: value } }))
  }
  const pairMatch = (noteId: string, definition: string) => {
    setAnswers(a => ({ ...a, matching: { ...a.matching, [noteId]: definition } }))
    setSelectedTerm(null)
  }

  if (phase === 'loading') {
    return (
      <div className="screen">
        <div className="stub">Loading deck…</div>
      </div>
    )
  }

  if (notes.length === 0) {
    return (
      <div className="screen">
        <div className="stub">No notes in this deck to test on yet.</div>
        <a className="btn btn-block" href="#/">Back home</a>
      </div>
    )
  }

  if (phase === 'setup') {
    const total = counts.written + counts.mc + counts.tf + counts.matching
    return (
      <div className="screen">
        <div className="section-title">Build your test</div>
        <Stepper label="Written" value={counts.written} max={notes.length} onChange={v => setCounts(c => ({ ...c, written: v }))} />
        <Stepper label="Multiple choice" value={counts.mc} max={notes.length} onChange={v => setCounts(c => ({ ...c, mc: v }))} />
        <Stepper label="True or false" value={counts.tf} max={notes.length} onChange={v => setCounts(c => ({ ...c, tf: v }))} />
        <Stepper label="Matching" value={counts.matching} max={notes.length} onChange={v => setCounts(c => ({ ...c, matching: v }))} />
        <button className="btn btn-accent btn-block" disabled={total === 0} onClick={start}>
          Start test
        </button>
      </div>
    )
  }

  if (phase === 'paper' && paper) {
    const canSubmit =
      paper.written.length + paper.mc.length + paper.tf.length + (paper.matching?.pairs.length ?? 0) > 0
    return (
      <div className="screen test-paper">
        {paper.written.length > 0 && (
          <div className="test-section">
            <div className="section-title">{SECTION_LABELS.written}</div>
            {paper.written.map((q, i) => (
              <div key={q.id} className="form-field">
                <label htmlFor={q.id}>{i + 1}. {q.prompt}</label>
                <input
                  id={q.id}
                  className="field"
                  value={answers.written[q.id] ?? ''}
                  onChange={e => setWritten(q.id, e.target.value)}
                  placeholder="Your answer"
                />
              </div>
            ))}
          </div>
        )}

        {paper.mc.length > 0 && (
          <div className="test-section">
            <div className="section-title">{SECTION_LABELS.mc}</div>
            {paper.mc.map((q, i) => (
              <div key={q.id} className="test-question">
                <div className="stepper-label">{i + 1}. {q.prompt}</div>
                <div className="learn-choices">
                  {q.options.map((opt, oi) => (
                    <button
                      key={oi}
                      type="button"
                      className={`learn-choice ${answers.mc[q.id] === oi ? 'learn-choice-correct' : ''}`}
                      onClick={() => setMc(q.id, oi)}
                    >
                      {opt}
                    </button>
                  ))}
                </div>
              </div>
            ))}
          </div>
        )}

        {paper.tf.length > 0 && (
          <div className="test-section">
            <div className="section-title">{SECTION_LABELS.tf}</div>
            {paper.tf.map((q, i) => (
              <div key={q.id} className="test-question">
                <div className="stepper-label">
                  {i + 1}. {q.term} = {q.definition}?
                </div>
                <div className="learn-close-actions">
                  <button
                    type="button"
                    className={`btn ${answers.tf[q.id] === true ? 'btn-accent' : ''}`}
                    onClick={() => setTf(q.id, true)}
                  >
                    True
                  </button>
                  <button
                    type="button"
                    className={`btn ${answers.tf[q.id] === false ? 'btn-accent' : ''}`}
                    onClick={() => setTf(q.id, false)}
                  >
                    False
                  </button>
                </div>
              </div>
            ))}
          </div>
        )}

        {paper.matching && (
          <div className="test-section">
            <div className="section-title">{SECTION_LABELS.matching}</div>
            <div className="hint">Tap a term, then tap its matching definition.</div>
            <div className="match-columns">
              <div className="match-col">
                {paper.matching.pairs.map(p => {
                  const paired = answers.matching[p.noteId]
                  return (
                    <button
                      key={p.noteId}
                      type="button"
                      className={`match-item ${selectedTerm === p.noteId ? 'match-item-selected' : ''} ${paired ? 'match-item-paired' : ''}`}
                      onClick={() => setSelectedTerm(selectedTerm === p.noteId ? null : p.noteId)}
                    >
                      <div>{p.term}</div>
                      {paired && <div className="hint">{paired}</div>}
                    </button>
                  )
                })}
              </div>
              <div className="match-col">
                {paper.matching.definitions.map((d, di) => (
                  <button
                    key={di}
                    type="button"
                    className="match-item"
                    disabled={!selectedTerm}
                    onClick={() => selectedTerm && pairMatch(selectedTerm, d)}
                  >
                    {d}
                  </button>
                ))}
              </div>
            </div>
          </div>
        )}

        <button className="btn btn-accent btn-block" disabled={!canSubmit} onClick={submit}>
          Submit test
        </button>
      </div>
    )
  }

  if (phase === 'results' && result) {
    return (
      <div className="screen">
        <div className="study-done">
          <div className="due-number">{result.percent}%</div>
          <div className="due-label">
            {result.correctCount} of {result.totalCount} correct
          </div>
        </div>

        <div className="test-section">
          <div className="section-title">By section</div>
          {result.sections
            .filter(s => s.total > 0)
            .map(s => (
              <div key={s.type} className="range-row">
                <span>{SECTION_LABELS[s.type]}</span>
                <span className="range-value">{s.correct} / {s.total}</span>
              </div>
            ))}
        </div>

        {result.weakest.length > 0 && (
          <div className="test-section">
            <div className="section-title">Needs work</div>
            <div className="weak-list">
              {result.weakest.map((w, i) => (
                <div key={`${w.noteId}-${i}`} className="weak-item">
                  <div className="stepper-label">{w.term}</div>
                  <div className="hint">Correct: {w.expected}</div>
                  {w.given && <div className="hint">Your answer: {w.given}</div>}
                </div>
              ))}
            </div>
          </div>
        )}

        <a className="btn btn-accent btn-block" href="#/">Back home</a>
      </div>
    )
  }

  return null
}
