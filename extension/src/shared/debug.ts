// =============================================================================
// shared/debug.ts — 유지보수용 게이트 로깅
//
// 스트림/앵커/문단진입 경로는 눈에 안 보이는 곳에서 어긋나기 쉬워(예: MV3 서비스워커
// 조기 종료, 앵커 불일치) 문제 추적에 로그가 필요하다. 호출부는 코드에 남겨 두고,
// VITE_DEBUG=true 로 빌드할 때만 콘솔에 찍는다. 평소 빌드에선 no-op 이라 조용하다.
//
// 켜는 법: 익스텐션 .env.local 에 `VITE_DEBUG=true` 추가 후 재빌드.
// =============================================================================

const DEBUG_ENABLED =
  (import.meta as { env?: Record<string, string | undefined> }).env?.VITE_DEBUG === 'true'

/** DEBUG 빌드에서만 `[PROBER] …` 로 콘솔에 남긴다. 평소엔 아무것도 안 한다. */
export function debugLog(...args: unknown[]): void {
  if (DEBUG_ENABLED) console.log('[PROBER]', ...args)
}
