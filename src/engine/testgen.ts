import { grade } from './grader'
import { renderCloze, parseCloze } from './cloze'
import { answerForNote } from './learn'
import type { Card, Note } from '@/data/types'

export type QuestionType = 'written' | 'mc' | 'tf' | 'matching'

export interface TestCounts {
  written: number
  mc: number
  tf: number
  matching: number
}

export interface WrittenQuestion {
  id: string
  type: 'written'
  noteId: string
  prompt: string
  answer: string
}

export interface McQuestion {
  id: string
  type: 'mc'
  noteId: string
  prompt: string
  options: string[]
  correctIndex: number
}

export interface TfQuestion {
  id: string
  type: 'tf'
  noteId: string
  term: string
  definition: string
  isTrue: boolean
  /** The note the shown definition actually belongs to (equals noteId when isTrue). */
  definitionNoteId: string
}

export interface MatchingPair {
  noteId: string
  term: string
  definition: string
}

export interface MatchingSection {
  id: string
  type: 'matching'
  pairs: MatchingPair[]
  /** Definitions in shuffled display order. */
  definitions: string[]
}

export interface TestPaper {
  written: WrittenQuestion[]
  mc: McQuestion[]
  tf: TfQuestion[]
  matching: MatchingSection | null
}

export interface WrittenAnswers {
  [questionId: string]: string
}
export interface McAnswers {
  [questionId: string]: number
}
export interface TfAnswers {
  [questionId: string]: boolean
}
export interface MatchingAnswers {
  /** keyed by term noteId -> the definition text the user paired it with */
  [noteId: string]: string
}

export interface TestAnswers {
  written: WrittenAnswers
  mc: McAnswers
  tf: TfAnswers
  matching: MatchingAnswers
}

export interface WeakItem {
  noteId: string
  term: string
  expected: string
  given: string
}

export interface SectionResult {
  type: QuestionType
  correct: number
  total: number
}

export interface TestResult {
  sections: SectionResult[]
  correctCount: number
  totalCount: number
  percent: number
  weakest: WeakItem[]
}

function shuffle<T>(arr: T[], rng: () => number): T[] {
  const a = [...arr]
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1))
    ;[a[i], a[j]] = [a[j], a[i]]
  }
  return a
}

/** The lowest cloze ordinal in a note's term text, defaulting to 1 for non-cloze notes. */
function firstOrd(note: Note): number {
  if (note.type !== 'cloze') return 1
  const ords = parseCloze(note.fields.term)
  return ords[0]?.ord ?? 1
}

/** A minimal stand-in Card carrying only the ordinal, for reuse of answerForNote(). */
function pseudoCard(note: Note, ord: number): Card {
  return {
    id: '',
    noteId: note.id,
    ord,
    due: 0,
    stability: 0,
    difficulty: 0,
    reps: 0,
    lapses: 0,
    state: 0,
    lastReview: null,
    suspended: 0,
    learningSteps: 0,
    deletedAt: null,
  }
}

function termText(note: Note, ord: number): string {
  return note.type === 'cloze' ? renderCloze(note.fields.term, ord, false) : note.fields.term
}

function answerText(note: Note, ord: number): string {
  return answerForNote(note, pseudoCard(note, ord))
}

function buildWritten(note: Note, i: number): WrittenQuestion {
  const ord = firstOrd(note)
  return {
    id: `w-${i}`,
    type: 'written',
    noteId: note.id,
    prompt: termText(note, ord),
    answer: answerText(note, ord),
  }
}

function buildMc(note: Note, allNotes: Note[], i: number, rng: () => number): McQuestion {
  const ord = firstOrd(note)
  const correct = answerText(note, ord)
  const otherAnswers = [...new Set(allNotes.filter(n => n.id !== note.id).map(n => answerText(n, firstOrd(n))))].filter(
    a => a !== correct
  )
  const distractors = shuffle(otherAnswers, rng).slice(0, 3)
  const options = shuffle([correct, ...distractors], rng)
  return {
    id: `mc-${i}`,
    type: 'mc',
    noteId: note.id,
    prompt: termText(note, ord),
    options,
    correctIndex: options.indexOf(correct),
  }
}

