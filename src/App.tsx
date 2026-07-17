import { useEffect, useState } from 'react'
import Nav from '@/components/Nav'
import Home from '@/screens/Home'
import Settings from '@/screens/Settings'

interface Route {
  name: 'home' | 'study' | 'learn' | 'test' | 'match' | 'edit' | 'generate' | 'settings'
  deckId?: string
}

function parseHash(hash: string): Route {
  const path = hash.replace(/^#\/?/, '')
  const [segment, param] = path.split('/')

  switch (segment) {
    case '':
      return { name: 'home' }
    case 'study':
      return { name: 'study', deckId: param }
    case 'learn':
      return { name: 'learn', deckId: param }
    case 'test':
      return { name: 'test', deckId: param }
    case 'match':
      return { name: 'match', deckId: param }
    case 'edit':
      return { name: 'edit', deckId: param }
    case 'generate':
      return { name: 'generate' }
    case 'settings':
      return { name: 'settings' }
    default:
      return { name: 'home' }
  }
}

function useRoute(): Route {
  const [route, setRoute] = useState(() => parseHash(window.location.hash))

  useEffect(() => {
    const onChange = () => setRoute(parseHash(window.location.hash))
    window.addEventListener('hashchange', onChange)
    return () => window.removeEventListener('hashchange', onChange)
  }, [])

  return route
}

function navigate(hash: string) {
  window.location.hash = hash
}

function NotBuilt({ label }: { label: string }) {
  return (
    <div className="screen">
      <div className="stub">{label} is not built yet.</div>
    </div>
  )
}

const TITLES: Record<Route['name'], string> = {
  home: 'Elbert',
  study: 'Study',
  learn: 'Learn',
  test: 'Test',
  match: 'Match',
  edit: 'Edit deck',
  generate: 'Generate cards',
  settings: 'Settings',
}

function App() {
  const route = useRoute()

  const body = (() => {
    switch (route.name) {
      case 'home':
        return (
          <Home
            onStudy={deckId => navigate(deckId ? `#/study/${deckId}` : '#/study')}
            onOpenDeck={deckId => navigate(`#/study/${deckId}`)}
            onCapture={() => navigate('#/generate')}
          />
        )
      case 'settings':
        return <Settings />
      case 'study':
        return <NotBuilt label="Study" />
      case 'learn':
        return <NotBuilt label="Learn mode" />
      case 'test':
        return <NotBuilt label="Test mode" />
      case 'match':
        return <NotBuilt label="Match mode" />
      case 'edit':
        return <NotBuilt label="Deck editor" />
      case 'generate':
        return <NotBuilt label="Card generator" />
    }
  })()

  return (
    <div className="app-shell">
      <Nav
        title={TITLES[route.name]}
        onBack={route.name === 'home' ? undefined : () => navigate('#/')}
        onSettings={route.name === 'home' ? () => navigate('#/settings') : undefined}
      />
      {body}
    </div>
  )
}

export default App
