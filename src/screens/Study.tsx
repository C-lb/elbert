import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { db } from '@/data/db'
import { buildQueue, noteNewIntroduced } from '@/engine/queue'
import { applyReview, previewIntervals } from '@/engine/scheduler'
import { createSession, type Session } from '@/engine/session'
import type { Card, Note, Rating } from '@/data/types'
import CardFace from '@/components/CardFace'
import RatingBar from '@/components/RatingBar'

interface StudyProps {
  deckId?: string
}

type Phase = 'loading' | 'front' | 'back' | 'done'

export default function Study({ deckId }: StudyProps) {
  const [phase, setPhase] = useState<Phase>('loading')
  const [notesById, setNotesById] = useState<Map<string, Note>>(new Map())
  const [retentionByDeck, setRetentionByDeck] = useState<Map<string, number>>(new Map())
  const [card, setCard] = useState<Card | null>(null)
  const [reviewed, setReviewed] = useState(0)
  const [submitting, setSubmitting] = useState(false)
  const sessionRef = useRef<Session | null>(null)
  const revealAtRef = useRef(0)
  const submittingRef = useRef(false)
  const countedNewRef = useRef<Set<string>>(new Set())
  const notesByIdRef = useRef<Map<string, Note>>(new Map())

  // Counts a state-0 card as "introduced" the moment it is first shown, exactly once,
  // even if it re-queues intraday. Fired synchronously with display so an interrupted
  // session still advances the daily cap (no batching at session end).
  const noteShown = useCallback((c: Card | null) => {
    if (!c || c.state !== 0 || countedNewRef.current.has(c.id)) return
    const note = notesByIdRef.current.get(c.noteId)
    if (!note) return
    countedNewRef.current.add(c.id)
    void noteNewIntroduced(note.deckId, 1)
  }, [])

  useEffect(() => {
    let cancelled = false

    ;(async () => {
      const queue = await buildQueue(deckId)
      const notes = await db.notes.toArray()
      const decks = await db.decks.toArray()
      if (cancelled) return

      const notesMap = new Map(notes.map(n => [n.id, n]))
      notesByIdRef.current = notesMap
      setNotesById(notesMap)
      setRetentionByDeck(new Map(decks.map(d => [d.id, d.desiredRetention])))

      const session = createSession(queue)
      sessionRef.current = session
      const first = session.current()
      setCard(first)
      setPhase(first ? 'front' : 'done')
      noteShown(first)
    })()

    return () => {
      cancelled = true
    }
  }, [deckId, noteShown])

  const reveal = useCallback(() => {
    if (phase !== 'front') return
    revealAtRef.current = Date.now()
    setPhase('back')
  }, [phase])

  const rate = useCallback(
    async (rating: Rating) => {
      if (submittingRef.current) return
      submittingRef.current = true
      setSubmitting(true)

      try {
        const session = sessionRef.current
        if (!session || !card) return
        const note = notesById.get(card.noteId)
        const retention = (note && retentionByDeck.get(note.deckId)) ?? 0.9
        const elapsedMs = Date.now() - revealAtRef.current

        const updated = await applyReview(card, rating, elapsedMs, retention)
        session.answer(updated)
        setReviewed(n => n + 1)

        const next = session.current()
        setCard(next)
        setPhase(next ? 'front' : 'done')
        noteShown(next)
      } finally {
        submittingRef.current = false
        setSubmitting(false)
      }
    },
    [card, notesById, retentionByDeck, noteShown]
  )

  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (phase === 'front' && e.code === 'Space') {
        e.preventDefault()
        reveal()
      } else if (phase === 'back' && ['1', '2', '3', '4'].includes(e.key)) {
        rate(Number(e.key) as Rating)
      }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [phase, reveal, rate])

  const note = card ? notesById.get(card.noteId) : undefined
  const retention = note ? retentionByDeck.get(note.deckId) ?? 0.9 : 0.9
  const labels = useMemo(
    () => (card ? previewIntervals(card, retention) : null),
    [card, retention]
  )

  if (phase === 'loading') {
    return (
      <div className="screen">
        <div className="stub">Loading queue…</div>
      </div>
    )
  }

  if (phase === 'done') {
    return (
      <div className="screen">
        <div className="study-done">
          <div className="due-number">{reviewed}</div>
          <div className="due-label">cards reviewed</div>
          <a className="btn btn-accent btn-block" href="#/">Back home</a>
        </div>
      </div>
    )
  }

  if (!card || !note || !labels) {
    return (
      <div className="screen">
        <div className="stub">Nothing to study.</div>
      </div>
    )
  }

  return (
    <div className="screen study-screen">
      <div className="study-remaining">{sessionRef.current!.remaining() + 1} left</div>
      <button className="study-card-tap" onClick={reveal} disabled={phase === 'back'}>
        <CardFace note={note} ord={card.ord} revealed={phase === 'back'} />
      </button>
      {phase === 'front' && (
        <button className="btn btn-accent btn-block" onClick={reveal}>
          Show answer
        </button>
      )}
      {phase === 'back' && <RatingBar labels={labels} onRate={rate} disabled={submitting} />}
    </div>
  )
}
