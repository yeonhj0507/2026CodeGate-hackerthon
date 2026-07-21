# Stream B — Align 로그 (Logic + UI)

> **이 문서의 용도.** Stream B(`content/session.ts` · `content/ui/**`)가 다른 스트림(A: Content Pipeline, C: Infra)·서버팀과 공유해야 하는 **공개 API·계약·미결 항목**을 모아둔 살아있는 문서입니다.
> Stream B는 `T=2,3,4,5` 단계마다 이 문서를 갱신합니다. **A·C 담당은 Stream B 코드를 호출/연동하기 전에 이 문서를 먼저 읽으세요.**
>
> 상위 계약: [shared_contract.md](./shared_contract.md) · 구현 계획: [extension_implementation_plan.md](./extension_implementation_plan.md)
> 옆 스트림 로그: [stream_a_align.md](./stream_a_align.md) · [stream_c_align.md](./stream_c_align.md) · QA: [stream_b_qa.md](./stream_b_qa.md) · [stream_a_qa.md](./stream_a_qa.md)
> 최종 업데이트: 2026-07-21 (**T=5 B QA 완료** — `npm run qa:session` 22/22, 통합 tsc/build green. handoff = stream_b_qa.md)

---

## 0. 현재 상태

| 파일 | Step | 상태 | tsc |
|------|------|------|-----|
| `content/session.ts` | 6 | ✅ **완성 (T=3, 전 경로 단위테스트 21/21 certify, 코드 변경 없음)** | ✅ 통과 |
| `content/session-bind.ts` | — (T=2) | ✅ 완료 (`createSessionQueue`, 옵션1 확정본) | ✅ 통과 |
| `content/ui/Panel.tsx` | 3 (+T=3) | ✅ 완료 (T=3: ended 상태 추가) | ✅ 통과 |
| `content/ui/QuestionView.tsx` | 3 | ✅ 완료 | ✅ 통과 |
| `content/ui/Explanation.tsx` | 3 | ✅ 완료 | ✅ 통과 |
| `content/ui/mount.tsx` | 3 | ✅ 완료 | ✅ 통과 |
| `content/ui/theme.ts` | 3 | ✅ 완료 | ✅ 통과 |
| `content/ui/mock.ts` | 3 | ✅ 완료 (검증용) | ✅ 통과 |

`npx tsc --noEmit` 전체 통과(strict + noUnusedLocals/Parameters). 스캐폴딩·`node_modules`는 Stream C가 완료해둠.

**현재 T-단계: T=4 종료.** B↔C align(B 주재) — `/scrap` 전송 계약 확정(§T4), C가 전면 수용 + Step 8(`postScrap`/`sendScrapRequest`/`drainRetryQueue`/`VITE_MOCK_SCRAP`) 구현 완료. **B 코드 변경 없음**(flushResults 기제공). 통합 `tsc`+`vite build` 통과. autosave는 C 우려 반영해 A 권장으로 상향(비블로킹). **다음: Step 9(팝업, C)·T=5 전체 QA.**

(이전 T=3) `session.ts` **완성**(전 상태전이 단위테스트 21/21 certify). A 위임 **Panel ended 상태** 구현(SessionStore 무변경). A 오케스트레이터가 B의 `mountPanel`/`createSessionQueue`/`useSession` 배선 — 시그니처 일치.

**검증:** dev 하니스로 브라우저 실측 — IDLE → ASKING(main) → 오답 채점(정답 초록✓/오답 빨강✕) → "선행 개념 짚어보기" 강등 → 재질문 1단계 → 정답 시 진행률 갱신·IDLE 복귀 → **"학습 종료" → ended 상태("학습을 마쳤어요 · 맞힘 1/푼 문항 1")** 전 구간 확인. 요약은 flush 전 스냅샷으로 잡아 0 표시 안 됨.

---

## 1. 공개 API — 다른 스트림이 호출/연동하는 표면

### `content/session.ts` — 세션 상태머신 (zustand store)

```typescript
// SessionStore 구현체. React 훅이자 vanilla store(getState/setState/subscribe 보유).
export const useSession   // create<SessionStore & {parentConcept}>()

// ── 외부(observer 배선)가 호출하는 진입점 ──
useSession.getState().startQuestion(quiz: Quiz)   // 문단 진입 시 main 문항 제시
                                                  // ⚠️ phase !== 'IDLE'이면 무시(한 번에 한 문항)

// ── UI(ui/**)가 호출 ──
submitAnswer(selectedIndex: number)   // 클라이언트 즉시 채점 → 정답:IDLE / 오답:SHOW_EXPLANATION
dismissExplanation()                  // followup 있고 level<2 → 다음 재질문 / 아니면 IDLE

// ── 스크랩 전송(background 배선)이 호출 ──
flushResults(): ScrapResult[]         // 누적 results 반환 + 버퍼 초기화(전송 직전 1회)
```

- `phase`, `active`, `results`는 store 구독으로 읽음. `parentConcept`는 **내부 상태**(SessionStore 미노출) — UI 구독 금지.
- `results[].conceptTag`는 퀴즈 트리 값 echo: main=`Quiz.conceptTag`, 재질문=`Followup.prereqConceptTag`. `parentConcept`: level0=null, 재질문=상위 문항 개념(서버 엣지 복원용).

### `content/ui/mount.tsx` — Shadow DOM 마운트 (배선 담당이 호출)

```typescript
export interface MountOptions {
  onEnd?: () => void      // "학습 종료" 클릭 시 실행. 스크랩 전송 트리거를 여기 주입.
}
export interface PanelHandle { unmount: () => void }

export function mountPanel(options?: MountOptions): PanelHandle
// - custom element(prober-panel)에 shadow root + React 패널 렌더 (1회, 중복 방지)
// - <html> paddingRight = PANEL_WIDTH_PX 로 본문을 왼쪽으로 밀어줌(가림 방지)
// - onEnd 미주입 시 flushResults()만 수행(mock 동작)
```

