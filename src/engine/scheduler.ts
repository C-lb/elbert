import { fsrs, generatorParameters, type Card as FsrsCard, type Grade, State } from 'ts-fsrs'
import { v4 as uuid } from 'uuid'
import { repo } from '@/data/repo'
import type { Card, Rating } from '@/data/types'

const engine = (retention: number) => fsrs(generatorParameters({ request_retention: retention }))

function toFsrs(c: Card): FsrsCard {
  return {
    due: new Date(c.due),
    stability: c.stability,
    difficulty: c.difficulty,
    elapsed_days: 0,
    scheduled_days: 0,
    learning_steps: 0,
    reps: c.reps,
    lapses: c.lapses,
    state: c.state as State,
    last_review: c.lastReview ? new Date(c.lastReview) : undefined,
  }
}

function fromFsrs(c: Card, f: FsrsCard): Card {
  return {
    ...c,
    due: f.due.getTime(),
    stability: f.stability,
    difficulty: f.difficulty,
    reps: f.reps,
    lapses: f.lapses,
    state: f.state as Card['state'],
    lastReview: f.last_review ? f.last_review.getTime() : null,
  }
}

const label = (ms: number) => {
  const m = ms / 60000
  if (m < 60) return `<${Math.max(1, Math.round(m))}m`
  if (m < 60 * 24) return `${Math.round(m / 60)}h`
  const d = m / (60 * 24)
  return d < 30 ? `${Math.round(d)}d` : `${(d / 30).toFixed(1)}mo`
}

export function previewIntervals(card: Card, retention: number): { 1: string; 2: string; 3: string; 4: string } {
  const now = new Date()
  const rec = engine(retention).repeat(toFsrs(card), now)
  const out: Record<string, string> = {}
  for (const g of [1, 2, 3, 4] as Grade[]) out[String(g)] = label(rec[g].card.due.getTime() - now.getTime())
  return out as { 1: string; 2: string; 3: string; 4: string }
}

export async function applyReview(card: Card, rating: Rating, elapsedMs: number, retention: number): Promise<Card> {
  const snapshot = {
    due: card.due,
    stability: card.stability,
    difficulty: card.difficulty,
    reps: card.reps,
    lapses: card.lapses,
    state: card.state,
  }
  const rec = engine(retention).repeat(toFsrs(card), new Date())
  const updated = fromFsrs(card, rec[rating as Grade].card)
  await repo.put('cards', updated)
  await repo.addReview({
    id: uuid(),
    cardId: card.id,
    ts: Date.now(),
    rating,
    elapsedMs,
    snapshot,
    deletedAt: null,
  })
  return updated
}
