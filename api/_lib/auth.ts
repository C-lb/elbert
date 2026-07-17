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

/** Throws UnauthorizedError unless x-elbert-key strictly equals env ELBERT_KEY. */
export function assertKey(req: AuthableRequest): void {
  const expected = process.env.ELBERT_KEY
  const provided = req.headers['x-elbert-key']
  if (!expected || provided !== expected) {
    throw new UnauthorizedError()
  }
}
