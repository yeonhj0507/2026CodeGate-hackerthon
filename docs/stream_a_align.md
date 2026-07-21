# Stream A — Align Log (Content Pipeline)

> **이 문서의 용도.** Stream A(`extractor.ts` · `anchor.ts` · `observer.ts`)가 다른 스트림(B: Logic+UI, C: Infra)과 공유해야 하는 **공개 API·계약·미결 항목**을 모아둔 살아있는 문서입니다.
> Stream A는 `T=2,3,4,5` 단계마다 이 문서를 갱신합니다. **B·C 담당은 Stream A 코드를 import하기 전에 이 문서를 먼저 읽으세요.**
>
> 상위 계약: [shared_contract.md](./shared_contract.md) · 구현 계획: [extension_implementation_plan.md](./extension_implementation_plan.md)
> 옆 스트림 로그: [stream_b_align.md](./stream_b_align.md) · [stream_c_align.md](./stream_c_align.md)
> **QA·핸드오프: [stream_a_qa.md](./stream_a_qa.md)** (T=5 앵커 튜닝 결과 + 브라우저 QA 체크리스트 + Step 9 auth seam)
> 최종 업데이트: 2026-07-21 (**T=5 앵커 튜닝·QA** — 16/16 통과, THRESHOLD 0.55 유지 확정. stream_a_qa.md)

---

## 0. 현재 상태

| 파일 | Step | 상태 | tsc |
|------|------|------|-----|
| `content/extractor.ts` | 2 | ✅ 완료 | ✅ 통과 |
| `content/anchor.ts` | 4 ⚠️ | ✅ 완료 | ✅ 통과 |
| `content/observer.ts` | 5 | ✅ 완료 | ✅ 통과 |
| `content/index.tsx` (오케스트레이터) | 7 | ✅ 완료(T=3) | ✅ 통과 |
| `qa/anchor-qa.ts` (앵커 QA 하니스) | 10 | ✅ 완료(T=5) · 16/16 | `npm run qa:anchor` |

`npx tsc --noEmit` 전체 통과(strict + noUnusedLocals/Parameters). 스캐폴딩·`node_modules`는 Stream C가 완료해둠.

**현재 T-단계: T=3 (전체 align 진행).** T=2 종료(B가 `createSessionQueue`로 리팩터 완료 확인). observer→session→ui→background end-to-end 배선 착수 — **오케스트레이터 소유권·부트 시퀀스 교통정리(아래 §T3).**

---

## 1. 공개 API — 다른 스트림이 import하는 표면

### `content/extractor.ts`

```typescript
// 상수
export const PROBER_IDX_ATTR = 'data-prober-idx'   // 각 문단 el에 부여되는 속성

// 텍스트 유틸 (anchor.ts가 재사용, B/C도 필요 시 사용 가능)
export function normalizeText(s: string | null | undefined): string

// 결과 타입
export interface ExtractResult {
  title: string
  body: string              // ⚠️ paragraphs를 '\n\n'으로 이어붙인 평문 (아래 §2.2)
  paragraphs: Paragraph[]   // 각 el에 data-prober-idx 부여됨
}

// 메인
export function extractArticle(doc?: Document): ExtractResult | null   // 본문 없으면 null
export function paragraphElement(idx: number, doc?: Document): Element | null
```

### `content/anchor.ts`

```typescript
export type AnchorMethod = 'exact' | 'partial' | 'similarity' | 'index' | 'none'

export interface AnchorMatch {
  quiz: Quiz
  paragraph: Paragraph | null   // null = 매칭 실패(하단 강등 대상)
  method: AnchorMethod
  score: number                 // 0~1
}

export interface AnchorResult {
  byClaim: Map<string, AnchorMatch>   // claimId → 매칭 결과
  byParagraph: Map<number, Quiz[]>    // 문단 idx → 그 문단에 걸린 Quiz[]  ← observer 배선의 핵심
  unanchored: Quiz[]                  // 하단 일괄 노출 대상
}

export function anchorQuizzes(quizzes: Quiz[], paragraphs: Paragraph[]): AnchorResult
export function diceCoefficient(a: string, b: string): number
```

### `content/observer.ts`

```typescript
export type ParagraphEnterCallback = (idx: number) => void

export interface ParagraphObserver {
  observe(targets: Paragraph[]): void          // 관찰 대상 등록(누적)
  onParagraphEnter(cb: ParagraphEnterCallback): void  // 진입 콜백(단일, 재호출 시 교체)
  rearm(idx: number): void                     // 특정 문단 재발화 가능화
  reset(): void                                // 발화 이력 초기화(재추출 시)
  disconnect(): void                           // 전면 중단·정리
}

export function createParagraphObserver(doc?: Document): ParagraphObserver
```

---

## 2. 크로스-스트림 계약 & align 필요 항목

### 2.1 [🔴 align 필요 · B] anchor 출력 표기 불일치

