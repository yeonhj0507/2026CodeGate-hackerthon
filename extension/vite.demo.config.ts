import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// Stream B mock UI 검증용. crx 플러그인 없이 demo/를 정적 페이지로 서빙/빌드.
export default defineConfig({
  root: 'demo',
  plugins: [react()],
  server: { port: 5174, strictPort: true },
  build: { outDir: '../dist-demo', emptyOutDir: true },
})
