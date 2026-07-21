// =============================================================================
// shared/types.ts — 프로버 크롬 익스텐션 전역 타입 정의
// 이 파일은 Stream A(content pipeline), B(logic+UI), C(infrastructure) 모두 import함.
// 변경 시 전체 탭 align 필요.
// =============================================================================

// ─── Extractor (Stream A) ────────────────────────────────────────────────────

/** extractor.ts가 DOM에서 추출한 문단 단위. el은 실제 DOM 노드 참조. */
export interface Paragraph {
  idx: number    // data-prober-idx 값 (0-based)
  text: string   // 정규화된 평문 텍스트
  el: Element    // 실제 DOM 노드 (anchor.ts, observer.ts가 사용)
}

// ─── Quiz Tree: 서버 → 익스텐션 (POST /quiz 응답) ──────────────────────────

/**
 * 재질문 노드. level 1 또는 2.
 * followups 배열이 비어있으면 해당 레벨이 트리 말단.
 */
export interface Followup {
  level: 1 | 2
  prereqConceptTag: string  // 이 재질문이 검사하는 선행 개념명
  question: string
  options: string[]         // 4지선다 보기
  answerIndex: number       // 정답 인덱스 (0-based)
  explanation: string       // 오답 시 노출할 설명
  followups: Followup[]     // 다음 단계 재질문 (최대 깊이 2이므로 level=1만 자식 가짐)
}

/**
 * 최상위 퀴즈 노드.
 * anchorText + paragraphIndex 두 가지로 DOM 문단에 매칭 (anchor.ts 참고).
 */
export interface Quiz {
  claimId: string           // 서버가 부여한 핵심 주장 ID
  conceptTag: string        // 이 퀴즈가 검사하는 핵심 개념명
  anchorText: string        // 해당 문단 앞 40~60자 (앵커 매칭 1순위)
  paragraphIndex: number    // 문단 번호 (앵커 매칭 폴백, 0-based)
  question: string
  options: string[]
  answerIndex: number
  explanation: string
  followups: Followup[]     // 오답 시 탐색할 선행 개념 재질문 트리
}

// ─── Scrap Result: 익스텐션 → 서버 (POST /scrap 요청) ──────────────────────

/**
 * 세션에서 사용자가 답한 각 문항의 결과.
 * parentConcept 포함 이유: 서버가 지식그래프에서 선행→후행 엣지를 복원하기 위함.
 */
export interface ScrapResult {
  conceptTag: string
  parentConcept: string | null  // main 문항이면 null, 재질문이면 부모 개념명
  level: 0 | 1 | 2             // 0=main, 1=1단계 재질문, 2=2단계 재질문
  correct: boolean
}

// ─── API 페이로드 ────────────────────────────────────────────────────────────

export interface QuizRequest {
  articleTitle: string
  articleBody: string   // 평문 원문 (문단 구분 없이 이어붙인 전체 텍스트)
}

export interface QuizResponse {
  quiz: Quiz[]
}

/**
 * 스크랩에는 **기사 원문이 없다**(명세 §3.4 개정).
 *
 * 원문은 /quiz 요청에서 이미 보냈으므로 재전송하지 않고, 출처 식별은 URL로만 한다.
 * 서버에 원문이 영속되는 지점을 없애기 위한 결정이다. articleBody 를 보내면 422.
 */
export interface ScrapRequest {
  articleUrl: string
  articleTitle: string
  results: ScrapResult[]
}

export interface ScrapResponse {
  ok: boolean
  buffered?: number   // 이 요청으로 버퍼에 쌓인 결과 개수(서버가 함께 준다)
}

// ─── Chrome Runtime 메시지 (content ↔ background) ───────────────────────────

/**
 * content script와 background service worker 간 메시지 타입.
 * 네트워크 호출은 항상 background가 담당 (CORS·토큰 노출 최소화).
 */
export type ChromeMessage =
  | { type: 'REQUEST_QUIZ'; title: string; body: string }
  | { type: 'QUIZ_RESPONSE'; quiz: Quiz[] }
  | { type: 'QUIZ_ERROR'; error: string }
  | { type: 'SEND_SCRAP'; payload: ScrapRequest }
  | { type: 'SCRAP_RESPONSE'; ok: boolean }
  | { type: 'SCRAP_ERROR'; error: string }
  | { type: 'GET_AUTH_STATUS' }
  | { type: 'AUTH_STATUS'; loggedIn: boolean; userId?: string; email?: string }
  | { type: 'LOGIN'; email: string; password: string; signup?: boolean }
  | { type: 'LOGIN_RESPONSE'; userId: string; email: string }
  | { type: 'LOGIN_ERROR'; error: string }
  | { type: 'LOGOUT' }
  | { type: 'LOGOUT_RESPONSE' }
  // 팝업 → content script. 사용자가 "이 기사에서 시작"을 눌렀을 때만 세션이 열린다.
  // (자동 실행하지 않는 이유: 원하는 기사에서만 패널이 뜨게 하기 위함)
  | { type: 'START_SESSION' }
  | { type: 'SESSION_STARTED' }
  | { type: 'SESSION_UNAVAILABLE'; reason: string }

// ─── Session 상태머신 (Stream B: session.ts ↔ ui/) ──────────────────────────

/**
 * session.ts가 관리하는 현재 질문 문맥.
 * quiz: 이 질문이 속한 최상위 Quiz 노드 (스크랩 시 claimId·conceptTag 추출용).
 * item: 실제로 화면에 표시할 질문 (main이면 quiz 자신, 재질문이면 Followup).
 * level: 0=main, 1·2=재질문 깊이.
 */
export interface ActiveQuestion {
  quiz: Quiz
  item: Quiz | Followup
  level: 0 | 1 | 2
}

/** session.ts가 ui/에 노출하는 상태 (zustand store shape). */
export interface SessionStore {
  phase: 'IDLE' | 'ASKING' | 'SHOW_EXPLANATION'
  active: ActiveQuestion | null
  results: ScrapResult[]

  // Actions (session.ts가 구현, ui/가 호출)
  startQuestion: (quiz: Quiz) => void
  submitAnswer: (selectedIndex: number) => void
  dismissExplanation: () => void
  flushResults: () => ScrapResult[]  // 스크랩 전송 후 results[] 초기화
}
