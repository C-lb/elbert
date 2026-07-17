import { useCallback, useEffect, useRef, useState } from 'react'
import { db } from '@/data/db'
import { applyReview } from '@/engine/scheduler'
import { createLearnSession, answerForNote, type LearnSession, type LearnStep } from '@/engine/learn'
import CardFace from '@/components/CardFace'

interface LearnProps {
  deckId?: string
}

type Phase = 'loading' | 'mc' | 'typed' | 'close' | 'done'

export default function Learn({ deckId }: LearnProps) {
  const [phase, setPhase] = useState<Phase>('loading')
  const [step, setStep] = useState<LearnStep | null>(null)
  const [progress, setProgress] = useState({ cleared: 0, total: 0 })
  const [typedValue, setTypedValue] = useState('')
  const [mcChoice, setMcChoice] = useState<string | null>(null)
  const sessionRef = useRef<LearnSession | null>(null)
  const revealAtRef = useRef(0)
  const submittingRef = useRef(false)

  useEffect(() => {
    let cancelled = false

    ;(async () => {
      const notes = await db.notes.filter(n => n.deletedAt == null && (!deckId || n.deckId === deckId)).toArray()
      const noteIds = new Set(notes.map(n => n.id))
      const cards = (await db.cards.toArray()).filter(
        c => c.deletedAt == null && c.suspended !== 1 && noteIds.has(c.noteId)
      )
      const decks = await db.decks.toArray()
      const retentionByDeck = new Map(decks.map(d => [d.id, d.desiredRetention]))
      if (cancelled) return

      const session = createLearnSession(cards, notes, {
        onDueReview: c => {
          const note = notes.find(n => n.id === c.noteId)
          const retention = (note && retentionByDeck.get(note.deckId)) ?? 0.9
          void applyReview(c, 3, Date.now() - revealAtRef.current, retention)
        },
      })
      sessionRef.current = session
      const first = session.next()
      revealAtRef.current = Date.now()
      setStep(first)
      setProgress(session.progress())
      setPhase(first ? (first.round === 1 ? 'mc' : 'typed') : 'done')
    })()

    return () => {
      cancelled = true
    }
  }, [deckId])

  const advance = useCallback(() => {
    const session = sessionRef.current
    if (!session) return
    const next = session.next()
    revealAtRef.current = Date.now()
    setStep(next)
    setProgress(session.progress())
    setTypedValue('')
    setMcChoice(null)
    setPhase(next ? (next.round === 1 ? 'mc' : 'typed') : 'done')
  }, [])

  const chooseMc = useCallback(
    (choice: string, correctAnswer: string) => {
      if (submittingRef.current || !sessionRef.current) return
      submittingRef.current = true
      setMcChoice(choice)
      const correct = choice === correctAnswer
      window.setTimeout(
        () => {
          sessionRef.current!.answerMc(correct)
          submittingRef.current = false
          advance()
        },
        correct ? 250 : 700
      )
    },
    [advance]
  )

  const submitTyped = useCallback(
    (e: React.FormEvent) => {
      e.preventDefault()
      const session = sessionRef.current
      if (!session || submittingRef.current || !typedValue.trim()) return
      const result = session.answerTyped(typedValue)
      setProgress(session.progress())
      if (result === 'close') {
        revealAtRef.current = Date.now()
        setPhase('close')
      } else {
        advance()
      }
    },
    [typedValue, advance]
  )

  const overrideCorrect = useCallback(() => {
    sessionRef.current?.overrideCorrect()
    advance()
  }, [advance])

  const declineClose = useCallback(() => {
    sessionRef.current?.declineClose()
    advance()
  }, [advance])

  if (phase === 'loading') {
    return (
      <div className="screen">
        <div className="stub">Loading cards…</div>
      </div>
    )
  }

  if (phase === 'done') {
    return (
      <div className="screen">
        <div className="study-done">
          <div className="due-number">{progress.cleared}</div>
          <div className="due-label">cards cleared</div>
          <a className="btn btn-accent btn-block" href="#/">
            Back home
          </a>
        </div>
      </div>
    )
  }

  if (!step) {
    return (
      <div className="screen">
        <div className="stub">Nothing to learn in this deck.</div>
      </div>
    )
  }

  const note = step.note
  const correctAnswer = answerForNote(note, step.card)
  const pct = progress.total === 0 ? 0 : Math.round((progress.cleared / progress.total) * 100)

  return (
    <div className="screen learn-screen">
      <div className="learn-progress">
        <div className="learn-progress-track">
          <div className="learn-progress-fill" style={{ width: `${pct}%` }} />
        </div>
        <div className="learn-progress-label">
          {progress.cleared} of {progress.total} cleared
        </div>
      </div>

      <CardFace note={note} ord={step.card.ord} revealed={false} />

      {phase === 'mc' && step.choices && (
        <div className="learn-choices">
          {step.choices.map(choice => {
            const isAnswer = choice === correctAnswer
            let state: 'idle' | 'correct' | 'wrong' | 'reveal' = 'idle'
            if (mcChoice) {
              if (choice === mcChoice) state = isAnswer ? 'correct' : 'wrong'
              else if (isAnswer) state = 'reveal'
            }
            return (
              <button
                key={choice}
                className={`learn-choice learn-choice-${state}`}
                disabled={!!mcChoice}
                onClick={() => chooseMc(choice, correctAnswer)}
              >
                {choice}
              </button>
            )
          })}
        </div>
      )}

      {(phase === 'typed' || phase === 'close') && (
        <form className="learn-typed" onSubmit={submitTyped}>
          <input
            className="field"
            autoFocus
            value={typedValue}
            onChange={e => setTypedValue(e.target.value)}
            disabled={phase === 'close'}
            placeholder="Type the answer"
            aria-label="Typed answer"
          />
          {phase === 'typed' && (
            <button className="btn btn-accent btn-block" type="submit">
              Check
            </button>
          )}
          {phase === 'close' && (
            <div className="learn-close">
              <div className="learn-close-hint">Close. Was that right?</div>
              <div className="learn-close-actions">
                <button type="button" className="btn btn-block" onClick={declineClose}>
                  No, mark wrong
                </button>
                <button type="button" className="btn btn-accent btn-block" onClick={overrideCorrect}>
                  I was right
                </button>
              </div>
            </div>
          )}
        </form>
      )}
    </div>
  )
}
