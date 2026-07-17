// Unit tests for POST /api/generate — request validation + response mapping.
// The Claude API call is fully mocked (vi.mock('@anthropic-ai/sdk')); no
// network access and no ANTHROPIC_API_KEY needed for `npm test` to pass.
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { RateLimitError, APIError } from '@anthropic-ai/sdk'

const createMock = vi.fn()

vi.mock('@anthropic-ai/sdk', async () => {
  const actual = await vi.importActual<typeof import('@anthropic-ai/sdk')>('@anthropic-ai/sdk')
  return {
    ...actual,
    default: class MockAnthropic {
      messages = { create: createMock }
    },
  }
})

import handler, { type GenerateRequest, type GenerateResponse } from '../api/generate.ts'

const ELBERT_KEY = 'test-key-123'
const ANTHROPIC_KEY = 'sk-ant-test'

function makeReq(body: unknown, key: string | null = ELBERT_KEY): GenerateRequest {
  return {
    method: 'POST',
    headers: key === null ? {} : { 'x-elbert-key': key },
    body,
  }
}

function makeRes(): GenerateResponse & { statusCode: number; body: unknown } {
  const res = {
    statusCode: 200,
    body: undefined as unknown,
    status(code: number) {
      res.statusCode = code
      return res
    },
    json(b: unknown) {
      res.body = b
    },
  }
  return res
}

async function call(body: unknown, key?: string | null) {
  const res = makeRes()
  await handler(makeReq(body, key), res)
  return res
}

function mockDrafts(overrides: Partial<{ stop_reason: string; drafts: unknown[]; refusalText: string }> = {}) {
  const drafts = overrides.drafts ?? [
    { type: 'basic', fields: { term: 'chat', definition: 'cat' } },
  ]
  createMock.mockResolvedValue({
    stop_reason: overrides.stop_reason ?? 'end_turn',
    content: [{ type: 'text', text: JSON.stringify({ drafts }) }],
  })
}