- **shared_contract.md 문구:** `anchor.ts … 출력: Map<number, Paragraph> (claimId → Paragraph)`
- **문제:** `claimId`는 `string`이라 `Map<number, …>`와 키 타입이 상충. 또한 실제 소비자(observer 배선)는 **문단 idx → Quiz** 방향이 필요.
- **Stream A 결정:** 위 두 방향을 모두 담는 `AnchorResult`를 반환.
  - 계약이 의도한 "claimId → Paragraph"는 `byClaim.get(claimId)!.paragraph`로 그대로 획득.
  - observer 진입 처리에 필요한 "idx → Quiz[]"는 `byParagraph.get(idx)`.
- **B/통합 담당 확인 요청:** 배선 코드(`content/index.tsx`)에서 `byParagraph`로 idx→Quiz를 해석해 `startQuestion(quiz)`를 호출하는 방식에 동의하는지.

### 2.2 [🟡 공유 · C·서버] `articleBody` 직렬화 규약

- **Stream A 결정:** `ExtractResult.body = paragraphs.map(p => p.text).join('\n\n')` — 문단을 **추출 순서대로** `'\n\n'`으로 이어붙임.
- **이유:** 서버가 이 body로 문단 번호를 매기므로, 구분자를 유지해야 서버의 `paragraphIndex`가 우리 `Paragraph.idx`와 **정렬**됨 → 앵커 폴백(우선순위 3) 신뢰도 확보.
- **주의:** `types.ts`의 `QuizRequest.articleBody` 주석("문단 구분 없이 이어붙인")과 표현이 다름. 정렬 목적상 구분자 유지가 맞다고 판단.
- **C/서버 담당 확인 요청:** `/quiz` 요청 body를 위 규약대로 받는지, 서버가 `'\n\n'` 경계로 문단을 세는지.

### 2.3 [🟡 사용 규약 · B/통합] observer는 "퀴즈 비인지(idx 기반)"

- observer는 Quiz를 모름. `observe()`에 넘긴 `Paragraph[]`만 관찰하고 진입 시 `idx`만 통지.
- **컨트롤러 책임:** `observe()`에는 **anchor가 매칭한 문단만** 넘길 것(예: `anchorResult.byParagraph.keys()`에 해당하는 Paragraph). 그래야 퀴즈 없는 문단에서 헛발화 없음.
- 진입 콜백 안에서 `byParagraph.get(idx)`로 Quiz[]를 얻어 처리.

### 2.4 [🟢 정보] 텍스트 정규화 단일 출처

- `normalizeText()`(공백 collapse + trim, 대소문자 보존)를 extractor가 export, anchor가 import해 사용. 문단 텍스트·매칭 기준을 한 함수로 통일. B/C도 문단 텍스트를 다룰 때 이 함수를 쓰면 불일치 방지.

---

## 2b. T=2 A↔B align — observer↔session 배선 확정

> shared_contract T=2 과제: "Paragraph의 실제 DOM 이벤트 훅 방식을 B에 전달 + B가 session.ts에서 observer 이벤트 받는 방식 확정."
> stream_b_align.md §2.1·§2.3의 미결 질문에 대한 **Stream A 응답**.

### DOM 이벤트 훅 방식 (A→B 전달)

- observer는 `IntersectionObserver`로 `data-prober-idx` 문단을 관찰. `OBSERVER_OPTIONS`(rootMargin `-40% 0px -60% 0px`)에 따라 **문단 상단이 뷰포트 상단 40% 지점을 통과**하는 순간을 진입으로 판정.
- **문단당 1회만** 발화(내부 `fired` Set) 후 해당 요소는 자동 `unobserve`. 재발화가 필요하면 `rearm(idx)`.
- 발화는 **`idx: number`만** 통지(퀴즈 비인지). idx→Quiz 해석은 배선 컨트롤러가 `anchorResult.byParagraph.get(idx)`로 수행.

### ✅ 응답 1 — B §2.1 "한 문단에 다중 Quiz / 진행 중 진입" → **session에 큐 불필요. 컨트롤러가 FIFO 큐 소유.**

- `session.startQuestion`은 단일 Quiz만 받고 `phase !== 'IDLE'`이면 드롭(현행 유지, **B 코드 변경 없음**).
- 컨트롤러가 대기 큐를 두고, `useSession.subscribe`로 **phase→IDLE 전이**를 감지해 다음 퀴즈를 pump.
- 이 방식이 (a) 한 문단 다중 퀴즈, (b) 빠른 스크롤로 여러 문단 동시 진입 두 경우를 **손실 없이** 처리. 순서 = `byParagraph`의 push 순서 = 서버 quiz 배열 순서.
- (대안이던 "첫 Quiz만 넘기고 나머지 드롭"은 퀴즈 유실 → 채택 안 함.)

### 🟡 응답 2 — B §2.3 "하단 강등(unanchored) UI 주체" → **UI 주체는 해소(별도 UI 불필요), 단 flush 트리거는 T=3 미결.**

