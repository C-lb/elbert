import { useEffect, useMemo, useRef, useState } from 'react'
import { db } from '@/data/db'
import { repo } from '@/data/repo'
import { createMatchGame, type MatchGame, type MatchTile } from '@/engine/match'
import type { Note } from '@/data/types'

interface MatchProps {
  deckId?: string
}

type Phase = 'loading' | 'playing' | 'done'

const PENALTY_MS = 1000

function mulberry32(seed: number): () => number {
  let a = seed
  return function () {
    a |= 0
    a = (a + 0x6d2b79f5) | 0
    let t = Math.imul(a ^ (a >>> 15), 1 | a)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

function bestKey(deckId: string) {
  return `matchBest:${deckId}`
}

function formatSeconds(ms: number): string {
  return (ms / 1000).toFixed(1)
}

export default function Match({ deckId }: MatchProps) {
  const [phase, setPhase] = useState<Phase>('loading')
  const [notes, setNotes] = useState<Note[]>([])
  const [seed, setSeed] = useState(1)
  const [tiles, setTiles] = useState<MatchTile[]>([])
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [flashIds, setFlashIds] = useState<{ ids: string[]; kind: 'miss' } | null>(null)
  const [fadingIds, setFadingIds] = useState<string[]>([])
  const [misses, setMisses] = useState(0)
  const [finalMs, setFinalMs] = useState<number | null>(null)
  const [best, setBest] = useState<number | null>(null)

  const gameRef = useRef<MatchGame | null>(null)
  const startedAtRef = useRef<number | null>(null)
  const flashTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  useEffect(() => {
    let cancelled = false
    ;(async () => {
      const loaded = await db.notes.filter(n => n.deletedAt == null && (!deckId || n.deckId === deckId)).toArray()
      const storedBest = deckId ? await repo.getMeta<number>(bestKey(deckId)) : undefined
      if (cancelled) return
      setNotes(loaded)
      setBest(storedBest ?? null)
      setPhase('loading')
    })()
    return () => {
      cancelled = true
    }
  }, [deckId])

  useEffect(() => {
    if (notes.length === 0) return
    const game = createMatchGame(notes, mulberry32(seed))
    gameRef.current = game
    setTiles(game.tiles())
    setSelectedId(null)
    setFlashIds(null)
    setFadingIds([])
    setMisses(0)
    setFinalMs(null)
    startedAtRef.current = null
    setPhase('playing')
  }, [notes, seed])

  useEffect(() => {
    return () => {
      if (flashTimerRef.current) clearTimeout(flashTimerRef.current)
    }
  }, [])

  const finish = (missCount: number) => {
    const elapsed = Date.now() - (startedAtRef.current ?? Date.now())
    const total = elapsed + missCount * PENALTY_MS
    setFinalMs(total)
    setPhase('done')
    if (deckId && (best == null || total < best)) {
      setBest(total)
      void repo.setMeta(bestKey(deckId), total)
    }
  }

  const pickTile = (tileId: string) => {
    const game = gameRef.current
    if (!game || phase !== 'playing') return
    if (startedAtRef.current == null) startedAtRef.current = Date.now()

    const result = game.pick(tileId)
    if (result === 'ignored') return

    if (result === 'first') {
      setSelectedId(tileId)
      return
    }

    const prevSelected = selectedId
    setSelectedId(null)

    if (result === 'miss') {
      const ids = [prevSelected, tileId].filter((id): id is string => id != null)
      setMisses(m => m + 1)
      setFlashIds({ ids, kind: 'miss' })
      if (flashTimerRef.current) clearTimeout(flashTimerRef.current)
      flashTimerRef.current = setTimeout(() => setFlashIds(null), 300)
      return
    }

    if (result === 'match' || result === 'done') {
      const ids = [prevSelected, tileId].filter((id): id is string => id != null)
      setFadingIds(f => [...f, ...ids])
      setTiles(game.tiles())
      if (result === 'done') {
        finish(game.misses())
      }
    }
  }

  const playAgain = () => setSeed(s => s + 1)

  const totalMisses = gameRef.current?.misses() ?? misses
  const grid = useMemo(() => tiles, [tiles])

  if (phase === 'loading') {
    return (
      <div className="screen">
        <div className="stub">Loading deck…</div>
        <a className="btn btn-block" href="#/">Back home</a>
      </div>
    )
  }

  if (notes.length === 0) {
    return (
      <div className="screen">
        <div className="stub">No notes in this deck to match yet.</div>
        <a className="btn btn-block" href="#/">Back home</a>
      </div>
    )
  }

  if (phase === 'done' && finalMs != null) {
    const beatBest = deckId != null && best === finalMs
    return (
      <div className="screen">
        <div className="study-done">
          <div className="due-number">{formatSeconds(finalMs)}s</div>
          <div className="due-label">
            {totalMisses} miss{totalMisses === 1 ? '' : 'es'} (+{totalMisses}s penalty)
          </div>
          {best != null && (
            <div className={`hint ${beatBest ? 'match-best-beaten' : ''}`}>
              Best: {formatSeconds(best)}s{beatBest ? ' (new best!)' : ''}
            </div>
          )}
          <button className="btn btn-accent btn-block" onClick={playAgain}>
            Play again
          </button>
          <a className="btn btn-block" href="#/">Back home</a>
        </div>
      </div>
    )
  }

  return (
    <div className="screen match-screen">
      <div className="match-hud">
        <span className="hint">Misses: {totalMisses}</span>
        {best != null && <span className="hint">Best: {formatSeconds(best)}s</span>}
      </div>
      <div className="match-grid">
        {grid.map(tile => {
          const isSelected = selectedId === tile.id
          const isMiss = flashIds?.kind === 'miss' && flashIds.ids.includes(tile.id)
          const isFading = fadingIds.includes(tile.id)
          const classes = [
            'match-tile',
            isSelected ? 'match-tile-selected' : '',
            isMiss ? 'match-tile-miss' : '',
            isFading || tile.matched ? 'match-tile-matched' : '',
          ]
            .filter(Boolean)
            .join(' ')
          return (
            <button
              key={tile.id}
              type="button"
              className={classes}
              disabled={tile.matched}
              onClick={() => pickTile(tile.id)}
              title={tile.text}
            >
              <span className="match-tile-text">{tile.text}</span>
            </button>
          )
        })}
      </div>
      <a className="btn btn-block" href="#/">Back home</a>
    </div>
  )
}
