import { repo } from '@/data/repo'

export interface Settings {
  syncKey: string
  shaderEnabled: boolean
}

const DEFAULTS: Settings = {
  syncKey: '',
  shaderEnabled: true,
}

const KEYS: { [K in keyof Settings]: string } = {
  syncKey: 'settings:syncKey',
  shaderEnabled: 'settings:shaderEnabled',
}

export async function getSettings(): Promise<Settings> {
  const [syncKey, shaderEnabled] = await Promise.all([
    repo.getMeta<string>(KEYS.syncKey),
    repo.getMeta<boolean>(KEYS.shaderEnabled),
  ])
  return {
    syncKey: syncKey ?? DEFAULTS.syncKey,
    shaderEnabled: shaderEnabled ?? DEFAULTS.shaderEnabled,
  }
}

export async function saveSettings(patch: Partial<Settings>): Promise<void> {
  const entries = Object.entries(patch) as [keyof Settings, Settings[keyof Settings]][]
  await Promise.all(entries.map(([key, value]) => repo.setMeta(KEYS[key], value)))
}
