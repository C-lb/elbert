import initSqlJs from 'sql.js'
import type { SqlJsStatic } from 'sql.js'

let sqlJsPromise: Promise<SqlJsStatic> | null = null

// sql.js needs its wasm binary. Two very different environments load this module:
//   - tests (Node, vitest): read the wasm straight off disk from node_modules.
//   - the browser build (Vite): the wasm must be bundled into the app so .apkg import works fully
//     offline (no CDN fetch, no network requests) — `?url` makes Vite emit it as a hashed asset.
// The browser-only import is dynamic and guarded behind the `window` check so it's never evaluated
// under the Node test environment, where a dev-server URL wouldn't resolve to a real file anyway.
export function loadSqlJs(): Promise<SqlJsStatic> {
  if (!sqlJsPromise) {
    sqlJsPromise =
      typeof window === 'undefined' ? loadForNode() : loadForBrowser()
  }
  return sqlJsPromise
}

async function loadForNode(): Promise<SqlJsStatic> {
  const path = await import('node:path')
  const wasmPath = path.join(process.cwd(), 'node_modules/sql.js/dist/sql-wasm.wasm')
  return initSqlJs({ locateFile: () => wasmPath })
}

async function loadForBrowser(): Promise<SqlJsStatic> {
  const wasmUrl = (await import('sql.js/dist/sql-wasm.wasm?url')).default
  return initSqlJs({ locateFile: () => wasmUrl })
}
