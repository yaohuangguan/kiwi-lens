import { defineConfig } from 'vite';
import { VitePWA } from 'vite-plugin-pwa';

export default defineConfig({
  server: { port: 5173, proxy: { '/api': 'http://localhost:8787' } },
  plugins: [VitePWA({
    registerType: 'autoUpdate',
    includeAssets: ['brand/tasman-icon-192.png', 'brand/tasman-icon-512.png'],
    manifest: {
      name: 'Tasman · NZ Navigation', short_name: 'Tasman', description: 'Route planning and road-safety awareness for New Zealand.',
      theme_color: '#032b45', background_color: '#032b45', display: 'standalone', start_url: '/app', scope: '/', orientation: 'portrait',
      icons: [{ src: '/brand/tasman-icon-192.png', sizes: '192x192', type: 'image/png', purpose: 'any' }, { src: '/brand/tasman-icon-512.png', sizes: '512x512', type: 'image/png', purpose: 'any' }]
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
