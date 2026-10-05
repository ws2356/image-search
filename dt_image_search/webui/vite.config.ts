import { defineConfig } from 'vitest/config'
import vue from '@vitejs/plugin-vue'
import AutoImport from 'unplugin-auto-import/vite'
import Components from 'unplugin-vue-components/vite'
import { ElementPlusResolver } from 'unplugin-vue-components/resolvers'
import { fileURLToPath, URL } from 'node:url'

// Dev server proxies the index server's business endpoints; the token comes
// from VITE_DTS_TOKEN so the API client can authenticate in dev mode.
const indexServerPort = process.env.DTS_DEV_PORT ?? '8000'
const target = `http://127.0.0.1:${indexServerPort}`

export default defineConfig({
  plugins: [
    vue(),
    AutoImport({ resolvers: [ElementPlusResolver()] }),
    Components({ resolvers: [ElementPlusResolver()] }),
  ],
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
    },
  },
  server: {
    proxy: {
      '/folders': target,
      '/search': target,
      '/browse': target,
      '/status': target,
      '/events': { target, ws: true },
      '/thumb': target,
      '/file': target,
    },
  },
  test: {
    environment: 'jsdom',
    include: ['tests/**/*.spec.ts'],
    // Element Plus ships per-component CSS imports (auto-import resolver);
    // inline it so vitest transforms them instead of node's ESM loader.
    server: { deps: { inline: ['element-plus'] } },
  },
})
