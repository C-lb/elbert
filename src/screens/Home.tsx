import { useEffect, useState } from 'react'
import { dueCounts } from '@/engine/queue'
import DeckList from '@/screens/DeckList'
import QuickCapture from '@/components/QuickCapture'

interface HomeProps {
  onStudy: (deckId?: string) => void
  onOpenDeck: (deckId: string) => void
}

function PlusIcon() {
  return (
    <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
      <path d="M12 5v14M5 12h14" />
    </svg>
  )
}

export default function Home({ onStudy, onOpenDeck }: HomeProps) {
  const [due, setDue] = useState<number | null>(null)
  const [capturing, setCapturing] = useState(false)
  const [toast, setToast] = useState(false)

  const refreshDue = () => {
    dueCounts().then(counts => setDue(counts.due + counts.newAvailable))
  }

  useEffect(() => {
    refreshDue()
  }, [])

  useEffect(() => {
    if (!toast) return
    const t = setTimeout(() => setToast(false), 2000)
    return () => clearTimeout(t)
  }, [toast])

  return (
    <div className="screen">
      <div className="due-hero">
        <div className="due-number">{due === null ? '–' : due}</div>
        <div className="due-label">cards due today</div>
        <button className="btn btn-accent btn-block" onClick={() => onStudy()}>
          Study now
        </button>
      </div>

      <DeckList onOpenDeck={onOpenDeck} />

      <button className="fab" onClick={() => setCapturing(true)} aria-label="Quick capture">
        <PlusIcon />
      </button>

      {capturing && (
        <QuickCapture
          onClose={() => setCapturing(false)}
          onSaved={() => {
            setCapturing(false)
            refreshDue()
            setToast(true)
          }}
        />
      )}

      {toast && <div className="toast toast-success">Card saved to Inbox</div>}
    </div>
  )
}
