import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'
import { VitePWA } from 'vite-plugin-pwa'
import path from 'path'

export default defineConfig({
  plugins: [
    react(),
    VitePWA({
      registerType: 'autoUpdate',
      manifest: {
        name: 'Elbert', short_name: 'Elbert', display: 'standalone',
        background_color: '#111113', theme_color: '#111113',
        icons: [{ src: '/icon-512.png', sizes: '512x512', type: 'image/png' }],
      },
    }),
  ],
  resolve: { alias: { '@': path.resolve(__dirname, 'src') } },
  test: { environment: 'node', exclude: ['e2e/**', 'node_modules/**'] },
})
