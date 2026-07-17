const RE = /\{\{c(\d+)::(.*?)(?:::(.*?))?\}\}/g

export function parseCloze(text: string) {
  const seen = new Map<number, { ord: number; hint?: string }>()
  for (const m of text.matchAll(RE)) {
    const ord = Number(m[1])
    if (!seen.has(ord)) seen.set(ord, m[3] ? { ord, hint: m[3] } : { ord })
  }
  return [...seen.values()].sort((a, b) => a.ord - b.ord)
}

export function renderCloze(text: string, ord: number, revealed: boolean) {
  return text.replace(RE, (_, n, answer, hint) =>
    Number(n) === ord && !revealed ? `[${hint ?? '...'}]` : answer)
}
