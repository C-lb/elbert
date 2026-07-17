import JSZip from 'jszip'
import { loadSqlJs } from './sqljs'

export interface ApkgNote {
  fields: string[]
  tags: string[]
}

export interface ApkgResult {
  notes: ApkgNote[]
}

const FIELD_SEP = '\x1f'
// Anki's newer (2.1+) collection filename; .anki2 is the older/legacy format some exporters still
// produce. Prefer anki21 when both are present since it's the more current schema.
const COLLECTION_NAMES = ['collection.anki21', 'collection.anki2']

export async function parseApkg(data: ArrayBuffer): Promise<ApkgResult> {
  const zip = await JSZip.loadAsync(data)

  let collectionName: string | undefined
  for (const name of COLLECTION_NAMES) {
    if (zip.file(name)) {
      collectionName = name
      break
    }
  }
  if (!collectionName) {
    throw new Error('Not a valid .apkg file: no collection.anki21 or collection.anki2 found inside the zip')
  }

  const dbBytes = await zip.file(collectionName)!.async('uint8array')

  const SQL = await loadSqlJs()
  const db = new SQL.Database(dbBytes)
  try {
    const result = db.exec('SELECT flds, tags FROM notes')
    if (result.length === 0) return { notes: [] }

    const [{ values }] = result
    const notes: ApkgNote[] = values.map(([flds, tags]) => ({
      fields: String(flds).split(FIELD_SEP),
      tags: String(tags).trim().split(/\s+/).filter(Boolean),
    }))
    return { notes }
  } finally {
    db.close()
  }
}
