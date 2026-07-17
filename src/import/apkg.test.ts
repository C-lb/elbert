import { readFile } from 'node:fs/promises'
import path from 'node:path'
import JSZip from 'jszip'
import { describe, expect, it } from 'vitest'
import { parseApkg } from './apkg'
import { loadSqlJs } from './sqljs'

const FIXTURE_PATH = path.join(__dirname, 'fixtures/mini.apkg')

function buildCollectionDb(SQL: Awaited<ReturnType<typeof loadSqlJs>>, notes: { fields: string[]; tags: string[] }[]) {
  const db = new SQL.Database()
  db.run(`
    CREATE TABLE notes (
      id integer primary key, guid text, mid integer, mod integer, usn integer,
      tags text, flds text, sfld text, csum integer, flags integer, data text
    );
  `)
  const stmt = db.prepare(
    'INSERT INTO notes (id, guid, mid, mod, usn, tags, flds, sfld, csum, flags, data) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
  )
  notes.forEach((n, i) => {
    stmt.run([i + 1, `g${i + 1}`, 1, 0, -1, ` ${n.tags.join(' ')} `, n.fields.join('\x1f'), n.fields[0], 0, 0, ''])
  })
  stmt.free()
  const bytes = db.export()
  db.close()
  return bytes
}

describe('parseApkg', () => {
  it('parses notes with correct field splits and tags from a real .apkg fixture', async () => {
    const buf = await readFile(FIXTURE_PATH)
    const arrayBuffer = buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength)
    const result = await parseApkg(arrayBuffer)

    expect(result.notes).toHaveLength(2)
    expect(result.notes[0]).toEqual({ fields: ['chat', 'cat'], tags: ['animals', 'french'] })
    expect(result.notes[1]).toEqual({ fields: ['chien', 'dog'], tags: ['animals'] })
  })

  it('prefers collection.anki21 over collection.anki2 when both are present', async () => {
    const SQL = await loadSqlJs()
    const oldBytes = buildCollectionDb(SQL, [{ fields: ['stale', 'wrong'], tags: [] }])
    const newBytes = buildCollectionDb(SQL, [{ fields: ['fresh', 'right'], tags: ['new'] }])

    const zip = new JSZip()
    zip.file('collection.anki2', oldBytes)
    zip.file('collection.anki21', newBytes)
    const zipBytes = await zip.generateAsync({ type: 'arraybuffer' })

    const result = await parseApkg(zipBytes)

    expect(result.notes).toEqual([{ fields: ['fresh', 'right'], tags: ['new'] }])
  })

  it('throws a clear error for a zip with no collection file', async () => {
    const zip = new JSZip()
    zip.file('readme.txt', 'not a real anki export')
    const zipBytes = await zip.generateAsync({ type: 'arraybuffer' })

    await expect(parseApkg(zipBytes)).rejects.toThrow(/collection\.anki21|collection\.anki2/)
  })
})
