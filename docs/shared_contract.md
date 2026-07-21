# 프로버(Prober) — Shared Contract

> 이 문서는 익스텐션 작업을 나눠서 진행하는 **모든 Claude 탭의 공통 참조 문서**입니다.
> 코드 작성 전에 반드시 읽고, 타입 변경 시 전체 align이 필요합니다.

---

## 파일 위치

```
C:\codegatethon\
├── docs\
│   ├── README.md
│   ├── system_overview.md            ← 전체 아키텍처
│   ├── extension_implementation_plan.md  ← Step 1~10 상세
│   └── shared_contract.md            ← 지금 이 문서
└── extension\
    └── src\
        └── shared\
            ├── types.ts     ← 모든 스트림이 import하는 타입 정의 (확정)
            └── constants.ts ← 전역 상수 (확정)
```

---

## 스트림 분할 (3탭 병렬 작업)

| 스트림 | 담당 파일 | 모델 | Steps |
|--------|-----------|------|-------|
| **A — Content Pipeline** | `content/extractor.ts` `content/anchor.ts` `content/observer.ts` | opus | Step 2 → 4 → 5 |
| **B — Logic + UI** | `content/session.ts` `content/ui/**` | opus | Step 3 → 6 |
| **C — Infrastructure** | `manifest.json` `background/api.ts` `popup/**` | sonnet | Step 1 → 8 → 9 |

> Stream A에 opus를 배정하는 이유: `anchor.ts`가 ⚠️ 최대 구현 리스크.
> LLM이 준 문단 위치(anchorText + paragraphIndex)를 실제 DOM에 매칭하는 로직으로,
> 실패 시 퀴즈가 완전히 잘못된 위치에 나타남.

---

## Align 일정 (T=n)

```
T=0  shared/ 타입 확정 ← 지금 완료
      │
      ├── Stream A ──────────────────────────────────┐
      ├── Stream B ──────────────────────────────┐   │
      └── Stream C ──────────────────────────┐   │   │
                                             │   │   │
T=1  [병렬 작업]                             │   │   │
      A: extractor.ts 완성                   │   │   │
      B: mock UI 위젯 완성 (Step 3)          │   │   │
      C: 스캐폴딩 + manifest 완성 (Step 1)   │   │   │
                                             │   │   │
T=2  [A ↔ B align]                          ┘   │   │
      A가 extractor 완성 후:                     │   │
      - Paragraph 타입의 실제 DOM 이벤트 훅 방식 B에 전달
      - B가 session.ts에서 observer 이벤트 받는 방식 확정
                                                 │   │
T=3  [전체 align]                               ┘   │
      observer → session → ui → background 체인      │
      end-to-end 동작 확인 (mock 서버 가능)           │
      A: anchor + observer 완성                       │
      B: session.ts 완성                              │
      C: background/api.ts /quiz 연동 완성            │
                                                      │
T=4  [B ↔ C align]                                   ┘
      C의 /scrap 완성 시:
      - B의 ScrapRequest 직렬화 → C 페이로드 포맷 일치 확인
      - 재시도 큐 동작 방식 확인

T=5  [전체 QA]
      Step 10: 앵커 튜닝 + 데모 기사 end-to-end 검증
```

---

## 타입 정의 전문 (`shared/types.ts`)

> 아래 타입은 확정입니다. 변경 필요 시 전체 탭 align 후 이 문서도 업데이트하세요.

### Paragraph (Stream A → B)

```typescript
export interface Paragraph {
  idx: number    // data-prober-idx 값 (0-based)
  text: string   // 정규화된 평문 텍스트
  el: Element    // 실제 DOM 노드
}
```

### Quiz Tree (서버 → 익스텐션, POST /quiz 응답)

```typescript
export interface Followup {
  level: 1 | 2
  prereqConceptTag: string
  question: string
  options: string[]     // 4지선다
  answerIndex: number   // 0-based
  explanation: string
  followups: Followup[]
}

export interface Quiz {
  claimId: string
  conceptTag: string
  anchorText: string       // 문단 앞 40~60자 (앵커 매칭 1순위)
  paragraphIndex: number   // 문단 번호 (앵커 매칭 폴백, 0-based)
  question: string
  options: string[]
  answerIndex: number
  explanation: string
  followups: Followup[]
}
```

### ScrapResult (익스텐션 → 서버, POST /scrap)

```typescript
export interface ScrapResult {
  conceptTag: string
  parentConcept: string | null  // main=null, 재질문=부모 개념명
  level: 0 | 1 | 2
  correct: boolean
}
```

### API 페이로드

```typescript
// POST /quiz
export interface QuizRequest  { articleTitle: string; articleBody: string }
export interface QuizResponse { quiz: Quiz[] }

// POST /scrap
export interface ScrapRequest {
  articleTitle: string
  articleBody: string
  results: ScrapResult[]
}
export interface ScrapResponse { ok: boolean }
```

