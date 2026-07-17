// POST /api/generate: AI card generation from notes text and/or a PDF, via
// the Claude API (`@anthropic-ai/sdk`, model claude-sonnet-5).
//
// Auth: header `x-elbert-key` must strictly equal env ELBERT_KEY (assertKey(),
// same as /api/sync), else 401.
//
// Wire contract:
//   Request  body: { text?: string, pdfBase64?: string,
//                     style: 'basic' | 'basic_reversed' | 'cloze' | 'mix',
//                     count?: number (1-50, default 20) }
//   Response body: { drafts: { type: NoteType, fields: { term, definition,
//                     example?, hint? } }[] }
//
// Structured output (controller-approved deviation from tool-forced output in
// the original brief): `output_config: { format: { type: 'json_schema',
// schema: DRAFTS_SCHEMA }, effort: 'medium' }` on `messages.create`. The SDK
// guarantees the response text block is schema-valid JSON, so parsing is a
// plain JSON.parse, no manual validation of the model's output shape (aside
// from the cloze-marker filter below, which the schema can't express).
//
// The Anthropic client is constructed lazily *inside* the handler (never at
// module load) so importing this file with no ANTHROPIC_API_KEY set never
// throws: mirrors the api/_lib/pg.ts lazy-getDb() pattern that fixed the
// prod incident where a static top-level import 500'd every request,
// including ones that should 401 before ever touching an external service.
import Anthropic, { APIError, RateLimitError } from '@anthropic-ai/sdk'
import { assertKey, UnauthorizedError } from './_lib/auth.js'

export type NoteType = 'basic' | 'basic_reversed' | 'cloze'

export interface Draft {
  type: NoteType
  fields: {
    term: string
    definition: string
    example?: string
    hint?: string
  }
}

const MODEL = 'claude-sonnet-5'
const MAX_TOKENS = 16000
// The binding cap is 10MB of decoded PDF bytes, matching the client's file
// size check. The base64 length pre-check is that cap inflated by ~4/3
// (base64 grows relative to raw bytes) so oversized payloads are rejected
// cheaply before any decode math. Keeps the overall request comfortably
// under Anthropic's ~32MB request limit.
const MAX_PDF_DECODED_BYTES = 10 * 1024 * 1024
const MAX_PDF_BASE64_LENGTH = 14 * 1024 * 1024

// Anki cloze syntax: {{c1::answer}}, optionally {{c1::answer::hint}}.
const CLOZE_MARKER_RE = /\{\{c\d+::.*?\}\}/

const STYLES = ['basic', 'basic_reversed', 'cloze', 'mix'] as const
type Style = (typeof STYLES)[number]

function isStyle(value: unknown): value is Style {
  return typeof value === 'string' && (STYLES as readonly string[]).includes(value)
}

// No minLength/maxLength/minItems/maxItems, unsupported by structured
// outputs. Every object carries additionalProperties: false + required.
const DRAFTS_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['drafts'],
  properties: {
    drafts: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['type', 'fields'],
        properties: {
          type: { type: 'string', enum: ['basic', 'basic_reversed', 'cloze'] },
          fields: {
            type: 'object',
            additionalProperties: false,
            required: ['term', 'definition'],
            properties: {
              term: { type: 'string' },
              definition: { type: 'string' },
              example: { type: 'string' },
              hint: { type: 'string' },
            },
          },
        },
      },
    },
  },
}

export class ValidationError extends Error {
  statusCode = 400
}

interface GenerateRequestBody {
  text?: string
  pdfBase64?: string
  style?: string
  count?: number
}

interface ValidatedInput {
  text?: string
  pdfBase64?: string
  style: Style
  count: number
}

function validateBody(body: GenerateRequestBody): ValidatedInput {
  const text = typeof body?.text === 'string' && body.text.trim() ? body.text : undefined
  const pdfBase64 = typeof body?.pdfBase64 === 'string' && body.pdfBase64 ? body.pdfBase64 : undefined

  if (!text && !pdfBase64) {
    throw new ValidationError('provide text and/or pdfBase64')
  }
  if (!isStyle(body?.style)) {
    throw new ValidationError(`style must be one of ${STYLES.join(', ')}`)
  }
  const count = body?.count === undefined ? 20 : Number(body.count)
  if (!Number.isInteger(count) || count < 1 || count > 50) {
    throw new ValidationError('count must be an integer between 1 and 50')
  }
  if (pdfBase64 && pdfBase64.length > MAX_PDF_BASE64_LENGTH) {
    throw new ValidationError('pdf exceeds the 10MB cap')
  }
  if (pdfBase64 && base64ByteLength(pdfBase64) > MAX_PDF_DECODED_BYTES) {
    throw new ValidationError('pdf exceeds the 10MB cap')
  }

  return { text, pdfBase64, style: body.style as Style, count }
}