- **UI 주체(B가 물은 것):** MVP는 전용 UI 불필요. `anchorResult.unanchored`를 §2.1 컨트롤러 큐에 append해 기존 단일 패널로 순차 노출 → **B는 새 UI 안 만들어도 됨.** (전용 목록 UI는 post-MVP. 본문 인라인은 B의 Shadow DOM 격리 원칙을 깨므로 훗날 만든다면 **패널 내 섹션** 권장.)
- **⚠️ 남은 문제 = flush 트리거:** "마지막 문단 진입 시 append"는 독자가 끝까지 스크롤 안 하면 강등 퀴즈 유실. **T=3에서 트리거 확정 필요**(§2b 스케치 하단 경고 참조). MVP 기본 = 마지막 문단, fallback = 종료 버튼 시 남은 unanchored 표시.

### 배선 스케치 (컨트롤러, `content/index.tsx` — 소유권 T=3 확정 예정)

> ⚠️ **아래 스케치는 §2b-확정으로 대체됨.** 큐를 컨트롤러 인라인으로 두던 초안 → B의 `createSessionQueue()`(테스트된 모듈)에 위임하는 최종안으로 변경. 이력 보존용으로만 남김. **현행 규약은 [§2b-확정](#2b-확정-t2-최종-결정-b의-2c-위임에-대한-stream-a-확정) 참조.**

```typescript
import { extractArticle } from './extractor'
import { anchorQuizzes } from './anchor'
import { createParagraphObserver } from './observer'
import { useSession } from './session'
import type { Quiz } from '../shared/types'

// 전제: quizzes: Quiz[] 는 background REQUEST_QUIZ 응답으로 이미 받음
const extract = extractArticle()
if (!extract) { /* 본문 없음 → 종료 */ }
const { paragraphs } = extract!
const anchor = anchorQuizzes(quizzes, paragraphs)

// ── 컨트롤러 소유 FIFO 큐 ──
const queue: Quiz[] = []
function enqueue(qs: Quiz[]) { queue.push(...qs); pump() }
function pump() {
  if (useSession.getState().phase !== 'IDLE') return  // 진행 중이면 대기
  const next = queue.shift()
  if (next) useSession.getState().startQuestion(next)
}
// phase가 IDLE로 돌아오면 다음 퀴즈 자동 진행
useSession.subscribe((s, prev) => {
  if (s.phase === 'IDLE' && prev.phase !== 'IDLE') pump()
})

// ── observer → 큐 (단일 콜백. onParagraphEnter는 1개만 등록됨) ──
const observer = createParagraphObserver()
let unanchoredFlushed = false
observer.onParagraphEnter((idx) => {
  const qs = anchor.byParagraph.get(idx)
  if (qs) enqueue(qs)

  // unanchored 강등 퀴즈: 마지막 문단에 도달하면 큐 뒤에 붙임(1회).
  if (!unanchoredFlushed && idx === lastIdx && anchor.unanchored.length) {
    unanchoredFlushed = true
    enqueue(anchor.unanchored)
  }
})

// 앵커 매칭된 문단만 관찰(퀴즈 없는 문단 헛발화 방지).
// 단, lastIdx는 unanchored flush 트리거로 필요하므로 매칭 여부와 무관하게 포함.
const lastIdx = paragraphs[paragraphs.length - 1]?.idx
const watched = paragraphs.filter(
  (p) => anchor.byParagraph.has(p.idx) || p.idx === lastIdx,
)
observer.observe(watched)
```

> **단일 콜백으로 통합함** — observer의 `onParagraphEnter`는 재호출 시 교체(단일)이므로, 큐 append와 unanchored flush를 **한 콜백 안에서** 처리. (앞선 버전의 이중 등록 버그 수정.)

**B에게 필요한 것:** 위 스케치대로면 `session.ts`는 **현행 그대로**면 됩니다(큐 추가 불필요). 컨트롤러가 `getState()`·`subscribe()`만 사용. 이 규약에 이견 있으면 stream_b_align.md에 남겨주세요.

---

## 2b-확정. T=2 최종 결정 (B의 §2c 위임에 대한 Stream A 확정)

> B가 `stream_b_align.md §2c`에서 D1~D5 차이표를 정리하고 **D1/D2 택일을 Stream A에 명시 위임**함.
> 사용자 지시로 Stream A가 최종 결정. 근거: B의 실제 구현(`session-bind.ts`) + observer/anchor 실코드 대조.

### ✅ 결정 1 (D1·D2) — **옵션 1 채택: 큐 메커니즘은 B 모듈, 단일 콜백은 컨트롤러.**

- B가 `session-bind.ts`를 **콜백 비점유형**으로 리팩터:
  ```typescript
  // content/session-bind.ts (B 소유) — observer를 모름. 큐+pump+phase구독만 캡슐화.
  export function createSessionQueue(): {
    enqueue: (quizzes: Quiz[]) => void   // IDLE이면 즉시 pump, 아니면 대기
    dispose: () => void                  // useSession 구독 해제
  }
  ```
- 단일 `observer.onParagraphEnter` 콜백은 **컨트롤러가 소유** → enqueue + unanchored flush를 한 콜백에서 처리.
- **채택 이유:** 큐+pump+phase전이는 session-flow(B 도메인)이고 이미 단위테스트 9/9 통과 → 검증 자산 보존. DOM 훅 배선(`onParagraphEnter`/`observe`)은 컨트롤러(A/통합 도메인). 관심사 분리가 옵션 2(전부 인라인, 미검증 재구현)보다 우월.
- **영향:** observer/anchor/session/extractor **코드 변경 없음(Stream A 무변경).** B는 `session-bind.ts`만 `connectObserverToSession` → `createSessionQueue`로 리팩터.

### ✅ 결정 2 (B §2.1 알림 회신) — **busy 시 `rearm` 재발화 불필요. 동의.**

- 큐가 유실을 막으므로, one-shot unobserve된 문단을 busy 때문에 `rearm`할 필요 없음. `observer.rearm(idx)`는 **재추출/SPA 이동** 용도로만 유지. (observer 코드 변경 없음.)

### ✅ 결정 3 (D4) — **`observe()` 대상 = 앵커된 문단 ∪ {마지막 문단}.**

- 컨트롤러가 `observer.observe()`에 `anchor.byParagraph.has(idx)`인 문단 + 유일하게 `lastIdx`(unanchored flush 트리거용)를 넘김. B §2.2b(앵커 문단만)에 lastIdx만 A가 보강.

### ✅ 결정 4 (unanchored flush 트리거, 그동안 미결) — **MVP: 마지막 문단 진입 시 1회. 조기 이탈 시 미제시 허용.**

- flush 시점 = 마지막 문단 진입. 독자가 끝까지 안 내려오면 `unanchored`는 **제시하지 않음**(= 독서 미완료 → 스크랩엔 답한 것만 반영, 허용 가능한 MVP 손실).
- **"학습 종료" 시 enqueue는 하지 않음** — 종료를 누른 뒤 문항이 새로 뜨는 모순 UX 방지. (종료는 스크랩 전송 트리거일 뿐.)
- Step 10 QA에서 재검토(스크롤 N% 트리거 등).

### ✅ 결정 5 (B §3 큐 상한/만료) — **MVP 무제한. Step 10 QA 관찰.**

- `createSessionQueue`는 MVP에서 무제한 FIFO. 상한/만료(지나간 문단 expire)는 필요 시 B가 큐 모듈에 추가. Step 10 관찰 대상.

### 확정 배선 스케치 (옵션 1)

```typescript
import { extractArticle } from './extractor'
import { anchorQuizzes } from './anchor'
import { createParagraphObserver } from './observer'
import { createSessionQueue } from './session-bind'   // ← B 모듈(옵션1 리팩터 후)
import type { Quiz } from '../shared/types'

const extract = extractArticle()
if (!extract) { /* 본문 없음 → 종료 */ }
const { paragraphs } = extract!
const anchor = anchorQuizzes(quizzes, paragraphs)   // quizzes: REQUEST_QUIZ 응답

const q = createSessionQueue()                      // 큐+pump+phase구독은 B 모듈이 캡슐화
const observer = createParagraphObserver()

const lastIdx = paragraphs[paragraphs.length - 1]?.idx
let unanchoredFlushed = false

// 단일 콜백을 컨트롤러가 소유: enqueue + unanchored flush 한 곳에서.
observer.onParagraphEnter((idx) => {
  const qs = anchor.byParagraph.get(idx)
  if (qs) q.enqueue(qs)
  if (!unanchoredFlushed && idx === lastIdx && anchor.unanchored.length) {
    unanchoredFlushed = true
    q.enqueue(anchor.unanchored)
  }
})

// 앵커된 문단 + lastIdx(unanchored 트리거)만 관찰
const watched = paragraphs.filter(
  (p) => anchor.byParagraph.has(p.idx) || p.idx === lastIdx,
)
observer.observe(watched)

// 정리 시: q.dispose(); observer.disconnect()
```

**요약: Stream A 코드 변경 없음.** B는 `session-bind.ts`를 `createSessionQueue`로 리팩터, 컨트롤러(T=3)는 위 스케치. D1~D5 전원 확정 → T=3 배선 착수 가능.

### T=2 A↔B 종료 판정

- **B가 추가로 결정할 사항 없음.** D1~D5 전원 확정. B의 잔여는 **결정이 아니라 실행 1건**(`session-bind.ts` → `createSessionQueue` 리팩터, B가 §2c에서 제안한 안).
- **경계 명시:** `createSessionQueue`의 **정확한 시그니처는 B 소유**. A는 `enqueue(quizzes: Quiz[])` + `dispose()` 시맨틱에만 의존. idx→Quiz 해석은 컨트롤러가 `anchor.byParagraph.get(idx)`로 수행 → **B 모듈은 observer/anchor를 import하지 않아도 됨**(리팩터 시 두 type-only import 제거).
- **T=3으로 이월(A↔B 둘이 못 정함):** ① `content/index.tsx` 소유권(3자 접점) ② onEnd→/scrap payload 조립(T=4, B↔C) ③ unanchored flush 트리거 정밀화·큐 상한(Step 10).
- → 위 리팩터·이견 없으면 **T=2 A↔B align 종료 가능.**

---

## §T3. T=3 전체 align — Stream A 교통정리 (RFC)

> shared_contract T=3 과제: **observer → session → ui → background 체인 end-to-end** (mock 서버 가능).
> A·B·C 세 문서 모두 **`content/index.tsx` 오케스트레이터 소유권**과 **REQUEST_QUIZ 호출 주체**를 "미정"으로 남겨 서로 미룸(A §3, B §3, C T=3 §38). 이게 T=3 병목 → Stream A가 최고참으로서 아래로 확정 제안.
> **B·C에게:** 읽고 더 나은 대안 있으면 각자 로그에 제안, 없으면 이 계획대로 진행. 확인 요청 항목은 §T3.5.

### T3.0 — end-to-end 체인 (확정 목표)

```
content script boot (document_idle)
  │
  1. extractArticle()               [A] → ExtractResult{title, body, paragraphs}  (실패/짧으면 중단)
  2. REQUEST_QUIZ (title, body)      [A→C] chrome.runtime.sendMessage → background sendQuizRequest → Quiz[]
  3. anchorQuizzes(quizzes, paras)   [A] → AnchorResult{byParagraph, unanchored}
  4. mountPanel({ onEnd })           [B] Shadow DOM 패널
  5. createSessionQueue()            [B] enqueue/dispose
  6. observer.observe(watched)       [A] 앵커문단 ∪ {lastIdx}
  7. onParagraphEnter(idx):          [A] q.enqueue(byParagraph.get(idx)) + unanchored flush
  8. 큐 → startQuestion → UI 채점     [B] (T=2 확정 흐름)
  9. onEnd → flushResults → SEND_SCRAP[A→C] chrome.runtime.sendMessage → background sendScrapRequest
```

### T3.1 — 🔑 결정: `content/index.tsx` 오케스트레이터는 **Stream A 소유**

- **근거:** 이 파일은 A의 content 파이프라인(extract→anchor→observe)이 **척추**이고, B(mount/queue)·C(message)는 그 위에서 호출됨. 단일 소유자가 명확해야 순환 미룸이 끝남. A가 파이프라인 오너이자 최고참이므로 A가 가짐.
- **경계:** A는 B의 공개 API(`mountPanel`/`createSessionQueue`/`useSession.flushResults`)와 C의 메시지 계약(`ChromeMessage`)에 **의존만** 함. B·C 파일 내부는 안 건드림.
- **C 관련:** content→background는 `chrome.runtime.sendMessage(ChromeMessage)` 직접 사용(공유 타입). content 쪽 별도 C 파일 불필요. C는 background 쪽(`index.ts`/`api.ts`)만 소유.
- → **C 문서 T=3 §38 "sendMessage 주체 미정" 종결: A.** B 문서 §3 "index.tsx 소유권 미정" 종결: A.

### T3.2 — 결정: 부트 시퀀스 & 실패 처리 (MVP)

1. `extractArticle()` → **null이거나 `paragraphs.length < MIN_ARTICLE_PARAGRAPHS(=3)`** → **조용히 중단**(패널·퀴즈요청 없음). 비기사 페이지에서 `/quiz` 남발 방지 게이트.
2. `REQUEST_QUIZ` → **throw(QUIZ_ERROR)거나 `quiz.length===0`** → **조용히 중단**(패널 안 띄움). MVP는 페이지 내 에러 UI 없음(팝업이 상태 표시는 Step 9).
3. 성공 시에만 anchor → mountPanel → observer 배선.
- 게이트 상수 `MIN_ARTICLE_PARAGRAPHS`는 **오케스트레이터 로컬**(shared/constants 안 건드림).

### T3.3 — 결정: REQUEST_QUIZ / SEND_SCRAP 라운드트립 계약 (현행 C 코드와 일치 확인함)

- **REQUEST_QUIZ:** content가 `await chrome.runtime.sendMessage({type:'REQUEST_QUIZ',title,body})` → 응답 `QUIZ_RESPONSE{quiz}` 또는 `QUIZ_ERROR{error}`. **C의 `background/index.ts` 현재 구현 그대로 동작**(리스너가 `return true`로 비동기 응답). A는 `resp.type` 분기.
- **SEND_SCRAP:** `onEnd` 콜백이 `{type:'SEND_SCRAP', payload:{articleTitle, articleBody, results}}` 전송. `articleTitle/articleBody`는 **오케스트레이터가 쥔 ExtractResult에서** 주입(→ B §2.2 "articleTitle/body 소유자 미정" 종결: 오케스트레이터 A). `results`는 `useSession.getState().flushResults()`.
- **T=3 범위:** "학습 종료" 버튼 경로만 배선. **주기적 자동저장·beforeunload·재시도 큐는 C의 T=4/Step 8.**

### T3.4 — 결정: mock 서버 (end-to-end QA 수단)

- T=3 e2e는 "서버 실물"이 아니라 **배선 검증**이 목적. 서버팀(담당3) 실API 대기 없이 진행하려면 mock 필요.
- **결정:** C의 `api.ts`에 **dev mock 모드**(env/플래그, 예: `import.meta.env.DEV` 또는 `VITE_MOCK`)를 두고, 켜지면 fetch 대신 **canned `Quiz[]`** 반환. fixture 형태는 B의 `ui/mock.ts` 트리와 동형(shape 합의됨). → 메시지+content 체인 전 구간 검증 가능.
  - (선택) 실 fetch 경로까지 보려면 `localhost:8000` 미니 mock 서버. nice-to-have, C 재량.
- **소유:** api.ts는 C 소유이므로 **mock 모드 구현·플래그명은 C가 최종 결정.** A는 "dev에서 실서버 없이 Quiz[]가 오면 됨"만 의존. **C 확인 요청.**

### T3.5 — 스트림별 T=3 작업 배정 & B·C 확인 요청

| 스트림 | T=3 할 일 | 확인/이견 요청 |
|--------|-----------|----------------|
| **A** | `content/index.tsx` 오케스트레이터 작성(T3.0 체인). anchor/observer는 완료. | — |
| **B** | 이미 완료(`createSessionQueue`/`mountPanel`/session). **패널 IDLE/빈 큐 상태**가 어색하지 않은지만 점검(분석중·대기 표시 선택). | ❓패널이 "퀴즈 대기(IDLE)"일 때 빈 화면인지, 안내 문구 있는지 — A가 mount 시점을 "퀴즈 확보 후"로 잡았으니 빈 패널은 안 뜸. 이대로 OK인지. |
| **C** | `sendQuizRequest`에 **Bearer 토큰 best-effort 첨부**(있으면 붙이고 없으면 생략 → 로그인 전에도 e2e 가능). **mock 모드**(T3.4). | ❓mock 모드 플래그·형태 C 확정. ❓토큰 미로그인 시 생략 정책 OK인지. |

### T3.6 — 레퍼런스 오케스트레이터 스케치 (A가 T=3에 작성할 `content/index.tsx`)

```typescript
import { extractArticle } from './extractor'
import { anchorQuizzes } from './anchor'
import { createParagraphObserver } from './observer'
import { createSessionQueue } from './session-bind'
import { mountPanel } from './ui/mount'
import { useSession } from './session'
import type { ChromeMessage, Quiz } from '../shared/types'

const MIN_ARTICLE_PARAGRAPHS = 3

async function requestQuiz(title: string, body: string): Promise<Quiz[]> {
  const resp = (await chrome.runtime.sendMessage(
    { type: 'REQUEST_QUIZ', title, body } satisfies ChromeMessage,
  )) as ChromeMessage
  if (resp.type === 'QUIZ_ERROR') throw new Error(resp.error)
  if (resp.type === 'QUIZ_RESPONSE') return resp.quiz
  throw new Error('unexpected quiz response')
}

async function boot(): Promise<void> {
  const extract = extractArticle()
  if (!extract || extract.paragraphs.length < MIN_ARTICLE_PARAGRAPHS) return   // T3.2-1

  let quizzes: Quiz[]
  try { quizzes = await requestQuiz(extract.title, extract.body) }
  catch { return }                                                            // T3.2-2
  if (quizzes.length === 0) return

  const anchor = anchorQuizzes(quizzes, extract.paragraphs)
  const queue = createSessionQueue()
  const observer = createParagraphObserver()

  mountPanel({
    onEnd: () => {
      const results = useSession.getState().flushResults()
      chrome.runtime.sendMessage(
        { type: 'SEND_SCRAP', payload: { articleTitle: extract.title, articleBody: extract.body, results } } satisfies ChromeMessage,
      ).catch(() => { /* 재시도 큐는 C의 T=4 */ })
      queue.dispose()        // ← B 🟠 반영: phase 구독 해제(새 pump 중단)
      observer.disconnect()  // ← B 🟠 반영: 이후 문단 진입 발화 중단
    },
  })

  const lastIdx = extract.paragraphs[extract.paragraphs.length - 1]?.idx
  let unanchoredFlushed = false
  observer.onParagraphEnter((idx) => {                                        // 단일 콜백(컨트롤러 소유)
    const qs = anchor.byParagraph.get(idx)
    if (qs) queue.enqueue(qs)
    if (!unanchoredFlushed && idx === lastIdx && anchor.unanchored.length) {
      unanchoredFlushed = true
      queue.enqueue(anchor.unanchored)
    }
  })

  const watched = extract.paragraphs.filter(
    (p) => anchor.byParagraph.has(p.idx) || p.idx === lastIdx,
  )
  observer.observe(watched)
  // MVP: SPA 재이동/이탈 teardown(queue.dispose·observer.disconnect·panel.unmount)은 Step 10 여력 시.
}

void boot()
```

> 위 스케치(dispose/disconnect 반영본)를 **`content/index.tsx`로 커밋 완료** (아래 §T3.7).

### T3.7 — B·C 응답 반영 & T=3 확정 (독립 작동 준비 완료)

> B(`stream_b_align.md` T=3), C(`stream_c_align.md` T=3) 응답 확인 후 Stream A 최종 결정.

**C 응답:** T3.1~T3.3·T3.6 이견 없음. 위임 2건 확정 — mock 플래그 **`VITE_MOCK_QUIZ`**, 토큰 미로그인 시 헤더 생략 OK. + C mock은 **실제 `body`를 `'\n\n'`로 split해 anchorText 동적 생성**(정적 fixture가 데모 기사와 불일치 → 앵커 전부 실패하는 문제 회피).

**B 응답:** T3 대부분 동의. 패널 IDLE은 이미 안내 문구 렌더(빈 화면 아님) → OK. + 🟠 버그 1건 지적.

**Stream A 확정:**
- ✅ **결정 A (B 🟠 반영):** `onEnd`에 `queue.dispose()` + `observer.disconnect()` 추가 → 종료 후 새 문항 정지. **오케스트레이터에 반영·커밋.**
- ✅ **결정 B (패널 종료 UI, B가 A에 위임):** **(b) ended 상태 채택**("학습을 마쳤어요·결과 저장됨"). 패널이 그냥 사라지면 오류처럼 보임 + 저장 피드백 유용. **메커니즘은 B 내부**(종료 버튼이 `onEnd` 호출 후 로컬 ended 뷰) → `SessionStore`/shared-types **무변경**. onEnd는 정리+스크랩만. → **B가 ended 뷰 구현.**
- ✅ **결정 C (C mock):** 동적 anchorText 승인. `body` `'\n\n'` split이 우리 `Paragraph.idx`와 정렬되므로(§2.2) 앵커 경로가 실제로 검증됨. **C가 mock 모드 구현.**
- ✅ **`anchorText` 계약 재확인:** 서버·mock 모두 anchorText를 **실제 문단 앞 40~60자**로 채워야 앵커 1순위(부분 일치)가 작동. C mock은 이미 이 방식. 실서버(담당3)도 동일 필요 — 서버팀 확인 항목으로 유지.

**커밋:** `content/index.tsx` 작성 완료. **`npx tsc --noEmit` 전체 통과** — 오케스트레이터가 B(`mountPanel`/`createSessionQueue`/`useSession`)·C(`ChromeMessage`/background) 실코드에 대해 타입 레벨 end-to-end 배선 검증됨.

**독립 작동 상태 (각 스트림 잔여):**
| 스트림 | T=3 잔여 | 블로킹? |
|--------|----------|---------|
| **A** | ✅ 완료 — 오케스트레이터 커밋, tsc 통과 | 없음 |
| **B** | ended 상태 뷰 구현(결정 B) | 없음(A/C 무관하게 독립 진행) |
| **C** | mock 모드(`VITE_MOCK_QUIZ`, 동적 anchorText) + 토큰 best-effort | 없음(독립 진행) |

→ **3 스트림 상호 블로킹 없음. 각자 독립 진행 가능.** 실제 브라우저 e2e(observer→session→ui→background)는 C mock 완료 후 합류 시점에 실측.

---

## 3. 미결/미소유 항목

- ~~배선 파일(`content/index.tsx`) 소유권 미정~~ → **확정: Stream A 소유(§T3.1).** A가 오케스트레이터 작성, B/C API·메시지 계약에 의존만.
- **동시 진입 큐 정책 — 확정(§2b-확정 결정1).** 옵션 1: `createSessionQueue`(B 모듈) + 컨트롤러 단일 콜백. session/observer 무변경.
- **하단 강등(`unanchored`) — 확정(결정3·4).** UI 없이 큐 append, 트리거=마지막 문단 진입 1회(조기 이탈 시 미제시 허용). Step 10 재검토.
- **큐 상한/만료 — MVP 무제한(결정5).** Step 10 QA 관찰.
- **튜닝 상수(Step 10):** `ANCHOR_SIMILARITY_THRESHOLD=0.55` → **QA로 유지 확정**(stream_a_qa.md §2). `OBSERVER_OPTIONS.rootMargin`은 **브라우저 수동 QA 필요**(IntersectionObserver 헤드리스 불가).

---

## 4. 변경 이력 (T-단계별)

### T=1 (2026-07-21)
- `extractor.ts` 완성 — Readability=화이트리스트 + 라이브 DOM 순회=실제 노드. `Paragraph[]` + `data-prober-idx`.
- (선행) `anchor.ts` 완성 — 부분일치→Dice 유사도→paragraphIndex→하단 강등 4단계.
- (선행) `observer.ts` 완성 — IntersectionObserver, 문단당 1회, idx 기반 콜백.
- align 항목 §2.1(anchor 출력 표기), §2.2(body 직렬화) 제기.

### T=2 (2026-07-21) — A↔B align
- stream_b_align.md §2.1·§2.3 미결 질문에 응답(§2b 신설).
- **확정:** observer↔session 배선은 **컨트롤러 소유 FIFO 큐** + `useSession.subscribe` phase→IDLE pump. session.ts **무변경**.
- **확정:** 다중 Quiz/한 문단, 빠른 스크롤 다문단 진입 → 큐로 손실 없이 처리.
- **부분 해소:** `unanchored` UI 주체는 해소(별도 UI 불필요, 큐 append). flush 트리거(마지막 문단 스크롤 의존)는 T=3 미결로 남김.
- 배선 스케치(`content/index.tsx`) A-side 초안 제공 — **단일 콜백으로 정정(이중 등록 버그 수정)**. 소유권은 T=3 확정.

### T=2 (2026-07-21, 최종) — B의 §2c 위임에 대한 A 확정
- B가 `session-bind.ts`(큐 바인더) 신설 + one-shot unobserve로 인한 **퀴즈 유실 레이스**를 정밀 규명(제 큐 제안의 근거를 더 정확히 보강). 인정·반영.
- **D1/D2 최종 결정 = 옵션 1**: 큐+pump는 B의 `createSessionQueue()`(테스트된 모듈)에 두고, 단일 `onParagraphEnter` 콜백은 컨트롤러 소유. **Stream A 코드 무변경.**
- 결정 2: busy-rearm 불필요(동의). 결정 3: observe = 앵커문단 ∪ {lastIdx}. 결정 4: unanchored flush = 마지막 문단 1회(조기 이탈 미제시 허용, 종료 시 enqueue 안 함). 결정 5: 큐 무제한(Step 10).
- §2b-확정 신설(결정 1~5 + 옵션1 배선 스케치). 초안 스케치는 superseded 표기. D1~D5 전원 종결 → T=3 착수 가능.

### T=3 (2026-07-21) — 전체 align 교통정리 (Stream A RFC)
- B가 `session-bind.ts`를 `createSessionQueue(): SessionQueue`로 리팩터 완료 확인 → **T=2 종료.**
- C 문서(`stream_c_align.md`) 첫 확인: background 라우팅·`sendQuizRequest`/`sendScrapRequest` 구현됨(토큰·재시도·mock 미완). C의 T=3 미정 = "REQUEST_QUIZ 호출 주체".
- **§T3 신설(교통정리 RFC):** 세 문서가 공통으로 미룬 오케스트레이터 문제를 A가 확정.
  - **T3.1:** `content/index.tsx` = **Stream A 소유**(오케스트레이터). C §38·B §3 종결.
  - **T3.2:** 부트 시퀀스·게이트(`MIN_ARTICLE_PARAGRAPHS=3`)·실패 시 조용히 중단.
  - **T3.3:** REQUEST_QUIZ/SEND_SCRAP 라운드트립 = C 현행 코드와 일치 확인. articleTitle/body 소유자 = 오케스트레이터(B §2.2 종결).
  - **T3.4:** mock = C의 api.ts dev 모드(플래그·형태 C 확정).
  - **T3.5:** 스트림별 배정 + B(패널 IDLE 상태)·C(토큰 best-effort·mock) 확인 요청.
  - **T3.6:** 오케스트레이터 레퍼런스 스케치 제공(이견 없으면 그대로 커밋).

### T=3 (2026-07-21, 확정) — B·C 응답 반영 → 오케스트레이터 커밋
- **C 응답:** 이견 없음. mock 플래그 `VITE_MOCK_QUIZ`, 토큰 미로그인 생략 OK, mock은 body를 `'\n\n'` split해 anchorText 동적 생성.
- **B 응답:** 동의 + 🟠 버그 지적(`onEnd`가 세션 미정지 → 종료 후 새 문항).
- **A 확정:** ① onEnd에 `queue.dispose()`+`observer.disconnect()` 추가(B 🟠 반영). ② 패널 종료 UI = **(b) ended 상태**(B 내부 구현, shared-types 무변경). ③ C 동적 anchorText mock 승인. ④ anchorText=실제 문단 앞 40~60자 계약 재확인(서버팀 항목 유지).
- **커밋:** `content/index.tsx` 오케스트레이터 작성 완료(§T3.6 스케치 = 실제 파일). **`npx tsc --noEmit` 전체 통과** — B/C 실코드 대상 end-to-end 타입 배선 검증.
- **결과:** 3 스트림 상호 블로킹 없음. B(ended 뷰)·C(mock+토큰) 각자 독립 진행. 실 브라우저 e2e는 C mock 후 합류.

### T=5 (2026-07-21) — 앵커 튜닝 + QA (Step 10)
- **앵커 QA 하니스** `qa/anchor-qa.ts` 작성 — 실제 `anchorQuizzes` 번들(rolldown)해 검증. `npm run qa:anchor`.
- 한국어 기사 2편 × 8시나리오(정확/공백변형/편집드리프트/index틀림/text쓰레기/완전실패/짧은anchor) → **16/16 통과**. method 분포: exact1·partial9·similarity2·index2·none2.
- **임계값 확정:** off-target 최고 0.271 < THRESHOLD 0.55 < 드리프트 최저 0.84 → **`ANCHOR_SIMILARITY_THRESHOLD=0.55` 유지**(근거 기반).
- **핸드오프 문서** `stream_a_qa.md` 신설 — QA 결과·튜닝 노브·**브라우저 수동 QA 체크리스트**(rootMargin 등 헤드리스 불가분)·**Step 9 auth seam**·MVP 한계.
- Step 9(auth)는 코드베이스에 placeholder 이미 존재(popup/background/api) → 재작성 없이 seam만 문서화(서버팀 인계).
- `content/index.tsx` 커밋 후 전체 `tsc --noEmit` 통과 유지.

<!-- T=4 이후 아래에 추가 -->
