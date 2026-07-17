import { useEffect, useState } from 'react'
import { getSettings, saveSettings } from '@/lib/settings'

export default function Settings() {
  const [syncKey, setSyncKey] = useState('')
  const [shaderEnabled, setShaderEnabled] = useState(true)
  const [saved, setSaved] = useState(false)

  useEffect(() => {
    getSettings().then(s => {
      setSyncKey(s.syncKey)
      setShaderEnabled(s.shaderEnabled)
    })
  }, [])

  const save = async () => {
    await saveSettings({ syncKey, shaderEnabled })
    setSaved(true)
    setTimeout(() => setSaved(false), 1200)
  }

  return (
    <div className="screen">
      <div className="form-field">
        <label htmlFor="sync-key">Sync key</label>
        <input
          id="sync-key"
          className="field"
          value={syncKey}
          onChange={e => setSyncKey(e.target.value)}
          placeholder="Paste your sync key"
        />
        <div className="hint">Used to sync your decks across devices.</div>
      </div>

      <div className="form-field">
        <label>
          <input
            type="checkbox"
            checked={shaderEnabled}
            onChange={e => setShaderEnabled(e.target.checked)}
          />{' '}
          Enable background shader
        </label>
        <div className="hint">Turn off if animations feel slow on this device.</div>
      </div>

      <button className="btn btn-accent" onClick={save}>
        {saved ? 'Saved' : 'Save settings'}
      </button>
    </div>
  )
}
