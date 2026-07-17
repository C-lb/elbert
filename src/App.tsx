import { useEffect, useState } from 'react'
import Nav from '@/components/Nav'
import Home from '@/screens/Home'
import Settings from '@/screens/Settings'
import Study from '@/screens/Study'
import Learn from '@/screens/Learn'
import TestMode from '@/screens/TestMode'
import Match from '@/screens/Match'
import Editor from '@/screens/Editor'
import DeckSettings from '@/screens/DeckSettings'
import Import from '@/screens/Import'
import Generate from '@/screens/Generate'
import { requestSync, useSyncStatus } from '@/sync/status'

interface Route {
  name: 'home' | 'study' | 'learn' | 'test' | 'match' | 'edit' | 'deck' | 'settings' | 'import' | 'generate'
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
    case 'deck':
      return { name: 'deck', deckId: param }
    case 'settings':
      return { name: 'settings' }
    case 'import':
      return { name: 'import' }
    case 'generate':
      return { name: 'generate' }
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
  deck: 'Deck settings',
  settings: 'Settings',
  import: 'Import',
  generate: 'Generate with AI',
}

function App() {
  const route = useRoute()
  const { pending } = useSyncStatus()

  useEffect(() => {
    requestSync()
    window.addEventListener('online', requestSync)
    return () => window.removeEventListener('online', requestSync)
  }, [])

  const body = (() => {
    switch (route.name) {
      case 'home':
        return (
          <Home
            onStudy={deckId => navigate(deckId ? `#/study/${deckId}` : '#/study')}
            onOpenDeck={deckId => navigate(`#/study/${deckId}`)}
            onImport={() => navigate('#/import')}
            onGenerate={() => navigate('#/generate')}
          />
        )
      case 'settings':
        return <Settings />
      case 'import':
        return <Import />
      case 'generate':
        return <Generate />
      case 'study':
        return <Study deckId={route.deckId} />
      case 'learn':
        return <Learn deckId={route.deckId} />
      case 'test':
        return <TestMode deckId={route.deckId} />
      case 'match':
        return <Match deckId={route.deckId} />
      case 'edit':
        return route.deckId ? (
          <Editor deckId={route.deckId} onOpenSettings={id => navigate(`#/deck/${id}`)} />
        ) : (
          <NotBuilt label="Deck editor" />
        )
      case 'deck':
        return route.deckId ? (
          <DeckSettings
            deckId={route.deckId}
            onDeleted={() => navigate('#/')}
            onBack={() => navigate(`#/edit/${route.deckId}`)}
          />
        ) : (
          <NotBuilt label="Deck settings" />
        )
    }
  })()

  return (
    <div className="app-shell">
      <Nav
        title={TITLES[route.name]}
        onBack={route.name === 'home' ? undefined : () => navigate('#/')}
        onSettings={route.name === 'home' ? () => navigate('#/settings') : undefined}
        pendingSync={pending}
      />
      {body}
    </div>
  )
}

export default App