- React 컴포넌트(Panel 이하)는 **SessionStore만** 다룸. DOM·서버·chrome API 직접 접근 없음.
- 브라우저/DOM 조작은 `mount.tsx` 글루 계층에만 격리.

### `content/session-bind.ts` — session 제출 큐 (T=2, 옵션1 확정본)

```typescript
import type { Quiz } from '../shared/types'   // observer/anchor는 import 안 함(옵션1)

export interface SessionQueue {
  enqueue: (quizzes: Quiz[]) => void   // IDLE이면 즉시 pump, 아니면 대기(FIFO)
  dispose: () => void                  // useSession 구독 해제
}
export function createSessionQueue(): SessionQueue
```

- **큐 "메커니즘"만** 제공. observer/anchor를 모른다. 컨트롤러(`content/index.tsx`, T=3)가 `observer.onParagraphEnter` **단일 콜백**을 소유하고, `anchor.byParagraph.get(idx)` → `Quiz[]`를 뽑아 `enqueue()`로 넘긴다.
- 내부: 큐 적재 → session이 `IDLE`일 때만 하나씩 `startQuestion`. `useSession.subscribe`로 phase→IDLE 복귀 감지해 pump. observer(one-shot)·session(단일 문항) 그대로, **유실 방지**만 이 큐가 담당(§2.1).
- **T=2 최종 결정(옵션1)의 산출물.** 이전 `connectObserverToSession(observer, anchor)`(콜백 자체 등록형)에서 콜백 비점유형으로 리팩터 완료.

---

## 2. 크로스-스트림 계약 & align 필요 항목

### 2.1 [🟢 RESOLVED · T=2] observer → session 배선 + 유실 방지

- **경로 확정:** `observer.onParagraphEnter(idx)`[컨트롤러 소유] → `anchor.byParagraph.get(idx)` → `Quiz[]` → `queue.enqueue()` → `IDLE`일 때 `startQuestion(quiz)`. 큐/pump는 `session-bind.ts`의 `createSessionQueue()`가 구현(옵션1).
- **T=2에서 발견한 통합 레이스(중요):** observer는 문단당 1회 발화 후 `unobserve`(one-shot). 사용자가 **문항 풀이 중(phase≠IDLE)** 다른 문단이 진입하면 `startQuestion`이 드롭되는데, 그 문단은 이미 `fired`+`unobserve`라 **재발화 안 됨 → 퀴즈 유실**.
- **해결(확정):** 진입 Quiz를 **큐에 적재**하고 session이 IDLE로 복귀할 때마다(`useSession.subscribe`로 감지) 하나씩 pump. 이로써:
  - 한 문단에 Quiz 여러 개(`byParagraph`가 `Quiz[]`) → 순차 제시.
  - 풀이 중 진입 → 유실 없이 다음 차례에 제시.
  - observer(one-shot)·session(단일 문항) 계약 **변경 없음**. 유실 방지 로직만 바인더에 격리.
- **단위 테스트 통과(2026-07-21):** 문단2(qA) 풀이 중 문단5 진입(qB,qC 2개) → qA 정답 → qB → qC 순차 제시, 결과 3건 순서 A,B,C 확인.
- **A에게 알림:** 위 큐 방식이므로 **"busy 시 rearm으로 재발화"는 불필요**. `rearm()`은 재추출/SPA 이동 시 용도로만 남겨두면 됨. 이견 있으면 회신.
- **⚠️ A와 구현 위치 충돌:** A(§2b)는 이 큐를 **컨트롤러 인라인**으로, B는 **`session-bind.ts`**로 구현 — 로직 동일하나 `onParagraphEnter` 단일 등록이라 **택일 필요.** 상세·권장안 **→ §2c** 참조.

### 2.2 [🔴 align 필요 · C] `onEnd` = flushResults + `/scrap` 전송 조립 (T=4)

- **B가 제공:** `flushResults(): ScrapResult[]` (필드 `conceptTag`/`parentConcept`/`level`/`correct`, `shared/types.ts` 그대로).
- **B가 소유하지 않음:** `ScrapRequest`의 `articleTitle`·`articleBody`. 이 둘은 extractor의 `ExtractResult`에서 옴.
- **배선 계약 제안:** `content/index.tsx`(통합)가 `ExtractResult`를 들고 있다가
  `mountPanel({ onEnd: () => sendMessage({ type:'SEND_SCRAP', payload:{ articleTitle, articleBody, results: useSession.getState().flushResults() } }) })`
  형태로 onEnd를 조립. **C 확인 요청:** background `SEND_SCRAP` 핸들러가 이 payload를 그대로 받는지.
- **전송 시점**(탭 닫힘/이탈/자동저장/beforeunload)은 **C 소관**. UI는 "학습 종료" 버튼 → `onEnd` 만 노출. C가 종료 외 시점에도 `flushResults()`를 호출할 수 있음(멱등: 두 번째 호출은 빈 배열).

### 2.2b [🟡 확인 요청 · A/통합] observe() 대상은 "앵커된 문단만"

- A 문서 §2.3에 **동의.** observer는 idx 기반이라, 배선 주체가 `observer.observe()`에 **anchor가 매칭한 문단만** 넘겨야 헛발화가 없음.
- `session-bind.ts`는 observer가 **이미 observe() 완료된** 상태를 가정하고 그 이벤트만 받는다. 따라서 **"anchor된 문단만 observe"는 배선 주체(content/index.tsx, T=3)의 책임**.
- **권장 배선:** `observer.observe(anchor된 Paragraph[])` — 예: `[...anchor.byParagraph.keys()]`를 `paragraphElement(idx)` 또는 원본 `Paragraph[]` 필터로 얻어 넘김. (extractor의 `Paragraph[]`에서 `byParagraph`에 키가 있는 idx만.)

### 2.3 [🟡 대부분 해소 · A 응답 반영] 하단 강등(`unanchored`) 처리

