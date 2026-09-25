import { defineConfig } from 'vite';
import { VitePWA } from 'vite-plugin-pwa';

export default defineConfig({
  server: { port: 5173, proxy: { '/api': 'http://localhost:8787' } },
  plugins: [VitePWA({
    registerType: 'autoUpdate',
    includeAssets: ['favicon.svg'],
    manifest: {
      name: 'Kiwi Lens · NZ Navigation', short_name: 'Kiwi Lens', description: 'Route planning and road-safety awareness for New Zealand.',
      theme_color: '#0b1717', background_color: '#0b1717', display: 'standalone', start_url: '/app', scope: '/', orientation: 'portrait',
      icons: [{ src: '/favicon.svg', sizes: 'any', type: 'image/svg+xml', purpose: 'any maskable' }]
    },
    workbox: {
      navigateFallback: '/index.html',
      runtimeCaching: [
        { urlPattern: ({ url }) => url.pathname === '/api/cameras', handler: 'NetworkFirst', options: { cacheName: 'kiwi-camera-data', networkTimeoutSeconds: 5, expiration: { maxEntries: 2, maxAgeSeconds: 86400 } } },
        { urlPattern: ({ url }) => url.hostname.endsWith('tile.openstreetmap.org'), handler: 'CacheFirst', options: { cacheName: 'kiwi-map-tiles', expiration: { maxEntries: 500, maxAgeSeconds: 604800 } } }
      ]
    }
  })]
});
