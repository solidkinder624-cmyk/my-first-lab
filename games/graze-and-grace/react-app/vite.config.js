import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  resolve: {
    // graze-and-grace-core (../package.json) is linked via `file:..` and symlinked
    // into node_modules. Without this, Vite resolves the symlink to its real path
    // outside node_modules and serves it as raw source instead of running it
    // through the dependency pre-bundler, so its CommonJS `module.exports` never
    // gets converted to ESM and named imports fail at dev-server time (production
    // `vite build` works either way since Rollup's bundling handles CJS directly).
    preserveSymlinks: true,
  },
  optimizeDeps: {
    include: [
      "graze-and-grace-core/core.js",
      "graze-and-grace-core/score.js",
      "graze-and-grace-core/rhythm.js",
    ],
  },
})