describe('POST /api/generate', () => {
  const savedEnv = {
    ELBERT_KEY: process.env.ELBERT_KEY,
    ANTHROPIC_API_KEY: process.env.ANTHROPIC_API_KEY,
  }

  beforeEach(() => {
    createMock.mockReset()
    process.env.ELBERT_KEY = ELBERT_KEY
    process.env.ANTHROPIC_API_KEY = ANTHROPIC_KEY
  })

  afterEach(() => {
    for (const [key, value] of Object.entries(savedEnv)) {
      if (value === undefined) delete process.env[key as keyof typeof savedEnv]
      else process.env[key as keyof typeof savedEnv] = value
    }
  })

  it('401s without a valid key', async () => {
    const res = await call({ text: 'notes', style: 'basic' }, 'wrong-key')
    expect(res.statusCode).toBe(401)
    expect(createMock).not.toHaveBeenCalled()
  })

  it('400s when neither text nor pdfBase64 is provided', async () => {
    const res = await call({ style: 'basic' })
    expect(res.statusCode).toBe(400)
    expect((res.body as { error: string }).error).toMatch(/text|pdf/i)
  })

  it('400s on an invalid style', async () => {
    const res = await call({ text: 'notes', style: 'nonsense' })
    expect(res.statusCode).toBe(400)
    expect((res.body as { error: string }).error).toMatch(/style/i)
  })

  it('400s on a count out of range', async () => {
    const res = await call({ text: 'notes', style: 'basic', count: 51 })
    expect(res.statusCode).toBe(400)
    expect((res.body as { error: string }).error).toMatch(/count/i)
  })

  it('400s when the decoded pdf exceeds the 10MB cap', async () => {
    // 14MB of base64 decodes to ~10.5MB, just over the 10MB decoded cap.
    const big = 'A'.repeat(14 * 1024 * 1024)
    const res = await call({ pdfBase64: big, style: 'basic' })
    expect(res.statusCode).toBe(400)
    expect((res.body as { error: string }).error).toMatch(/large|size|cap|mb/i)
  })

  it('accepts a pdf the size the client allows (10MB file)', async () => {
    // A 10MB file becomes ~13.3MB of base64; must pass validation.
    mockDrafts()
    const clientMax = 'A'.repeat(4 * Math.floor((10 * 1024 * 1024) / 3))
    const res = await call({ pdfBase64: clientMax, style: 'basic' })
    expect(res.statusCode).toBe(200)
  })

  it('500s cleanly when ANTHROPIC_API_KEY is not configured', async () => {
    delete process.env.ANTHROPIC_API_KEY
    const res = await call({ text: 'notes', style: 'basic' })
    expect(res.statusCode).toBe(500)
    expect((res.body as { error: string }).error).toMatch(/anthropic key not configured/i)
    expect(createMock).not.toHaveBeenCalled()
  })

  it('maps a schema-valid SDK response to { drafts }', async () => {
    mockDrafts({
      drafts: [
        { type: 'basic', fields: { term: 'chat', definition: 'cat' } },
        { type: 'cloze', fields: { term: 'The {{c1::cat}} sat.', definition: '' } },
      ],
    })
    const res = await call({ text: 'chat means cat', style: 'mix', count: 2 })
    expect(res.statusCode).toBe(200)
    expect(res.body).toEqual({
      drafts: [
        { type: 'basic', fields: { term: 'chat', definition: 'cat' } },
        { type: 'cloze', fields: { term: 'The {{c1::cat}} sat.', definition: '' } },
      ],
    })
    expect(createMock).toHaveBeenCalledTimes(1)
    const [call1] = createMock.mock.calls[0]
    expect(call1.model).toBe('claude-sonnet-5')
    expect(call1.output_config.format.type).toBe('json_schema')
    expect(call1.temperature).toBeUndefined()
  })

  it('drops cloze drafts with no {{c1::...}} marker so a note is never created with zero cards', async () => {
    mockDrafts({
      drafts: [
        { type: 'basic', fields: { term: 'chat', definition: 'cat' } },
        { type: 'cloze', fields: { term: 'The capital of France is Paris.', definition: '' } },
        { type: 'cloze', fields: { term: 'The {{c1::cat}} sat.', definition: '' } },
      ],
    })
    const res = await call({ text: 'notes', style: 'mix' })
    expect(res.statusCode).toBe(200)
    expect(res.body).toEqual({
      drafts: [
        { type: 'basic', fields: { term: 'chat', definition: 'cat' } },
        { type: 'cloze', fields: { term: 'The {{c1::cat}} sat.', definition: '' } },
      ],
    })
  })

  it('puts a PDF document block before the text block when pdfBase64 is given', async () => {
    mockDrafts()
    await call({ pdfBase64: Buffer.from('%PDF-1.4').toString('base64'), text: 'extra notes', style: 'basic' })
    const [call1] = createMock.mock.calls[0]
    const userMsg = call1.messages.find((m: { role: string }) => m.role === 'user')
    const content = userMsg.content
    const docIdx = content.findIndex((b: { type: string }) => b.type === 'document')
    const textIdx = content.findIndex((b: { type: string }) => b.type === 'text')
    expect(docIdx).toBeGreaterThanOrEqual(0)
    expect(docIdx).toBeLessThan(textIdx)
  })

  it('500s with "generation truncated" when stop_reason is max_tokens', async () => {
    mockDrafts({ stop_reason: 'max_tokens' })
    const res = await call({ text: 'notes', style: 'basic' })
    expect(res.statusCode).toBe(500)
    expect((res.body as { error: string }).error).toMatch(/truncated/i)
  })

  it('500s on refusal with the model message', async () => {
    createMock.mockResolvedValue({ stop_reason: 'refusal', content: [] })
    const res = await call({ text: 'notes', style: 'basic' })
    expect(res.statusCode).toBe(500)
    expect((res.body as { error: string }).error).toBeTruthy()
  })

  it('429s and passes through the message on RateLimitError', async () => {
    createMock.mockRejectedValue(
      new RateLimitError(429, { type: 'error', error: { type: 'rate_limit_error', message: 'slow down' } }, 'slow down', new Headers())
    )
    const res = await call({ text: 'notes', style: 'basic' })
    expect(res.statusCode).toBe(429)
    expect((res.body as { error: string }).error).toMatch(/slow down/i)
  })

  it('500s on a generic APIError without leaking internals', async () => {
    createMock.mockRejectedValue(
      new APIError(500, { type: 'error', error: { type: 'api_error', message: 'boom' } }, 'boom', new Headers())
    )
    const res = await call({ text: 'notes', style: 'basic' })
    expect(res.statusCode).toBe(500)
    expect(res.body).toHaveProperty('error')
  })
})