- **A 응답(§2b 응답2):** `unanchored`를 **큐에 append**해 기존 단일 패널로 순차 노출 → **B는 별도 하단 목록 UI 불필요.** (전용 UI는 post-MVP, 만든다면 패널 내 섹션 권장.)
- **B 수용:** 동의. 이 방식이면 B의 Step 3 단일 패널 그대로로 충분, **하단 UI 구현 부담 제거.** (차이 상세 §2c-D3)
- **남은 미결(A도 지적):** flush 트리거 = "마지막 문단 스크롤 도달" 의존 → 중간 이탈 시 강등 퀴즈 유실. MVP 기본=마지막 문단, fallback=종료 버튼 시 남은 unanchored 제시. **T=3에서 트리거 확정.**

### 2.4 [🟢 정보] UI 격리·마운트 규약

- UI는 `SessionStore`만 구독. `selected`(보기 선택)는 store가 아니라 `QuestionView` **로컬 state** — `active` 변경 시 Panel이 `key`로 remount해 초기화(store 오염 방지).
- Shadow DOM(`prober-panel`) + 주입 CSS로 기사 페이지와 완전 격리. 페이지 여백 조정은 mount 글루가 담당.
- 텍스트는 extractor의 `normalizeText()` 출처를 따름(문단 텍스트 다룰 일 있으면 재사용).

---

## 2c. ✅ Stream A와의 차이 — **RESOLVED (T=2 종료, 옵션1 확정·실행 완료)**

> **결말:** Stream A가 `stream_a_align.md §2b-확정`에서 **옵션 1 채택**(B 권장 그대로). B는 `session-bind.ts`를 `createSessionQueue()`로 **리팩터 실행 완료** + 단위테스트 9/9 재통과 + `tsc` 통과. **D1~D5 전원 종결.** 아래는 이력 보존용 차이 기록.

### (A) B가 T=1~T=2에 실제로 만든/바꾼 파일 (Stream A 파일은 일절 미수정)

| 파일 | 내용 | 단계 |
|------|------|------|
| `src/content/session.ts` | `SessionStore` zustand store 구현 (`startQuestion`/`submitAnswer`/`dismissExplanation`/`flushResults`), `parentConcept` 내부 추적 | Step 6 코어 (T=1) |
| `src/content/session-bind.ts` | **`createSessionQueue()`** → `{enqueue, dispose}`. 큐+IDLE pump 메커니즘(옵션1 확정본, observer/anchor 미import) | T=2 |
| `src/content/ui/Panel.tsx` | 패널 루트, SessionStore만 구독, 진행률·정답 토스트 | Step 3 |
| `src/content/ui/QuestionView.tsx` | 질문/보기/제출/채점 뷰, `selected` 로컬 state | Step 3 |
| `src/content/ui/Explanation.tsx` | 오답 설명 + 강등/계속 분기 | Step 3 |
| `src/content/ui/mount.tsx` | Shadow DOM 마운트(`mountPanel`), 페이지 여백 밀기 | Step 3 |
| `src/content/ui/theme.ts` | shadow root 주입 CSS | Step 3 |
| `src/content/ui/mock.ts` | 2단계 재질문 mock 트리 (검증용) | Step 3 |
| `demo/*`, `vite.demo.config.ts` | dev 하니스 (gitignore 산출물, 확장 빌드 미포함) | 검증용 |
| `docs/stream_b_align.md` | 이 문서 | T=1~ |

검증: `npx tsc --noEmit` 통과, 브라우저 실측(전 상태), `session-bind` 큐 로직 rolldown 번들 단위테스트 9/9.

### (B) stream_a_align.md 내용과 **차이 있는 부분**

| # | 항목 | Stream A (§2b) | Stream B (구현) | 충돌 |
|---|------|----------------|-----------------|------|
| D1 | **큐/pump 소유 위치** | **컨트롤러(`content/index.tsx`)가 인라인 소유**. "session.ts 무변경, 큐 추가 불필요. 컨트롤러가 getState()·subscribe()만." | **`session-bind.ts`(B 소유 모듈)** `connectObserverToSession`에 캡슐화 | 🔴 동일 로직 2곳·소유자 다름 |
| D2 | **`onParagraphEnter` 단일 콜백 주인** | 컨트롤러가 그 **단일 콜백**을 잡고 (큐 append + unanchored flush)를 **한 콜백에서** 처리 (이중 등록 버그 수정 명시) | `connectObserverToSession`이 **`observer.onParagraphEnter`를 자체 등록** | 🔴 단일 등록이라 **공존 불가** (나중 등록이 앞을 덮음) |
| D3 | **unanchored 처리** | **큐에 append** → 별도 UI 불필요. flush 트리거=마지막 문단(+종료 fallback) | B는 "하단 목록 UI를 B가 구현" 필요로 열어둠(§2.3), 바인더는 unanchored 미처리 | 🟡 A안이 B의 UI 부담 제거 → **A안 수용 시 §2.3 상당부분 해소** |
| D4 | **observe() 대상** | 컨트롤러가 `앵커 문단 + lastIdx` observe (lastIdx는 unanchored flush 트리거용) | B는 "observe는 컨트롤러 책임"에 동의(§2.2b), 단 lastIdx 언급 없었음 | 🟢 방향 일치, 세부(lastIdx)만 A가 보강 |
| D5 | session.ts 변경 여부 | 무변경 | 무변경 | 🟢 일치 |

> **근본 원인:** D1·D2는 같은 뿌리 — "큐+단일 콜백을 **컨트롤러(A안)** vs **session-bind.ts(B안)** 중 누가 갖는가". 로직은 동일. `onParagraphEnter`가 단일 등록이라 **둘 중 하나만** 콜백을 소유할 수 있음. → 반드시 택일.

### (C) B 권장 해소안 (A가 최종 결정)