### Chrome Runtime 메시지 (content ↔ background)

```typescript
export type ChromeMessage =
  | { type: 'REQUEST_QUIZ'; title: string; body: string }
  | { type: 'QUIZ_RESPONSE'; quiz: Quiz[] }
  | { type: 'QUIZ_ERROR'; error: string }
  | { type: 'SEND_SCRAP'; payload: ScrapRequest }
  | { type: 'SCRAP_RESPONSE'; ok: boolean }
  | { type: 'SCRAP_ERROR'; error: string }
  | { type: 'GET_AUTH_STATUS' }
  | { type: 'AUTH_STATUS'; loggedIn: boolean; userId?: string }
```

### SessionStore (session.ts ↔ ui/)

```typescript
export interface ActiveQuestion {
  quiz: Quiz           // 최상위 Quiz (스크랩용 claimId·conceptTag 추출)
  item: Quiz | Followup  // 현재 화면에 보여줄 질문
  level: 0 | 1 | 2
}

export interface SessionStore {
  phase: 'IDLE' | 'ASKING' | 'SHOW_EXPLANATION'
  active: ActiveQuestion | null
  results: ScrapResult[]

  startQuestion: (quiz: Quiz) => void
  submitAnswer: (selectedIndex: number) => void
  dismissExplanation: () => void
  flushResults: () => ScrapResult[]
}
```

---

## 상수 (`shared/constants.ts`)

| 상수 | 값 | 설명 |
|------|----|------|
| `API_BASE_URL` | `http://localhost:8000` | ⚠️ 배포 시 교체 |
| `ANCHOR_SIMILARITY_THRESHOLD` | `0.55` | ⚠️ Step 10 튜닝 대상 |
| `OBSERVER_OPTIONS.rootMargin` | `'-40% 0px -60% 0px'` | ⚠️ Step 10 튜닝 대상 |
| `MAX_FOLLOWUP_LEVEL` | `2` | 확정, 서버와 계약된 값 |
| `OPTIONS_COUNT` | `4` | 객관식 보기 수, 서버 계약 |
| `PANEL_WIDTH_PX` | `340` | 익스텐션 패널 너비 |
| `SHADOW_HOST_TAG` | `'prober-panel'` | Shadow DOM custom element 태그 |

---

## 각 스트림의 책임 경계

### Stream A가 반드시 지켜야 할 것

- `extractor.ts` 출력: `paragraphs: Paragraph[]` 배열 + 각 `el`에 `data-prober-idx` 속성 부여
- `anchor.ts` 입력: `Quiz[]` + `Paragraph[]` → 출력: `Map<number, Paragraph>` (claimId → Paragraph)
- `observer.ts`는 `onParagraphEnter(idx: number)` 콜백을 외부(session.ts)가 등록할 수 있게 노출

### Stream B가 반드시 지켜야 할 것

- `session.ts`는 `SessionStore` 인터페이스를 zustand store로 구현
- `startQuestion(quiz: Quiz)` 진입점을 observer가 호출 — quiz는 anchor 매칭된 Quiz 객체
- `flushResults()`는 스크랩 전송 후 results[] 초기화까지 포함
- UI는 `SessionStore`만 구독 (DOM 직접 접근 금지, Shadow DOM 안에서만 동작)

### Stream C가 반드시 지켜야 할 것

- `background/api.ts`의 `sendQuizRequest()` 반환타입: `Promise<Quiz[]>` (에러 시 throw)
- `sendScrapRequest()` 반환타입: `Promise<void>` (실패 시 STORAGE_KEYS.RETRY_QUEUE에 적재)
- 토큰은 `chrome.storage.local`에 `STORAGE_KEYS.ACCESS_TOKEN` 키로만 저장
- 모든 서버 호출은 background에서만 수행 (content script에서 직접 fetch 금지)

---

## 주요 결정 사항 (변경 불가)

| 항목 | 결정 |
|------|------|
| 퀴즈 채점 위치 | **클라이언트** (answerIndex 비교, 런타임 LLM 호출 없음) |
| 재질문 최대 깊이 | **2단계** (서버가 전체 트리를 한 번에 내려줌) |
| 익스텐션·로컬앱 통신 | **금지** (모든 통신은 서버 경유) |
| 그래프 원본 위치 | 로컬앱 (익스텐션은 보유·수정 안 함) |
| 스크랩 저장 | 서버 임시 버퍼링 → 로컬앱 동기화 시 소비 |

---

## 참조 문서

- `docs/system_overview.md` — 전체 3-컴포넌트 아키텍처, 데이터 흐름
- `docs/extension_implementation_plan.md` — Step 1~10 상세 구현 가이드
- 구글 드라이브 `코드게이트 해커톤 준비` > `[READ THIS]` 탭 — 원본 기획/명세
