import { useEffect, useState } from 'react'
import { db } from '@/data/db'
import { renderCloze } from '@/engine/cloze'
import { speak } from '@/lib/tts'
import type { Note } from '@/data/types'

interface CardFaceProps {
  note: Note
  ord: number
  revealed: boolean
  lang?: string
}

function SpeakerIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
      <path d="M4 9v6h4l5 4V5L8 9H4z" />
      <path d="M17 8a5 5 0 0 1 0 8" />
    </svg>
  )
}

function useImageUrl(imageId?: string): string | null {
  const [url, setUrl] = useState<string | null>(null)

  useEffect(() => {
    if (!imageId) {
      setUrl(null)
      return
    }
    let objectUrl: string | null = null
    db.media.get(imageId).then(media => {
      if (media?.blob) {
        objectUrl = URL.createObjectURL(media.blob)
        setUrl(objectUrl)
      }
    })
    return () => {
      if (objectUrl) URL.revokeObjectURL(objectUrl)
    }
  }, [imageId])

  return url
}

export default function CardFace({ note, ord, revealed, lang }: CardFaceProps) {
  const imageUrl = useImageUrl(note.fields.imageId)
  const isCloze = note.type === 'cloze'

  const text = isCloze
    ? renderCloze(note.fields.term, ord, revealed)
    : revealed
      ? note.fields.definition
      : note.fields.term

  const speakText = isCloze ? renderCloze(note.fields.term, ord, true) : text

  return (
    <div className="card-face">
      <div className="card-face-text">{text}</div>
      {imageUrl && <img className="card-face-image" src={imageUrl} alt="" />}
      {revealed && note.fields.example && <div className="card-face-example">{note.fields.example}</div>}
      <button
        className="btn-icon card-face-speak"
        onClick={() => speak(speakText, lang)}
        aria-label="Play pronunciation"
      >
        <SpeakerIcon />
      </button>
    </div>
  )
}
