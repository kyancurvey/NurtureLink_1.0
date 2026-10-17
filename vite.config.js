import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { VitePWA } from 'vite-plugin-pwa'

// GitHub Pages serves this project at /NurtureLink_1.0/, so every asset path,
// the PWA scope and the PWA start_url must live under this base.
const BASE = '/NurtureLink_1.0/'

export default defineConfig({
  base: BASE,
  plugins: [
    react(),
    VitePWA({
      registerType: 'autoUpdate',
      includeAssets: ['favicon.png', 'apple-touch-icon.png', 'logo.png'],
      manifest: {
        name: 'NurtureLink',
        short_name: 'NurtureLink',
        description: 'Nurture Lives, Linking Hearts',
        theme_color: '#5B3986', // deep purple sampled from the logo
        background_color: '#FFFFFF',
        display: 'standalone',
        orientation: 'portrait',
        start_url: BASE,
        scope: BASE,
        id: BASE,
        icons: [
          { src: 'pwa-192x192.png', sizes: '192x192', type: 'image/png', purpose: 'any' },
          { src: 'pwa-512x512.png', sizes: '512x512', type: 'image/png', purpose: 'any' },
          { src: 'pwa-maskable-512x512.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' },
        ],
      },
      // App-shell caching only: the built HTML, JS, CSS and images are
      // precached. No runtime caching rule exists, so Supabase API calls
      // (auth, patient data) are never stored by the service worker.
      workbox: {
        globPatterns: ['**/*.{js,css,html,png,svg,ico,webmanifest}'],
        navigateFallback: `${BASE}index.html`,
        cleanupOutdatedCaches: true,
      },
    }),
  ],
})
