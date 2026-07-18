import React, { Suspense, useEffect, useState } from 'react'
import { getSettings } from '@/lib/settings'

const ShaderGradientInner = React.lazy(() => import('./ShaderGradientInner'))

interface ShaderBackdropProps {
  deckId: string
}

interface ShaderErrorBoundaryState {
  hasError: boolean
}

// A WebGL failure (unsupported context, driver crash, etc.) must never break
// studying, so any error inside the shader tree is swallowed and renders null.
class ShaderErrorBoundary extends React.Component<{ children: React.ReactNode }, ShaderErrorBoundaryState> {
  state: ShaderErrorBoundaryState = { hasError: false }

  static getDerivedStateFromError(): ShaderErrorBoundaryState {
    return { hasError: true }
  }

  componentDidCatch() {
    // Swallow: a decorative backdrop is never worth surfacing an error UI.
  }

  render() {
    if (this.state.hasError) return null
    return this.props.children
  }
}

export default function ShaderBackdrop({ deckId }: ShaderBackdropProps) {
  const [allowed, setAllowed] = useState(false)
  const [visible, setVisible] = useState(() => document.visibilityState !== 'hidden')

  useEffect(() => {
    let cancelled = false
    // The gradient shows regardless of prefers-reduced-motion — it's a wanted
    // visual, not incidental motion, so we don't gate it on the OS setting.
    getSettings().then(settings => {
      if (!cancelled && settings.shaderEnabled) setAllowed(true)
    })
    return () => {
      cancelled = true
    }
  }, [])

  useEffect(() => {
    const onVisibility = () => setVisible(document.visibilityState !== 'hidden')
    document.addEventListener('visibilitychange', onVisibility)
    return () => document.removeEventListener('visibilitychange', onVisibility)
  }, [])

  // Unmounting the canvas (rather than trying to pause the r3f render loop,
  // which shadergradient doesn't expose a prop for) is the reliable way to
  // stop GPU work while the tab is hidden.
  if (!allowed || !visible) return null

  return (
    <div className="shader-backdrop" aria-hidden="true">
      <ShaderErrorBoundary>
        <Suspense fallback={null}>
          <ShaderGradientInner deckId={deckId} />
        </Suspense>
      </ShaderErrorBoundary>
      <div className="shader-backdrop-scrim" />
    </div>
  )
}