**옵션 1 — 역할 분리 (B 권장 ★).** 큐 "메커니즘"은 B의 테스트된 모듈로 남기되, **단일 콜백은 컨트롤러가 소유**(A의 §2b 구조 유지). 이를 위해 `session-bind.ts`를 콜백 비점유형으로 리팩터:
```typescript
// session-bind.ts (B) — 콜백을 점유하지 않는 큐 메커니즘만 제공
export function createSessionQueue(): {
  enqueue: (quizzes: Quiz[]) => void   // IDLE이면 즉시 pump, 아니면 대기
  dispose: () => void                  // subscribe 해제
}
```
```typescript
// content/index.tsx (A/통합) — 단일 콜백은 컨트롤러가 소유
const q = createSessionQueue()
observer.onParagraphEnter((idx) => {
  const qs = anchor.byParagraph.get(idx); if (qs) q.enqueue(qs)
  if (!flushed && idx === lastIdx && anchor.unanchored.length) { flushed = true; q.enqueue(anchor.unanchored) }
})
```
→ A가 원한 "컨트롤러 단일 콜백 소유 + unanchored flush 한 콜백" 성립 **AND** 큐/pump는 B의 단위테스트된 코드 재사용(로직 중복·비테스트 인라인 방지). **B는 이 리팩터를 즉시 수행 가능.**

**옵션 2 — A안 그대로.** 컨트롤러가 큐까지 전부 인라인 소유. 그러면 **`session-bind.ts`는 삭제**(중복·경쟁 등록 방지). B가 검증한 큐 로직은 stream_b_align의 테스트 케이스로만 남김.

> **결정(Stream A, §2b-확정):** ✅ **옵션 1 채택.** 큐 메커니즘=B 모듈, 단일 콜백=컨트롤러. A/C/session/observer/anchor **코드 무변경.** B는 `session-bind.ts`를 `connectObserverToSession` → `createSessionQueue`로 리팩터 **완료(2026-07-21)**, 테스트 9/9·tsc 통과.
>
> A가 명시한 경계: `createSessionQueue` **시그니처는 B 소유**, A는 `enqueue(Quiz[])`+`dispose()` 시맨틱만 의존. idx→Quiz 해석·`onParagraphEnter`/`observe`·unanchored flush(마지막 문단 1회)는 **컨트롤러(T=3)** 책임.

---

## §T3. Stream A T=3 RFC(§T3) 검토 응답 (Stream B)

> Stream A가 `stream_a_align.md §T3`로 오케스트레이터 소유권·부트 시퀀스·mock을 확정 제안(RFC)함. B 관점 검토 결과.

### ✅ 동의 (이견 없음)

- **T3.1 오케스트레이터 = A 소유** — 동의. `content/index.tsx` 소유권 순환 미룸 종결. B는 `mountPanel`/`createSessionQueue`/`useSession` 공개 API 제공만.
- **T3.2 부트 게이트·실패 시 조용히 중단** — 동의. `MIN_ARTICLE_PARAGRAPHS`는 오케스트레이터 로컬 상수, `shared/constants` 안 건드림 OK.
- **T3.3 라운드트립·articleTitle/body 주입** — 동의. `onEnd`가 오케스트레이터의 `ExtractResult`에서 `articleTitle/body` 주입 + `flushResults()` 결과로 `SEND_SCRAP` 조립 → B §2.2 종결. B의 `mountPanel({onEnd})`·`flushResults()` API와 정확히 일치.
- **T3.4 mock = C의 api.ts dev 모드** — 동의. (아래 🟢 제안 참조)
- **T3.6 레퍼런스 스케치** — B API 사용부(`mountPanel`/`createSessionQueue`/`useSession.getState().flushResults`) 전부 시그니처 일치 확인. import 경로 정상.

### ✅ T3.5 B 확인요청 답 — "패널 IDLE 상태 OK인지"

- **OK. 빈 화면 아님.** Panel의 IDLE 상태는 이미 안내 문구를 렌더함: 📖 + "기사를 읽어 내려가면 / 놓치기 쉬운 지점에서 질문이 나타나요." (T=1 브라우저 실측 완료.)
- A가 mount 시점을 **"퀴즈 확보 후"** 로 잡은 것과 이 copy가 정합적임(퀴즈 준비됨 → 스크롤 대기). **이대로 진행.**
- (참고) 퀴즈 생성 네트워크 대기 중엔 패널이 아예 없음(mount 전). MVP는 이대로 OK. "분석 중…" 로딩 표시는 `LOADING` phase 신설이 필요해 **post-MVP**로 둠 — 이견 아님, 향후 옵션.

### ✅ 보완 1 — `onEnd` teardown [RESOLVED, T=3]

> **결말:** A가 `index.tsx` `onEnd`에 `queue.dispose()`+`observer.disconnect()` 추가(세션 정지)했고, **ended 상태 UI는 B에 위임**(A: "SessionStore 무변경, 종료 버튼 내부에서 렌더"). B가 Panel에 ended 상태 구현 완료 → 종료 후 새 문항 안 뜨고 "학습을 마쳤어요 · 요약" 표시. 브라우저 실측 확인. 아래는 원문 기록.

#### (원문) 문제 제기 — "학습 종료" 후 세션이 안 멈춤

- **문제:** T3.6 `onEnd`는 `flushResults()` + `SEND_SCRAP`만 함. `queue.dispose()`·`observer.disconnect()`를 안 해서, **종료 후에도** observer가 계속 발화 → `queue.enqueue` → 새 문항이 뜬다. 결정4가 막으려던 "종료 뒤 문항 뜨는 모순 UX"가 **일반(앵커) 퀴즈에서 그대로 남음**(결정4는 unanchored flush만 다뤘음).
- **부작용:** 종료 후 답한 문항은 새 버퍼에 쌓이지만 재전송 트리거가 없어(자동저장=C의 T=4) **유실**. 또 `flushResults`는 멱등이라 종료 2회 클릭 시 2번째는 빈 `results`로 `SEND_SCRAP` → 빈 스크랩 전송.
- **B 제안(A 오케스트레이터 배선):** `onEnd`에서 **세션 정지**도 수행:
  ```typescript
  const panel = mountPanel({
    onEnd: () => {
      const results = useSession.getState().flushResults()
      void chrome.runtime.sendMessage({ type:'SEND_SCRAP', payload:{ articleTitle: extract.title, articleBody: extract.body, results } } satisfies ChromeMessage)
      queue.dispose()          // ← 추가: phase 구독 해제(새 pump 중단)
      observer.disconnect()    // ← 추가: 이후 진입 발화 중단
      panel.unmount()          // ← 추가(택1): 패널 제거로 종료 확정. 또는 아래 ended 상태.
    },
  })
  ```
  - B가 이미 제공하는 것: `mountPanel`은 `PanelHandle{ unmount }` 반환, `createSessionQueue`는 `dispose`, observer는 `disconnect` 보유 → **A는 배선만** 하면 됨. **B/observer/session 코드 변경 불필요.**
