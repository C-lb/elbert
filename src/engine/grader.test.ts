import { describe, it, expect } from 'vitest'
import { grade } from './grader'

describe('grade', () => {
  it('exact and case/diacritic-insensitive', () => {
    expect(grade('Ãrbol', ' arbol ')).toBe('correct')
  })
  it('edit distance 1 on long answers is close', () => {
    expect(grade('biblioteca', 'bibloteca')).toBe('close')
  })
  it('short answers demand exactness', () => {
    expect(grade('sí', 'so')).toBe('wrong')
  })
})
