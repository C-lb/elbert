function supported(): boolean {
  return typeof window !== 'undefined' && 'speechSynthesis' in window
}

export function bestVoice(lang?: string): SpeechSynthesisVoice | null {
  if (!supported()) return null
  const voices = window.speechSynthesis.getVoices()
  if (!voices.length) return null
  if (!lang) return voices.find(v => v.default) ?? voices[0]

  const exact = voices.find(v => v.lang.toLowerCase() === lang.toLowerCase())
  if (exact) return exact

  const base = lang.split('-')[0].toLowerCase()
  const partial = voices.find(v => v.lang.toLowerCase().startsWith(base))
  if (partial) return partial

  return voices.find(v => v.default) ?? voices[0]
}

export function speak(text: string, lang?: string): void {
  if (!supported() || !text.trim()) return

  const utterance = new SpeechSynthesisUtterance(text)
  const voice = bestVoice(lang)
  if (voice) {
    utterance.voice = voice
    utterance.lang = voice.lang
  } else if (lang) {
    utterance.lang = lang
  }

  window.speechSynthesis.cancel()
  window.speechSynthesis.speak(utterance)
}