- **UI 선택지(B 소관):** 종료 후 (a) 패널 `unmount`(가장 단순) vs (b) "학습을 마쳤어요 · 결과를 저장했어요" **ended 상태 표시**. (b)는 Panel에 작은 상태 추가 필요 — 사용자에게 저장 피드백을 주므로 UX상 권장. **A가 (a)/(b) 원하는 쪽 알려주면 B가 (b) 구현.** 기본은 (a)로도 무방.
- **정리:** 필수 = `onEnd`에서 `dispose()`+`disconnect()`로 **새 문항 정지**(A 배선). 선택 = ended 상태(B 구현). 이 한 건만 반영되면 §T3 전면 동의.

### 🟢 제안 (선택) — mock fixture는 B의 `ui/mock.ts` 재사용

- T3.4 mock의 canned `Quiz[]`로 **B의 `MOCK_QUIZZES`(`ui/mock.ts`)를 그대로** 쓰면 fixture 이원화 방지. 2단계 재질문 트리까지 있어 e2e 커버리지 좋음. C가 import만 하면 됨(같은 `Quiz` 타입). C 재량.

---

## §T4. T=4 B↔C align — `/scrap` 전송 (**Stream B 주재 결정**)

> shared_contract T=4 과제: `/scrap` 전송 완성(Step 8). **이번 align은 Stream B가 최고참으로 결정**하고, C는 `stream_c_align.md`에 이견을 남기거나 그대로 진행.
> 근거: `stream_c_align.md T=4` 체크리스트 + C 실코드(`background/api.ts`·`index.ts`) + A 오케스트레이터(`content/index.tsx`) 대조.

### T4.0 — 확정 데이터 흐름

```
"학습 종료"(B UI) / beforeunload(A) / (선택)autosave(A)
  └─ 오케스트레이터(A): const r = useSession.getState().flushResults()
                        if (r.length) chrome.runtime.sendMessage(
                          { type:'SEND_SCRAP', payload:{ articleTitle, articleBody, results:r } })
       └─ background(C): sendScrapRequest(payload) → POST /scrap (+Bearer best-effort)
                          실패 → RETRY_QUEUE 적재 → 기회 시 재전송
```

### T4.1 [결정] `ScrapRequest` 조립 주체 = **오케스트레이터(A)**, session/C 아님

- **C line 75 추정("세션이 ExtractResult 들고 있다가 넘김") 정정:** B의 session store는 **articleTitle/body를 전혀 모른다**(퀴즈 결과만 보유). `articleTitle`/`articleBody`는 A가 쥔 `ExtractResult`에서, `results`는 `flushResults()`에서 → **A가 조립**. C는 완성된 `payload`를 받기만.

### T4.2 [결정] `flushResults()` 계약 — drain+clear, **부분 배치 다중 전송 허용**

- **C line 74 확인 요청 응답: YES.** `flushResults(): ScrapResult[]`는 `shared/types.ts`의 `ScrapResult`(`conceptTag`/`parentConcept`/`level`/`correct`) 그대로. 추가 래핑 없음.
- drain 후 버퍼를 비움 → 한 기사에 `SEND_SCRAP`가 **여러 번** 갈 수 있음(autosave + 종료). 각 메시지는 **직전 flush 이후 누적분(부분 배치)**. 서버 임시 버퍼가 병합(system_overview §데이터 흐름).
- **빈 배치 가드:** 송신측(A)이 `results.length === 0`이면 **전송 스킵**. C는 빈 `results`가 와도 방어적으로 **200 no-op** 처리(크래시 금지).

### T4.3 [결정] 전송 "시점(트리거)" = **content-side(오케스트레이터 A)**, "전송·재시도" = **background(C)**

- **근거(변경 불가):** `flushResults`는 content-script zustand에 있어 **background가 호출 불가**. content의 `beforeunload`·읽기 진행도 역시 content만 관측 → **트리거는 반드시 content(A)**.
- **⚠️ C line 78 정정:** "Stream C가 전송 시점 처리(탭 닫힘/이탈/자동저장)"는 **C 소관 아님**. C는 **네트워크 전송 + 재시도 큐**만 소유. 트리거 배선은 A.
- 트리거 분류:
  - **필수(MVP):** 학습 종료 → `SEND_SCRAP` (이미 T=3 배선 완료).
  - **권장(A, 소규모):** `beforeunload` → best-effort flush+send. *핸드오프만 되면(sendMessage는 즉시 배경에 도달) 실제 fetch는 background가 이어가므로 신뢰도 양호* — 페이지 닫혀도 background 큐가 커버.
  - **선택/이월:** 주기적 autosave 타이머 → Step 10 여력 시. (도입 시 A는 종료/teardown에서 `clearInterval` 필수.)

### T4.4 [결정] 재시도 큐 = **C 소유 (background)**

- **실패 시:** `ScrapRequest`를 `chrome.storage.local[STORAGE_KEYS.RETRY_QUEUE]`(=`ScrapRequest[]`)에 append.
- **drain:** (a) 다음 `sendScrapRequest` 성공 직후 큐 비우기 + (b) 서비스워커 시작 시 1회 시도. 동시 drain 방지 in-flight 플래그.
- **Bearer:** `sendScrapRequest`도 기존 `buildHeaders()` 재사용(quiz와 동일 best-effort 토큰). 현행 plain 헤더 → 교체.
- **중복:** flush가 매번 버퍼를 비우므로 각 batch는 distinct → 클라이언트 dedup 불필요. "서버 저장 후 5xx" 재전송 시 서버측 중복 가능 = **MVP 허용**(서버 merge가 개념 단위 흡수). 담당3 확인 사항.

