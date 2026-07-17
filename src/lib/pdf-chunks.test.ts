import { describe, expect, it } from 'vitest'
import { PDFDocument } from 'pdf-lib'
import {
  PageTooLargeError,
  projectedBase64Length,
  splitCountAcrossChunks,
  splitPdfIntoChunks,
} from './pdf-chunks'

describe('projectedBase64Length', () => {
  it('is 4 chars per padded 3-byte group', () => {
    expect(projectedBase64Length(0)).toBe(0)
    expect(projectedBase64Length(1)).toBe(4)
    expect(projectedBase64Length(2)).toBe(4)
    expect(projectedBase64Length(3)).toBe(4)
    expect(projectedBase64Length(4)).toBe(8)
    expect(projectedBase64Length(6)).toBe(8)
  })

  it('matches the real base64 length', () => {
    for (const n of [1, 2, 3, 57, 1000, 1001]) {
      const b64 = Buffer.alloc(n).toString('base64')
      expect(projectedBase64Length(n)).toBe(b64.length)
    }
  })
})

describe('splitCountAcrossChunks', () => {
  it('splits proportionally to page counts', () => {
    expect(splitCountAcrossChunks(10, [1, 1])).toEqual([5, 5])
    expect(splitCountAcrossChunks(20, [3, 1])).toEqual([15, 5])
  })

  it('gives every chunk at least 1', () => {
    expect(splitCountAcrossChunks(5, [100, 1])).toEqual([5, 1])
    expect(splitCountAcrossChunks(1, [1, 1, 1])).toEqual([1, 1, 1])
  })

  it('passes the whole total to a single chunk', () => {
    expect(splitCountAcrossChunks(20, [7])).toEqual([20])
  })
})

async function makePdf(pages: number): Promise<Uint8Array> {
  const doc = await PDFDocument.create()
  for (let i = 0; i < pages; i++) {
    const page = doc.addPage([300, 300])
    // Distinct content per page so pages carry real weight.
    page.drawText(`Page ${i + 1} ${'x'.repeat(200)}`, { x: 10, y: 150, size: 8, maxWidth: 280 })
  }
  return doc.save()
}

describe('splitPdfIntoChunks', () => {
  it('returns a single chunk when the whole PDF fits the budget', async () => {
    const bytes = await makePdf(3)
    const chunks = await splitPdfIntoChunks(bytes, 10 * 1024 * 1024)
    expect(chunks).toHaveLength(1)
    expect(chunks[0].pageCount).toBe(3)
  })

  it('splits an oversized PDF into in-order chunks that each fit the budget', async () => {
    const bytes = await makePdf(8)
    // Budget forces a split but comfortably fits a few pages per chunk.
    const budget = projectedBase64Length(Math.ceil(bytes.length / 2))
    const chunks = await splitPdfIntoChunks(bytes, budget)
    expect(chunks.length).toBeGreaterThan(1)
    expect(chunks.reduce((a, c) => a + c.pageCount, 0)).toBe(8)
    for (const chunk of chunks) {
      expect(projectedBase64Length(chunk.bytes.length)).toBeLessThanOrEqual(budget)
      const doc = await PDFDocument.load(chunk.bytes)
      expect(doc.getPageCount()).toBe(chunk.pageCount)
    }
  })

  it('throws PageTooLargeError when a single page exceeds the budget', async () => {
    const bytes = await makePdf(4)
    await expect(splitPdfIntoChunks(bytes, 16)).rejects.toBeInstanceOf(PageTooLargeError)
  })
})
