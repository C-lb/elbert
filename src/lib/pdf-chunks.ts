// Client-side PDF page chunking for /api/generate.
//
// Vercel rejects request bodies over ~4.5MB regardless of what the function
// itself would accept, so a big PDF (up to the app's 10MB cap) has to be
// split into page-range sub-documents small enough that each JSON request's
// base64 payload stays well clear of that platform limit. The server is
// unchanged: each chunk is just a normal, smaller /api/generate request.
import { PDFDocument } from 'pdf-lib'

// Per-request base64 budget (~3MB of base64 characters). JSON overhead on top
// of this is tiny, so every chunked request body sits far below Vercel's
// ~4.5MB cap. A PDF whose whole projected base64 fits this budget goes
// through the existing single-request path.
export const CHUNK_BASE64_BUDGET = 3 * 1024 * 1024

/** Thrown when a single page serializes over the budget on its own: it cannot be split further. */
export class PageTooLargeError extends Error {
  constructor() {
    super('a single page exceeds the upload budget')
    this.name = 'PageTooLargeError'
  }
}

export interface PdfChunk {
  bytes: Uint8Array
  pageCount: number
}

/** Base64 length of a payload of `byteLength` raw bytes: 4 chars per 3-byte group, padded. */
export function projectedBase64Length(byteLength: number): number {
  return Math.ceil(byteLength / 3) * 4
}

/**
 * Splits a requested card total across chunks roughly proportionally to each
 * chunk's page count, minimum 1 per chunk. Sums can drift slightly from
 * `total` (rounding, minimums); the server treats count as a target anyway.
 */
export function splitCountAcrossChunks(total: number, pageCounts: number[]): number[] {
  const totalPages = pageCounts.reduce((a, b) => a + b, 0)
  return pageCounts.map(pc => Math.max(1, Math.round((total * pc) / totalPages)))
}

/**
 * Splits a PDF into page-range sub-documents whose serialized base64 length
 * each fits `base64Budget`. Page order is preserved. Recursive bisection:
 * try the whole range, halve any range that serializes over budget. Shared
 * resources (fonts, images) get duplicated into each chunk, so sizes are
 * re-measured per chunk rather than assumed to add up linearly.
 */
export async function splitPdfIntoChunks(
  bytes: Uint8Array,
  base64Budget = CHUNK_BASE64_BUDGET,
): Promise<PdfChunk[]> {
  const src = await PDFDocument.load(bytes, { ignoreEncryption: true })
  const total = src.getPageCount()

  const serializeRange = async (start: number, end: number): Promise<Uint8Array> => {
    const doc = await PDFDocument.create()
    const indices = Array.from({ length: end - start }, (_, i) => start + i)
    const pages = await doc.copyPages(src, indices)
    for (const page of pages) doc.addPage(page)
    return doc.save()
  }

  const pack = async (start: number, end: number): Promise<PdfChunk[]> => {
    const serialized = await serializeRange(start, end)
    if (projectedBase64Length(serialized.length) <= base64Budget) {
      return [{ bytes: serialized, pageCount: end - start }]
    }
    if (end - start <= 1) throw new PageTooLargeError()
    const mid = start + Math.ceil((end - start) / 2)
    return [...(await pack(start, mid)), ...(await pack(mid, end))]
  }

  return pack(0, total)
}
