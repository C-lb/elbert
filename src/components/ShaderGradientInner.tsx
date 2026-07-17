import { ShaderGradient, ShaderGradientCanvas } from 'shadergradient'

interface ShaderGradientInnerProps {
  deckId: string
}

interface GradientPreset {
  type: 'plane' | 'sphere' | 'waterPlane'
  color1: string
  color2: string
  color3: string
}

// Four dim, dark presets in the blurple family + a neutral, so decks look
// distinct without ever fighting card text for contrast.
const PRESETS: GradientPreset[] = [
  { type: 'waterPlane', color1: '#5865f2', color2: '#2b2f77', color3: '#0f1030' },
  { type: 'plane', color1: '#7c5cf2', color2: '#3a2b77', color3: '#120f30' },
  { type: 'sphere', color1: '#5c8ff2', color2: '#2b4a77', color3: '#0f1c30' },
  { type: 'waterPlane', color1: '#8a8ea3', color2: '#3a3d4d', color3: '#131419' },
]

function hashDeckId(id: string): number {
  let h = 0
  for (let i = 0; i < id.length; i++) {
    h = (Math.imul(h, 31) + id.charCodeAt(i)) | 0
  }
  return Math.abs(h)
}

export default function ShaderGradientInner({ deckId }: ShaderGradientInnerProps) {
  const preset = PRESETS[hashDeckId(deckId) % PRESETS.length]

  return (
    <ShaderGradientCanvas style={{ position: 'absolute', inset: 0 }} pixelDensity={1}>
      <ShaderGradient
        control="props"
        type={preset.type}
        animate="on"
        uSpeed={0.15}
        uStrength={2.2}
        uDensity={1.2}
        uFrequency={5.5}
        uAmplitude={1}
        color1={preset.color1}
        color2={preset.color2}
        color3={preset.color3}
        brightness={0.85}
        reflection={0.08}
        grain="off"
        lightType="env"
        envPreset="city"
        cAzimuthAngle={180}
        cPolarAngle={90}
        cDistance={3.6}
        cameraZoom={1}
      />
    </ShaderGradientCanvas>
  )
}
