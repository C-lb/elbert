export interface ImportRow {
  term: string
  definition: string
}

// Delimiter is chosen once for the whole input (Quizlet exports are consistently tab- or
// comma-separated), not per line — a per-line guess would misfire on a definition that happens to
// contain a comma while the file is actually tab-delimited.
function detectDelimiter(text: string): '\t' | ',' | ';' {
  if (text.includes('\t')) return '\t'
  if (text.includes(',')) return ','
  return ';'
}

// Splits text into logical rows, respecting quoted fields that may contain embedded newlines.
// Returns an array of rows, each row an array of raw (still-quoted) fields.
function splitRows(text: string, delimiter: string): string[][] {
  const rows: string[][] = []
  let row: string[] = []
  let field = ''
  let inQuotes = false

  const pushField = () => {
    row.push(field)
    field = ''
  }
  const pushRow = () => {
    pushField()
    rows.push(row)
    row = []
  }

  for (let i = 0; i < text.length; i++) {
    const ch = text[i]

    if (inQuotes) {
      if (ch === '"') {
        if (text[i + 1] === '"') {
          field += '"'
          i++
        } else {
          inQuotes = false
        }
      } else {
        field += ch
      }
      continue
    }

    if (ch === '"' && field === '') {
      inQuotes = true
      continue
    }
    if (ch === delimiter) {
      pushField()
      continue
    }
    if (ch === '\r') continue
    if (ch === '\n') {
      pushRow()
      continue
    }
    field += ch
  }

  // Flush trailing field/row unless the input ended cleanly on a newline (already pushed).
  if (field !== '' || row.length > 0) pushRow()

  return rows
}

export function parseCsv(text: string): ImportRow[] {
  if (!text.trim()) return []

  const delimiter = detectDelimiter(text)
  const rows = splitRows(text, delimiter)
  const out: ImportRow[] = []

  for (const cells of rows) {
    const trimmed = cells.map(c => c.trim())
    if (trimmed.every(c => c === '')) continue

    const [term, definition = '', ...rest] = trimmed
    if (!term) continue

    const fullDefinition = rest.length > 0 ? [definition, ...rest].join(' · ') : definition
    out.push({ term, definition: fullDefinition })
  }

  return out
}
