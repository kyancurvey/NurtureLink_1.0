import { defineConfig } from 'vite';
import { VitePWA } from 'vite-plugin-pwa';

const base = '/NurtureLink_1.0/';

export default defineConfig({
  base,
  // Plain JSX without an extra plugin; keeps the dependency list to the approved set.
  esbuild: { jsx: 'automatic' },
  plugins: [
    VitePWA({
      registerType: 'autoUpdate',
      includeAssets: ['favicon.png', 'apple-touch-icon.png', 'logo.png'],
      manifest: {
        name: 'NurtureLink',
        short_name: 'NurtureLink',
        description: 'Stay connected with your health worker and midwife during pregnancy.',
        lang: 'en',
        theme_color: '#65428D',
        background_color: '#FFFFFF',
        display: 'standalone',
        start_url: base,
        scope: base,
        icons: [
          { src: 'pwa-192x192.png', sizes: '192x192', type: 'image/png', purpose: 'any' },
          { src: 'pwa-512x512.png', sizes: '512x512', type: 'image/png', purpose: 'any' },
          { src: 'pwa-maskable-512x512.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' },
        ],
      },
      workbox: {
        // App shell, images and the self-hosted font files work with the network off (COM-07, COM-08).
        globPatterns: ['**/*.{js,css,html,png,woff2}'],
        cleanupOutdatedCaches: true,
      },
    }),
  ],
});
