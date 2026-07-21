// =============================================================================
// shared/constants.ts — 전역 상수
// TODO: API_BASE_URL은 배포 환경에 맞춰 교체
// =============================================================================

// ─── API ─────────────────────────────────────────────────────────────────────

export const API_BASE_URL = 'http://localhost:8000'

export const ENDPOINTS = {
  QUIZ:    `${API_BASE_URL}/quiz`,
  SCRAP:   `${API_BASE_URL}/scrap`,
  LOGIN:   `${API_BASE_URL}/auth/login`,
  ME:      `${API_BASE_URL}/auth/me`,
  LOGOUT:  `${API_BASE_URL}/auth/logout`,
} as const

// ─── chrome.storage.local 키 ─────────────────────────────────────────────────

export const STORAGE_KEYS = {
  ACCESS_TOKEN:  'prober_access_token',
  RETRY_QUEUE:   'prober_scrap_retry_queue',  // 전송 실패한 ScrapRequest[] 재시도 큐
} as const

// ─── IntersectionObserver (observer.ts) ─────────────────────────────────────

/**
 * 문단 상단이 뷰포트 상단 40% 지점을 통과할 때 진입으로 판정.
 * rootMargin '-40% 0px -60% 0px' → 뷰포트 상단 40%~60% 구간에 있을 때만 교차 감지.
 * ⚠️ Step 10 QA 단계에서 튜닝 대상.
 */
export const OBSERVER_OPTIONS: IntersectionObserverInit = {
  root: null,
  rootMargin: '-40% 0px -60% 0px',
  threshold: 0,
} as const

// ─── Anchor 매칭 (anchor.ts) ─────────────────────────────────────────────────

/** 유사도 점수가 이 값 미만이면 paragraphIndex 폴백 또는 하단 강등. ⚠️ 튜닝 대상. */
export const ANCHOR_SIMILARITY_THRESHOLD = 0.55

/** anchorText 매칭 시 비교할 문단 텍스트 앞부분 길이 (서버가 40~60자 제공). */
export const ANCHOR_COMPARE_LENGTH = 80

// ─── Session ─────────────────────────────────────────────────────────────────

/** 재질문 최대 깊이. 명세 확정값 — 변경 시 서버 담당자와 align 필요. */
export const MAX_FOLLOWUP_LEVEL = 2

/** 객관식 보기 수. 서버가 항상 4개를 보내도록 계약됨. */
export const OPTIONS_COUNT = 4

// ─── UI ──────────────────────────────────────────────────────────────────────

/** 익스텐션 패널 너비 (기사 영역 오른쪽 고정). CSS 변수에도 동일하게 적용할 것. */
export const PANEL_WIDTH_PX = 340

/** Shadow DOM의 custom element 태그명. */
export const SHADOW_HOST_TAG = 'prober-panel'