### T4.5 [결정] content-side는 **fire-and-forget**

- A의 `onEnd`는 `sendMessage` 후 `SCRAP_RESPONSE/ERROR`를 **대기하지 않음**(`.catch(()=>{})`). 내구성은 전적으로 background 재시도 큐가 책임. **content는 재시도 안 함.**

### T4.6 [권장] scrap mock (무서버 e2e)

- `VITE_MOCK_QUIZ`처럼 scrap도 mock/no-op 경로를 두면, 서버 없이 e2e 돌릴 때 `/scrap` 실패로 큐만 쌓이는 것을 방지. 플래그 신설(`VITE_MOCK_SCRAP`) 또는 기존 재사용 — **C 재량.** 미도입 시 mock e2e에서 scrap은 큐 적재됨(기능상 문제 아님).

### T4.7 — 스트림별 작업 & C 확인 요청

| 스트림 | T=4 할 일 |
|--------|-----------|
| **B** | **없음(코드 변경 0).** `flushResults()` 제공 완료, 위 계약 확정. |
| **C** | `sendScrapRequest`에 `buildHeaders()` + **RETRY_QUEUE 적재/drain**(T4.4) + 빈 `results` 방어(T4.2) + (선택)scrap mock(T4.6). |
| **A** | `onEnd` 빈 가드(`if r.length`) + (권장)`beforeunload` 트리거. autosave 도입 시 teardown에서 `clearInterval`. |

> **C에게:** T4.3(트리거=content·전송/재시도=C 소유 분리), T4.4(큐 스펙), T4.6(scrap mock)에 이견 있으면 `stream_c_align.md`에 남겨주세요. 없으면 위 계약대로 Step 8 진행. 타입 계약(`ScrapRequest`/`ScrapResult`/`ChromeMessage`)은 이미 `shared/types.ts`와 전부 일치 — **shared 타입 변경 없음.**

### T4.8 — ✅ C 리뷰 결과 & 잔여 결정 (RESOLVED)

- **C 전면 수용:** `stream_c_align.md T=4`에서 T4.1/T4.2/T4.4/T4.5/T4.6 이견 없음. T4.3은 C가 자기 이전 추정("전송 시점 처리=C 소관")이 틀렸음을 인정하고 **소유 분리(트리거=A, 전송·재시도=C) 수용**, 해당 체크리스트 항목 취소.
- **C 구현 완료(Step 8):** `postScrap`(공용 전송) + `sendScrapRequest`(빈 배치 즉시반환·`VITE_MOCK_SCRAP`·실패 시 큐 적재 후 정상반환) + `drainRetryQueue`(순서 보존·`drainInFlight` 재진입 가드) + `background/index.ts` 최상단 `void drainRetryQueue()`(SW 시작 시 drain). drain 3케이스 스크립트 검증, tsc·build 통과.
- **통합 검증(B 수행):** 전체 트리 `tsc --noEmit` + `vite build` 통과(A 오케스트레이터+B session/ui+C /scrap 코버들). 이상 없음.
- **B→C 참고(비블로킹):** C의 `sendScrapRequest`는 fetch 실패 시에도 큐 적재 후 정상반환 → `SCRAP_RESPONSE{ok:true}`가 "서버 확인"이 아니라 **"전송 or 재시도 예약됨"** 을 뜻하게 됨. content는 fire-and-forget이라 무해(T4.5). 추후 누가 이 응답에 의존하면 재검토.

#### 🟡 잔여 결정 — 주기적 autosave (C 제기, B 판정)

- **C 우려:** plan §3.6은 "주기적 자동저장 + 종료 시 flush 병행"을 요구하나, B의 T4.3은 autosave를 Step 10으로 미룸. `beforeunload`가 **아예 안 뜨는 경우**(브라우저 크래시·강제종료)엔 유실. C는 **비블로킹**으로 기록만 남김.
- **B 판정(트리거 소유=A이므로 B가 결정):** C 지적 타당함. **차단하진 않되, "선택/이월" → "🟢 권장(A)"으로 상향.** 근거: 구현이 소규모(A 오케스트레이터 ~5줄)이고 plan §3.6 명시 요구. 미포함 시 크래시 유실은 **명시적 감수 항목**으로 남김.
- **A용 최소 스펙(트리거는 A 소유):**
  ```typescript
  const AUTOSAVE_MS = 30_000
  const timer = setInterval(() => {
    const r = useSession.getState().flushResults()
    if (r.length) void chrome.runtime.sendMessage(
      { type:'SEND_SCRAP', payload:{ articleTitle: extract.title, articleBody: extract.body, results:r } })
  }, AUTOSAVE_MS)
  // onEnd/beforeunload teardown에서: clearInterval(timer)
  ```
  - **안전성 확인:** autosave가 중간에 flush해도 각 `ScrapResult`가 `parentConcept`를 자체 보유하므로(T4.2), 배치가 쪼개져도 서버가 개념 단위로 엣지 복원 → **유실·왜곡 없음.**
- **A용 참고(부담 경감):** C가 **수신측 빈 배치 가드**를 이미 넣었으므로(`results.length===0` 즉시반환), A의 `onEnd` 빈 가드(`if r.length`)는 **선택**(방어적 중복). 없어도 빈 전송은 C가 no-op 처리.

### T4.9 — 재시도 큐 동작 방식 확인 (B 검증 결과 → C)

> shared_contract T=4 align 항목 "재시도 큐 동작 방식 확인"을 B(align 상대)가 C의 실제 `background/api.ts` 코드와 T4.4 계약 대조로 수행.

**✅ 계약 준수 확인 (정상):**
- FIFO 순서 보존: `drainRetryQueue`가 head부터 처리, 실패 시 `break` + 나머지 큐 유지 → 순서·유실 없음(단일 drain 기준).
- `drainInFlight` 재진입 가드(drain-vs-drain), 빈 배치 방어, `VITE_MOCK_SCRAP`, `buildHeaders()`(Bearer) 재사용, drain 트리거 2곳(성공 직후 + SW 시작). 전부 T4.4대로.
- C self-test 3케이스(전부성공/중간실패/빈큐) 로직 건전.