function buildSystemPrompt(style: Style, count: number): string {
  const styleInstruction =
    style === 'mix'
      ? 'Choose whichever card type (basic, basic_reversed, or cloze) best suits each fact, use your judgement.'
      : `Every card must use the "${style}" type.`
  return [
    'You are a spaced-repetition card author. Turn the source material into atomic flashcards:',
    '- One fact or concept per card. Prefer many small cards over few dense ones.',
    '- "basic" cards: term is the prompt, definition is the answer.',
    '- "basic_reversed" cards: only when term and definition are genuinely symmetric (e.g. vocabulary pairs), the card will be tested in both directions.',
    '- "cloze" cards: put the full sentence in the term field, with the blanked span marked using Anki cloze syntax, e.g. "The capital of France is {{c1::Paris}}." A cloze card MUST contain at least one {{c1::...}} marker in the term field, or it will be discarded. Leave definition empty unless useful extra context belongs there.',
    '- "example" is an optional usage example or context sentence; "hint" is an optional nudge, not the answer.',
    styleInstruction,
    `Aim for about ${count} cards, fewer is fine if the material doesn't support that many; do not pad with redundant or trivial cards.`,
  ].join('\n')
}

function base64ByteLength(b64: string): number {
  const clean = b64.replace(/=+$/, '')
  return Math.floor((clean.length * 3) / 4)
}

/** Drops cloze drafts with no {{c1::...}} marker: they'd approve into a note with zero cards. */
function filterUnmarkedCloze(drafts: Draft[]): Draft[] {
  return drafts.filter(d => d.type !== 'cloze' || CLOZE_MARKER_RE.test(d.fields.term))
}

export interface GenerateRequest {
  method?: string
  headers: Record<string, string | string[] | undefined>
  body: unknown
}

export interface GenerateResponse {
  status(code: number): GenerateResponse
  json(body: unknown): void
}

function parseDrafts(text: string): Draft[] {
  const parsed = JSON.parse(text) as { drafts: Draft[] }
  return parsed.drafts
}

export default async function handler(req: GenerateRequest, res: GenerateResponse): Promise<void> {
  try {
    assertKey(req)
  } catch (err) {
    if (err instanceof UnauthorizedError) {
      res.status(401).json({ error: 'unauthorized' })
      return
    }
    throw err
  }

  if (req.method && req.method !== 'POST') {
    res.status(405).json({ error: 'method not allowed' })
    return
  }

  let body: GenerateRequestBody
  try {
    body = (typeof req.body === 'string' ? JSON.parse(req.body) : req.body) as GenerateRequestBody
  } catch {
    res.status(400).json({ error: 'malformed JSON body' })
    return
  }

  let input: ValidatedInput
  try {
    input = validateBody(body ?? {})
  } catch (err) {
    if (err instanceof ValidationError) {
      res.status(400).json({ error: err.message })
      return
    }
    throw err
  }

  const apiKey = process.env.ANTHROPIC_API_KEY
  if (!apiKey) {
    res.status(500).json({ error: 'anthropic key not configured' })
    return
  }

  const content: Anthropic.Messages.ContentBlockParam[] = []
  if (input.pdfBase64) {
    content.push({
      type: 'document',
      source: { type: 'base64', media_type: 'application/pdf', data: input.pdfBase64 },
    })
  }
  content.push({
    type: 'text',
    text: input.text ?? 'Generate cards from the attached PDF.',
  })

  const client = new Anthropic({ apiKey })

  let response
  try {
    response = await client.messages.create({
      model: MODEL,
      max_tokens: MAX_TOKENS,
      system: buildSystemPrompt(input.style, input.count),
      messages: [{ role: 'user', content }],
      output_config: {
        format: { type: 'json_schema', schema: DRAFTS_SCHEMA },
        effort: 'medium',
      },
    })
  } catch (err) {
    if (err instanceof RateLimitError) {
      res.status(429).json({ error: err.message })
      return
    }
    if (err instanceof APIError) {
      res.status(500).json({ error: err.message })
      return
    }
    throw err
  }

  if (response.stop_reason === 'max_tokens') {
    res.status(500).json({ error: 'generation truncated' })
    return
  }
  if (response.stop_reason === 'refusal') {
    const textBlock = response.content.find((b): b is Anthropic.Messages.TextBlock => b.type === 'text')
    res.status(500).json({ error: textBlock?.text || 'the model declined to generate cards' })
    return
  }

  const textBlock = response.content.find((b): b is Anthropic.Messages.TextBlock => b.type === 'text')
  if (!textBlock) {
    res.status(500).json({ error: 'no text content in model response' })
    return
  }

  let drafts: Draft[]
  try {
    drafts = parseDrafts(textBlock.text)
  } catch {
    res.status(500).json({ error: 'could not parse model response' })
    return
  }

  res.status(200).json({ drafts: filterUnmarkedCloze(drafts) })
}
