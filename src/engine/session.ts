import type { Card } from '@/data/types'

const REQUEUE_HORIZON_MS = 20 * 60000
const REQUEUE_OFFSET = 5

export interface Session {
  current(): Card | null
  answer(updated: Card): void
  remaining(): number
}

export function createSession(cards: Card[]): Session {
  const queue = [...cards]

  return {
    current() {
      return queue[0] ?? null
    },
    answer(updated: Card) {
      queue.shift()
      if (updated.due <= Date.now() + REQUEUE_HORIZON_MS) {
        const pos = Math.min(REQUEUE_OFFSET, queue.length)
        queue.splice(pos, 0, updated)
      }
    },
    remaining() {
      return queue.length
    },
  }
}
