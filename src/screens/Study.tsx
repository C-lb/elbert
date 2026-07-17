import { useEffect, useRef, useState } from 'react'
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
  const sessionRef = useRef<Session | null>(null)
  const revealAtRef = useRef(0)
  const newIntroducedRef = useRef<Map<string, number>>(new Map())

  useEffect(() => {
    let cancelled = false

    ;(async () => {
      const queue = await buildQueue(deckId)
      const notes = await db.notes.toArray()
      const decks = await db.decks.toArray()
      if (cancelled) return

      setNotesById(new Map(notes.map(n => [n.id, n])))
      setRetentionByDeck(new Map(decks.map(d => [d.id, d.desiredRetention])))

      for (const c of queue) {
        if (c.state === 0) {
          const note = notes.find(n => n.id === c.noteId)
          if (note) newIntroducedRef.current.set(note.deckId, (newIntroducedRef.current.get(note.deckId) ?? 0) + 1)
        }
      }

      const session = createSession(queue)
      sessionRef.current = session
      const first = session.current()
      setCard(first)
      setPhase(first ? 'front' : 'done')
    })()

    return () => {
      cancelled = true
    }
  }, [deckId])

  async function finish() {
    for (const [id, n] of newIntroducedRef.current) await noteNewIntroduced(id, n)
    setPhase('done')
  }

  function reveal() {
    if (phase !== 'front') return
    revealAtRef.current = Date.now()
    setPhase('back')
  }

  async function rate(rating: Rating) {
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
    if (!next) await finish()
  }

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
  })

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

  const note = card ? notesById.get(card.noteId) : undefined
  if (!card || !note) {
    return (
      <div className="screen">
        <div className="stub">Nothing to study.</div>
      </div>
    )
  }

  const labels = previewIntervals(card, retentionByDeck.get(note.deckId) ?? 0.9)

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
      {phase === 'back' && <RatingBar labels={labels} onRate={rate} />}
    </div>
  )
}
