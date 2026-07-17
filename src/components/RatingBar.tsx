import type { Rating } from '@/data/types'

interface RatingBarProps {
  labels: { 1: string; 2: string; 3: string; 4: string }
  onRate: (rating: Rating) => void
  disabled?: boolean
}

const RATINGS: { rating: Rating; text: string; tone: string }[] = [
  { rating: 1, text: 'Again', tone: 'rating-again' },
  { rating: 2, text: 'Hard', tone: 'rating-hard' },
  { rating: 3, text: 'Good', tone: 'rating-good' },
  { rating: 4, text: 'Easy', tone: 'rating-easy' },
]

export default function RatingBar({ labels, onRate, disabled }: RatingBarProps) {
  return (
    <div className="rating-bar">
      {RATINGS.map(({ rating, text, tone }) => (
        <button
          key={rating}
          className={`rating-btn ${tone}`}
          onClick={() => onRate(rating)}
          disabled={disabled}
        >
          <span className="rating-text">{text}</span>
          <span className="rating-interval">{labels[rating]}</span>
        </button>
      ))}
    </div>
  )
}
