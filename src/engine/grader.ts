export function grade(expected: string, given: string): 'correct' | 'close' | 'wrong' {
  // Normalize: trim, case-fold, strip diacritics (NFD + remove combining marks), collapse whitespace
  const normalize = (s: string): string => {
    return s
      .trim()
      .toLowerCase()
      .normalize('NFD')
      .replace(/\p{M}/gu, '') // remove combining marks
      .replace(/\s+/g, ' ') // collapse internal whitespace to single space
  }

  const normExpected = normalize(expected)
  const normGiven = normalize(given)

  // Exact match
  if (normExpected === normGiven) {
    return 'correct'
  }

  // Levenshtein distance 1 on long answers (≥5 chars)
  if (normExpected.length >= 5 && levenshteinDistance(normExpected, normGiven) === 1) {
    return 'close'
  }

  return 'wrong'
}

// Classic two-row Levenshtein distance
function levenshteinDistance(s: string, t: string): number {
  const m = s.length
  const n = t.length

  // Two-row DP approach
  let prev = Array(n + 1)
    .fill(0)
    .map((_, i) => i)
  let curr = Array(n + 1).fill(0)

  for (let i = 1; i <= m; i++) {
    curr[0] = i
    for (let j = 1; j <= n; j++) {
      const cost = s[i - 1] === t[j - 1] ? 0 : 1
      curr[j] = Math.min(
        curr[j - 1] + 1, // insertion
        prev[j] + 1, // deletion
        prev[j - 1] + cost // substitution
      )
    }
    ;[prev, curr] = [curr, prev]
  }

  return prev[n]
}
