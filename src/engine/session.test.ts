import { describe, it, expect } from 'vitest'
import { createSession } from './session'

const c = (id: string): any => ({ id, due: 0 })

describe('session', () => {
  it('drops cards scheduled beyond 20m, requeues intraday ones', () => {
    const s = createSession([c('a'), c('b')])
    expect(s.current()!.id).toBe('a')
    s.answer({ ...c('a'), due: Date.now() + 5 * 60000 } as any) // 5m → requeue
    expect(s.remaining()).toBe(2)
    s.answer({ ...c('b'), due: Date.now() + 86400000 } as any) // 1d → drop
    expect(s.remaining()).toBe(1)
    expect(s.current()!.id).toBe('a')
  })
})
