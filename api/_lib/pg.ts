// Tiny query seam so sync.ts can run against either:
//  - @neondatabase/serverless (the "neon-http" driver) in production, talking
//    to Neon over HTTP with no persistent connection, or
//  - the plain `pg` driver in tests, talking to a real Postgres over TCP
//    (colima docker container) — the neon-http driver cannot speak to a
//    non-Neon Postgres endpoint at all, so tests need a different transport.
//
// Both paths expose the same `transaction(queries)` shape: an array of
// {text, params} descriptors executed in order inside a single Postgres
// transaction, returning an array of row-arrays (one per query, in order).
// This is exactly the shape neon's `sql.transaction()` returns, so the pg
// path is written to match it.
//
// IMPORTANT: both driver packages are loaded via dynamic `import()` inside
// getDb(), not as static top-level imports. A prod incident showed that
// with static imports, `/api/sync` 500ed as FUNCTION_INVOCATION_FAILED for
// EVERY request — including wrong-key ones that must 401 without ever
// touching a database — before DATABASE_URL was provisioned in Vercel.
// Static `import { Pool } from 'pg'` runs `pg`'s own top-level module code
// as part of loading this function's bundle, which can fail independently
// of whether any of our code actually calls it. Dynamic imports defer that
// entirely until getDb() is actually invoked, which only happens after
// assertKey() has already let the request through.
export interface QueryDesc {
  text: string
  params: unknown[]
}

export interface DbClient {
  transaction(queries: QueryDesc[]): Promise<unknown[][]>
}

export class DatabaseNotConfiguredError extends Error {
  statusCode = 500
  constructor() {
    super('database not configured')
  }
}

async function makeNeonClient(url: string): Promise<DbClient> {
  const { neon } = await import('@neondatabase/serverless')
  const sql = neon(url)
  return {
    async transaction(queries) {
      if (queries.length === 0) return []
      return sql.transaction(queries.map((q) => sql.query(q.text, q.params)))
    },
  }
}

async function makePgClient(url: string): Promise<DbClient> {
  const { Pool } = await import('pg')
  const pool = new Pool({ connectionString: url })
  return {
    async transaction(queries) {
      const client = await pool.connect()
      try {
        await client.query('BEGIN')
        const results: unknown[][] = []
        for (const q of queries) {
          const r = await client.query(q.text, q.params)
          results.push(r.rows)
        }
        await client.query('COMMIT')
        return results
      } catch (err) {
        await client.query('ROLLBACK')
        throw err
      } finally {
        client.release()
      }
    },
  }
}

let cached: DbClient | undefined

/**
 * Returns a DbClient for the configured database. `PG_TEST_URL` (set only in
 * server-tests) always forces the `pg` driver, since it points at a plain
 * TCP Postgres instance that neon-http cannot reach. Otherwise, DATABASE_URL
 * is used, routed through neon-http unless the URL is clearly not a Neon
 * endpoint (e.g. a local/CI Postgres override), in which case `pg` is used
 * too.
 *
 * Throws DatabaseNotConfiguredError (not a raw crash) if neither env var is
 * set — callers should catch this and return a clean JSON 500.
 */
export async function getDb(): Promise<DbClient> {
  if (cached) return cached
  const testUrl = process.env.PG_TEST_URL
  const prodUrl = process.env.DATABASE_URL
  const url = testUrl ?? prodUrl
  if (!url) throw new DatabaseNotConfiguredError()

  const useNodePg = !!testUrl || !/neon\.tech/.test(url)
  cached = useNodePg ? await makePgClient(url) : await makeNeonClient(url)
  return cached
}

/** Test-only: drop the cached client so a new PG_TEST_URL takes effect. */
export function resetDbCache(): void {
  cached = undefined
}
