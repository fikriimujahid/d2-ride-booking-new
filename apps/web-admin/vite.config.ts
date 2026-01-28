import { defineConfig } from 'vite';

export default defineConfig({
  define: {
    // Some dependencies (e.g. `buffer`) reference the Node.js global identifier `global`.
    // In browsers this doesn't exist, so we map it to `globalThis`.
    global: 'globalThis',
    // Some libs reference `process.env` for feature flags.
    // Provide an empty object to avoid `process is not defined` / undefined access.
    'process.env': '{}'
  },
  resolve: {
    alias: {
      buffer: 'buffer',
      process: 'process'
    }
  },
  optimizeDeps: {
    include: ['buffer', 'process'],
    esbuildOptions: {
      define: {
        global: 'globalThis'
      }
    }
  },
  server: {
    port: 5173
  }
});