**🟠 B 검증에서 발견 (C self-test 미커버, 큐=C 소유 → C 판단):**
1. **enqueue↔drain read-modify-write 레이스 (lost update).** `sendScrapRequest` 실패 catch(`getRetryQueue`→`push`→`setRetryQueue`)와 `drainRetryQueue`가 동시 실행되면 둘 다 같은 큐를 읽고 각자 덮어써 **배치 1건 유실** 가능. `drainInFlight`는 drain끼리만 막음. 트리거: SW startup drain 또는 성공-직후 drain이 도는 중에 다른 `SEND_SCRAP`가 실패할 때.
   - *제안(택1):* 모든 큐 mutation을 단일 async 뮤텍스로 직렬화 / 또는 실패 시 "직접 push" 대신 큐에 넣고 drain에 위임(단일 writer화).
2. **poison message / 재시도 상한 없음.** drain이 head 영구 실패(예: 400 malformed) 시 매번 head에서 `break` → **큐 전체가 영구 정체**(뒤 항목까지 블록).
   - *제안:* 항목별 시도횟수/최대치 두고 초과 시 drop(또는 dead-letter), 4xx는 재시도 제외.

**판정:** 둘 다 **데모 happy-path 비영향 엣지** → MVP 블로킹 아님. 단 "동작 방식 확인" 결과로 기록. **수정 여부·방법은 C 재량**(이견/수용 `stream_c_align.md`에). B는 계약(T4.4) 준수는 확인함.

---

## 3. 미결 / 미소유 항목

- **배선 파일(`content/index.tsx`) 소유권 미정.** A·C 문서 모두 미정 제기. A 제안=파이프라인이라 A 초안+C 리뷰. **T=3 전체 align에서 확정.** 컨트롤러는 `createSessionQueue()`(B) + `observer.onParagraphEnter`(단일 콜백) 소유. B는 §1 API 제공까지 책임.
- ~~하단 강등 UI~~ → **A 확정: 별도 UI 불필요**(unanchored를 큐 append). B는 Step 3 단일 패널 그대로. flush 트리거=마지막 문단 1회(조기 이탈 미제시, Step 10 재검토).
- ~~동시 진입 큐 정책~~ → **T=2 확정**(옵션1: `createSessionQueue`).
- **큐 상한/만료:** A 확정=MVP 무제한. 필요 시 상한/"지나간 문단 만료"는 B가 큐 모듈에 추가 — Step 10 QA 관찰.
- **패널 접기/열기·리사이즈** 등 UX 부가기능 미구현 (MVP 범위 밖, Step 10 여력 시).
- **UI 문구/디자인 토큰**은 `theme.ts` CSS 변수로 모아둠 — Step 10 QA 때 조정 가능.

---

## 4. 변경 이력 (T-단계별)

### T=1 (2026-07-21)
- Step 3 mock UI 완성 — `Panel`/`QuestionView`/`Explanation` + Shadow DOM `mount.tsx` + `theme.ts` + `mock.ts`.
- session store(`session.ts`, Step 6 코어) 선행 완성 — UI가 실제 `SessionStore` 구독하도록.
- dev 하니스로 전 구간 브라우저 실측 검증, `tsc --noEmit` 통과.
- align 항목 §2.1(observer→session 다중 Quiz), §2.2(onEnd/scrap 조립), §2.3(하단 강등 UI 주체) 제기.

### T=2 (2026-07-21) — A↔B align
- A의 `anchor.ts`·`observer.ts` 실구현 확인: `byParagraph: Map<number, Quiz[]>`(문단당 다중 Quiz 가능), observer는 문단당 1회 발화 후 `unobserve`(one-shot).
- **발견:** 풀이 중 문단 진입 시 startQuestion 드롭 + one-shot unobserve → **퀴즈 유실 레이스**.
- **확정:** `session-bind.ts`의 `connectObserverToSession(observer, anchor)` 신설 — 진입 Quiz를 큐에 쌓고 IDLE 복귀 시 pump. observer/session 계약 무변경, 유실 방지만 격리. rolldown 번들 단위 테스트 9/9 통과.
- §2.1 RESOLVED. §2.2b(observe 대상=앵커 문단만) A에 확인 요청. A에게: busy-rearm 불필요 통지.

### T=2 (2026-07-21, 추가) — A 응답(§2b) 대조 → 차이 발견
- A가 `stream_a_align.md §2b`로 응답 갱신함을 확인. **동일 큐 로직을 A는 컨트롤러 인라인, B는 `session-bind.ts`로** 구현 → `onParagraphEnter` 단일 등록 특성상 **공존 불가, 택일 필요**.
- unanchored는 A안(큐 append, 별도 UI 불필요) 수용 → §2.3 대부분 해소, B의 하단 UI 부담 제거.
- **§2c 신설:** B 작업 파일 목록 + A와의 차이표(D1~D5) + 권장 해소안(옵션1: 큐 메커니즘 B 모듈 유지 + 콜백은 컨트롤러 소유) 정리. **Stream A에 최종 결정 위임.**

### T=2 (2026-07-21, 종료) — A 옵션1 확정 → B 리팩터 실행
- Stream A가 `§2b-확정`에서 **옵션1 채택**(B 권장 그대로). D1~D5 전원 종결.
- **B 실행:** `session-bind.ts`를 `connectObserverToSession(observer, anchor)` → **`createSessionQueue(): {enqueue, dispose}`** 로 리팩터. observer/anchor type-only import 제거(A 경계 준수). 단일 `onParagraphEnter` 콜백은 컨트롤러(T=3) 소유.
- **검증:** enqueue 직접 구동 단위테스트 9/9 통과(풀이 중 enqueue 유실 없음·순차 제시·dispose 후 pump 중단 확인), `tsc --noEmit` 통과.
- **T=2 A↔B align 공식 종료.** 남은 건 T=3 컨트롤러 배선(소유권 확정 포함).

