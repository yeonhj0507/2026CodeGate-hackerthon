/// <reference types="vite/client" />

interface ImportMetaEnv {
  /** 'true'면 background/api.ts가 실제 fetch 대신 canned Quiz[]를 반환 (Stream C, T=3 §T3.4). */
  readonly VITE_MOCK_QUIZ?: string
  /** 'true'면 background/api.ts가 /scrap 실제 fetch 없이 즉시 성공 처리 (Stream C, T=4 §T4.6). */
  readonly VITE_MOCK_SCRAP?: string
}
