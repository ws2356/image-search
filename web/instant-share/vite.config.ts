/// <reference types="vitest/config" />
import { defineConfig, loadEnv } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '');
  console.log('Vite config: loaded env', { mode, env });
  return {
    plugins: [react()],
    server: { port: 5173 },
    test: {
      globals: true,
      environment: 'jsdom',
      setupFiles: './src/test/setup.ts',
      exclude: ['**/node_modules/**', '**/dist/**', '**/relay/**'],
    },
    base: env.VITE_BASE || '/',
  }
});