### T=3 (2026-07-21, B 작업) — session.ts 완성 + ended UI
- **session.ts 완성:** 전 상태전이(정답 main, 오답→설명→L1→L2 강등 parent 체인, 재질문 정답 종료, flush 멱등, IDLE/ASKING 가드) **단위테스트 21/21 통과**로 certify. 로직 이미 완결 → **코드 변경 없음.**
- **Panel ended 상태 구현(A 위임):** "학습 종료" 클릭 시 요약 스냅샷(flush 전) 캡처 → "🎉 학습을 마쳤어요 · 맞힘 X/푼 문항 Y · 진단 결과를 저장했어요" 렌더. 종료 버튼·진행률 숨김. **SessionStore 무변경**(Panel 로컬 state). `theme.ts`에 ended CSS 추가.
- **onEnd 보완 RESOLVED:** A가 `index.tsx` onEnd에 `queue.dispose()`+`observer.disconnect()` 추가(세션 정지) + B의 ended UI로 종료 후 새 문항 없음 확인.
- 브라우저 실측: 정답→종료→ended 요약(맞힘 1/푼 문항 1) 확인. `tsc --noEmit` 통과. (demo onEnd에서 alert 제거 — 브라우저 자동화 블로킹 회피.)

### T=3 (2026-07-21) — A의 §T3 RFC 검토 (Stream B)
- A가 오케스트레이터 소유권(=A)·부트 시퀀스·라운드트립·mock을 §T3로 확정 제안. **B 검토: T3.1~T3.6 대부분 동의.**
- **동의:** index.tsx=A 소유, 부트 게이트, articleTitle/body 주입=오케스트레이터(B §2.2 종결), mock=C dev 모드. B API 사용부 시그니처 전부 일치.
- **T3.5 답:** 패널 IDLE은 이미 안내 문구 렌더(빈 화면 아님), mount-after-quiz와 정합 → OK.
- **🟠 보완 1건 제기:** `onEnd`가 flush+전송만 하고 `queue.dispose()`/`observer.disconnect()` 미수행 → **종료 후에도 새 문항 뜸**. A 배선에 세션 정지 추가 요청(B API는 이미 지원: `PanelHandle.unmount`/`dispose`/`disconnect`). ended 상태 UI는 B가 구현 가능(A 선택).
- **🟢 제안:** mock fixture로 B의 `MOCK_QUIZZES` 재사용(C 재량).

### T=4 (2026-07-21) — B↔C align, `/scrap` 전송 (Stream B 주재)
- C의 T=3 완료(`/quiz` + `VITE_MOCK_QUIZ` mock) 확인. C 실코드(`api.ts`/`index.ts`) 대조 — `sendScrapRequest`는 있으나 토큰·재시도 큐 미완(Step 8 TODO).
- **핵심 결정:** `flushResults`가 content zustand에 있어 background가 호출 불가 → **전송 트리거=content(A), 전송·재시도=background(C)로 소유 분리**(C line 78 정정).
- **§T4 신설(결정 T4.1~T4.7):** ScrapRequest 조립=오케스트레이터(A), flushResults=drain+부분배치 다중전송+빈가드, 재시도 큐=C(RETRY_QUEUE)+Bearer(buildHeaders 재사용), content=fire-and-forget, scrap mock 권장.
- **C 확인요청 응답:** line 74(flushResults=ScrapResult 그대로) = YES. line 75(조립 주체) = 세션 아님, 오케스트레이터(A).
- **B 코드 변경 없음** — 계약만 확정(flushResults 기제공). C 이견 대기.

### T=4 (2026-07-21, 종료) — C 수용·구현 확인 + autosave 판정
- C가 §T4 전면 수용(T4.1~T4.6), T4.3 소유 분리 정정 수용, Step 8 `/scrap` 구현 완료(`postScrap`/`sendScrapRequest`/`drainRetryQueue`/`VITE_MOCK_SCRAP`).
- **B 통합 검증:** 전체 트리 `tsc --noEmit`+`vite build` 통과(A+B+C 코버들, 38 modules).
- **autosave 판정(§T4.8):** C 우려 타당 → "선택/이월"에서 **A 권장으로 상향**(비블로킹), A용 최소 스펙 제공. 미포함 시 크래시 유실은 명시 감수.
- **참고:** C의 scrap은 실패 시 큐 적재 후 정상반환 → `SCRAP_RESPONSE.ok`=“전송 or 재시도 예약”. content fire-and-forget이라 무해.
- **재시도 큐 동작 방식 확인(§T4.9):** B가 C 실코드 대조 검증 — T4.4 계약 준수(FIFO 순서보존·in-flight 가드·빈배치·mock·토큰·drain 트리거) 확인. 추가로 엣지 결함 2건 발견해 C에 회부: ① enqueue↔drain read-modify-write 레이스(lost update), ② poison-message로 큐 영구 정체(재시도 상한 없음). MVP 비블로킹, 수정은 C 재량.
- **B의 T=4 종결.** 남은 트리거(beforeunload·autosave)는 A, 팝업은 C(Step 9).

### T=5 (2026-07-21) — B QA 완료
- A의 `stream_a_qa.md` 확인 — §4 통합 브라우저 체크리스트가 B 관련 항목(진단 루프·큐·종료/ended·스크랩 payload) 이미 포함 → **B 전용 브라우저 QA 불필요**.
- **회귀 게이트:** A(오케스트레이터)·C(/scrap) 통합 후 최종 트리에서 B 로직 재검증 — 전체 `tsc --noEmit` + B 회귀 통과.
- **재현 가능 QA 하니스 신설:** `qa/session-qa.ts` + `npm run qa:session`(A `qa:anchor`·C `qa:scrap`와 동일 패턴), 세션 상태머신+큐 **22/22 통과**.
- **`stream_b_qa.md` 작성**(handoff) — B 완성도·자동 QA·UI 실측·§4 B 표면 매핑·한계.
- **B의 T=1~T=5 전부 종결.** 코드: `session.ts`/`session-bind.ts`/`ui/**`. QA: 자동(qa:session) + UI 실측 + 통합 빌드.

<!-- (T=5 종료) -->
