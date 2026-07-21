import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { crx } from '@crxjs/vite-plugin'
import manifest from './manifest.json'

export default defineConfig({
  plugins: [react(), crx({ manifest })],
  server: {
    // MV3 서비스 워커·콘텐츠 스크립트가 HMR 웹소켓에 접근할 수 있도록 고정 포트 사용
    port: 5173,
    strictPort: true,
    hmr: { port: 5173 },
  },
})
