import { timingSafeEqual } from 'node:crypto'

// Minimal request shape shared with sync.ts — matches what both Vercel's
// Node runtime request object and our fake test req provide.
export interface AuthableRequest {
  headers: Record<string, string | string[] | undefined>
}

export class UnauthorizedError extends Error {
  statusCode = 401
  constructor() {
    super('unauthorized')
  }
}

/** Constant-time string compare, guarded against length leaks via timingSafeEqual's own length requirement. */
function safeEqual(a: string, b: string): boolean {
  const bufA = Buffer.from(a)
  const bufB = Buffer.from(b)
  if (bufA.length !== bufB.length) return false
  return timingSafeEqual(bufA, bufB)
}

/** Throws UnauthorizedError unless x-elbert-key strictly equals env ELBERT_KEY. */
export function assertKey(req: AuthableRequest): void {
  const expected = process.env.ELBERT_KEY
  const provided = req.headers['x-elbert-key']
  if (!expected || typeof provided !== 'string' || !safeEqual(provided, expected)) {
    throw new UnauthorizedError()
  }
}
