import { describe, expect, it } from 'vitest'
import { parseCsv } from './csv'

describe('parseCsv', () => {
  it('parses tab-delimited rows (Quizlet default export)', () => {
    const text = 'chat\tcat\nchien\tdog'
    expect(parseCsv(text)).toEqual([
      { term: 'chat', definition: 'cat' },
      { term: 'chien', definition: 'dog' },
    ])
  })

  it('parses comma-delimited rows with quoted fields containing commas', () => {
    const text = '"a, b",def\nterm2,def2'
    expect(parseCsv(text)).toEqual([
      { term: 'a, b', definition: 'def' },
      { term: 'term2', definition: 'def2' },
    ])
  })

  it('handles quoted fields with embedded newlines', () => {
    const text = '"line1\nline2",def'
    expect(parseCsv(text)).toEqual([{ term: 'line1\nline2', definition: 'def' }])
  })

  it('handles escaped quotes inside quoted fields', () => {
    const text = '"she said ""hi""",def'
    expect(parseCsv(text)).toEqual([{ term: 'she said "hi"', definition: 'def' }])
  })

  it('falls back to semicolon when no tab or comma is present', () => {
    const text = 'chat;cat\nchien;dog'
    expect(parseCsv(text)).toEqual([
      { term: 'chat', definition: 'cat' },
      { term: 'chien', definition: 'dog' },
    ])
  })

  it('appends extra columns to definition separated by middle dot', () => {
    const text = 'chat,cat,feline,animal'
    expect(parseCsv(text)).toEqual([{ term: 'chat', definition: 'cat · feline · animal' }])
  })

  it('trims cell whitespace', () => {
    const text = '  chat  ,  cat  '
    expect(parseCsv(text)).toEqual([{ term: 'chat', definition: 'cat' }])
  })

  it('skips empty lines', () => {
    const text = 'chat\tcat\n\n\nchien\tdog'
    expect(parseCsv(text)).toEqual([
      { term: 'chat', definition: 'cat' },
      { term: 'chien', definition: 'dog' },
    ])
  })

  it('skips rows with an empty term', () => {
    const text = 'chat\tcat\n\tdog\n   \tcat2'
    expect(parseCsv(text)).toEqual([{ term: 'chat', definition: 'cat' }])
  })

  it('handles CRLF line endings', () => {
    const text = 'chat\tcat\r\nchien\tdog\r\n'
    expect(parseCsv(text)).toEqual([
      { term: 'chat', definition: 'cat' },
      { term: 'chien', definition: 'dog' },
    ])
  })

  it('returns empty array for empty input', () => {
    expect(parseCsv('')).toEqual([])
    expect(parseCsv('   \n  \n')).toEqual([])
  })

  it('handles a row with only a term and no definition', () => {
    const text = 'chat'
    expect(parseCsv(text)).toEqual([{ term: 'chat', definition: '' }])
  })
})