function buildTf(note: Note, allNotes: Note[], i: number, rng: () => number): TfQuestion {
  const ord = firstOrd(note)
  const term = termText(note, ord)
  const ownDefinition = answerText(note, ord)
  const others = allNotes.filter(n => n.id !== note.id)
  const wantTrue = rng() < 0.5 || others.length === 0

  if (wantTrue) {
    return { id: `tf-${i}`, type: 'tf', noteId: note.id, term, definition: ownDefinition, isTrue: true, definitionNoteId: note.id }
  }

  const other = others[Math.floor(rng() * others.length)]
  const otherOrd = firstOrd(other)
  return {
    id: `tf-${i}`,
    type: 'tf',
    noteId: note.id,
    term,
    definition: answerText(other, otherOrd),
    isTrue: false,
    definitionNoteId: other.id,
  }
}

function buildMatching(notes: Note[], count: number, rng: () => number): MatchingSection | null {
  const n = Math.min(count, notes.length)
  if (n <= 0) return null
  const chosen = shuffle(notes, rng).slice(0, n)
  const pairs = chosen.map(note => {
    const ord = firstOrd(note)
    return { noteId: note.id, term: termText(note, ord), definition: answerText(note, ord) }
  })
  return {
    id: 'matching',
    type: 'matching',
    pairs,
    definitions: shuffle(pairs.map(p => p.definition), rng),
  }
}

export function generateTest(notes: Note[], counts: TestCounts, rng: () => number): TestPaper {
  const writtenPool = shuffle(notes, rng).slice(0, Math.max(0, Math.min(counts.written, notes.length)))
  const written = writtenPool.map((note, i) => buildWritten(note, i))

  const mcPool = shuffle(notes, rng).slice(0, Math.max(0, Math.min(counts.mc, notes.length)))
  const mc = mcPool.map((note, i) => buildMc(note, notes, i, rng))

  const tfPool = shuffle(notes, rng).slice(0, Math.max(0, Math.min(counts.tf, notes.length)))
  const tf = tfPool.map((note, i) => buildTf(note, notes, i, rng))

  const matching = buildMatching(notes, counts.matching, rng)

  return { written, mc, tf, matching }
}

export function gradePaper(paper: TestPaper, answers: TestAnswers): TestResult {
  const sections: SectionResult[] = []
  const weakest: WeakItem[] = []

  let writtenCorrect = 0
  for (const q of paper.written) {
    const given = answers.written[q.id] ?? ''
    const result = grade(q.answer, given)
    if (result === 'wrong') {
      weakest.push({ noteId: q.noteId, term: q.prompt, expected: q.answer, given })
    } else {
      writtenCorrect++
    }
  }
  sections.push({ type: 'written', correct: writtenCorrect, total: paper.written.length })

  let mcCorrect = 0
  for (const q of paper.mc) {
    const given = answers.mc[q.id]
    if (given === q.correctIndex) {
      mcCorrect++
    } else {
      weakest.push({
        noteId: q.noteId,
        term: q.prompt,
        expected: q.options[q.correctIndex],
        given: given != null ? q.options[given] ?? '' : '',
      })
    }
  }
  sections.push({ type: 'mc', correct: mcCorrect, total: paper.mc.length })

  let tfCorrect = 0
  for (const q of paper.tf) {
    const given = answers.tf[q.id]
    if (given === q.isTrue) {
      tfCorrect++
    } else {
      weakest.push({
        noteId: q.noteId,
        term: q.term,
        expected: q.isTrue ? 'true' : 'false',
        given: given == null ? '' : given ? 'true' : 'false',
      })
    }
  }
  sections.push({ type: 'tf', correct: tfCorrect, total: paper.tf.length })

  let matchingCorrect = 0
  const matchingTotal = paper.matching?.pairs.length ?? 0
  if (paper.matching) {
    for (const pair of paper.matching.pairs) {
      const given = answers.matching[pair.noteId] ?? ''
      if (given === pair.definition) {
        matchingCorrect++
      } else {
        weakest.push({ noteId: pair.noteId, term: pair.term, expected: pair.definition, given })
      }
    }
  }
  sections.push({ type: 'matching', correct: matchingCorrect, total: matchingTotal })

  const totalCount = sections.reduce((sum, s) => sum + s.total, 0)
  const correctCount = sections.reduce((sum, s) => sum + s.correct, 0)
  const percent = totalCount === 0 ? 0 : Math.round((correctCount / totalCount) * 100)

  return { sections, correctCount, totalCount, percent, weakest }
}
