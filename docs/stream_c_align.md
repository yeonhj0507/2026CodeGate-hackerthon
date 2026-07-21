# Stream C — Align 로그 (Infrastructure)

> 담당 파일: `manifest.json`, `background/api.ts`(+`background/index.ts`), `popup/**`
> Steps: 1 → 7 → 8 → 9 (T=3 align에서 Step 7이 배정됨, `shared_contract.md` Align 일정 참고)
> 이 문서는 Stream C가 다른 스트림(A/B)·서버팀과 맞춰야 할 내용을 T 시점마다 갱신한다.
> 타입 계약 자체는 `docs/shared_contract.md`가 원본이며, 여기는 **진행 상태 + align 체크리스트**만 다룬다.

---

## 현재 상태: T=4 완료 — Step 7(`/quiz`) + Step 8(`/scrap`) 둘 다 완성

`background/api.ts`가 `/quiz`·`/scrap` 양쪽 모두 Bearer best-effort 첨부 + mock 모드 + (`/scrap`은) 재시도 큐까지 갖춤. 남은 Stream C 몫은 **Step 9(팝업 로그인)**와 **T=5 브라우저 실측 QA**.

- [x] Step 1 스캐폴딩 (Vite + @crxjs/vite-plugin + TS, MV3 `manifest.json`, 폴더 구조)
- [x] `background/index.ts` — `ChromeMessage` 라우팅 스켈레톤 (`REQUEST_QUIZ`/`SEND_SCRAP`/`GET_AUTH_STATUS`)
- [x] `background/api.ts` — `sendQuizRequest` **T=3 완성**: Bearer 토큰 best-effort 첨부 + `VITE_MOCK_QUIZ` mock 모드 (`sendScrapRequest`는 Step 8/T=4에서 보강)
- [x] `background/mockQuiz.ts` (신규) — `buildMockQuizzes(body)`: 실제 문단에서 `anchorText`를 동적 추출해 canned `Quiz[]` 생성
- [x] `src/vite-env.d.ts` (신규) — `VITE_MOCK_QUIZ` env 타입 선언
- [x] `.env.example` (신규) — mock 모드 사용법 문서화
- [x] `popup/index.html`·`main.tsx`·`Popup.tsx` — placeholder
- [x] `npx tsc --noEmit`, `npx vite build` 통과 확인 (38 modules — A의 오케스트레이터가 전체 체인을 번들에 연결한 것 확인)
- [x] Stream A(`extractor.ts`/`anchor.ts`/`observer.ts`/`content/index.tsx` 오케스트레이터), Stream B(`session.ts`/`session-bind.ts`/`ui/*`)가 내 폴더 구조 위에 파일 추가한 것 확인 — 빌드 안 깨짐

---

## Align 체크리스트

### T=2 (A ↔ B align) — Stream C 해당 없음

Stream C는 T=2에 별도 산출물 없음. A의 `Paragraph` 실제 DOM 이벤트 훅 방식이 B로 전달되는 단계라 대기.

---

### T=3 (전체 align) — Stream A RFC(§T3) 검토 결과

> `stream_a_align.md §T3` 전체 검토함. **핵심 결정(T3.1~T3.3, T3.6 오케스트레이터 스케치)에 Stream C 이견 없음.** 아래는 근거 확인 + A가 C에 위임/요청한 항목에 대한 답변.

**✅ 이견 없음 — 근거 확인:**
- **T3.1** (`content/index.tsx` = Stream A 소유): C 파일 범위(`manifest.json`/`background/**`/`popup/**`)와 겹치지 않음. 동의.
- **T3.3** (REQUEST_QUIZ/SEND_SCRAP 라운드트립 = C 현행 코드와 일치): 실제 `background/index.ts` 재확인함 — `case 'REQUEST_QUIZ'`가 `sendQuizRequest().then(QUIZ_RESPONSE).catch(QUIZ_ERROR)` + `return true`(비동기 응답) 그대로. A 서술과 **정확히 일치**. 변경 불필요.
- **T3.6** (오케스트레이터 레퍼런스 스케치): `chrome.runtime.sendMessage({type:'REQUEST_QUIZ',...})` / `SEND_SCRAP` payload 형태가 `shared/types.ts`의 `ChromeMessage`와 일치. 이견 없음.

**A가 위임한 결정 → C 확정:**

1. **mock 모드 플래그·형태 (T3.4 확인 요청 응답)**
   - 플래그명: `import.meta.env.DEV` 대신 **`import.meta.env.VITE_MOCK_QUIZ`** 별도 플래그 채택. 이유: `DEV`에 묶으면 `npm run dev`할 때마다 강제로 mock만 타서, 실서버(localhost:8000) 붙여서 테스트하고 싶을 때도 못 씀. 별도 env로 두면 dev 중에도 mock/실서버 토글 가능.
   - fixture 형태: B의 `ui/mock.ts`(`MOCK_QUIZZES`)와 **shape(타입 구조)는 동일하게 따름** — 단, `anchorText`는 정적 하드코딩을 그대로 재사용하지 않고 **`sendQuizRequest`에 실제로 들어온 `body`(문단 `'\n\n'` join, A §2.2 규약)를 파싱해서 앞쪽 문단 텍스트를 anchorText로 동적 생성**할 예정. (아래 "참고" 항목 참조)
   - 구현은 T=3 작업으로 착수 예정 (아직 코드 미반영, 이 문서에 방침만 확정).

2. **토큰 미로그인 시 생략 정책 (T3.5 확인 요청 응답)**
   - **OK.** `chrome.storage.local`에 `STORAGE_KEYS.ACCESS_TOKEN`이 있으면 `Authorization: Bearer` 첨부, 없으면 헤더 자체를 생략(빈 토큰 전송 안 함). Step 9 로그인 전에도 mock/실서버 e2e 진행 가능하게 하는 목적에 동의.

**🟡 참고 사항 (이견 아님, 설계 메모):**
- B의 `content/ui/mock.ts`(`MOCK_QUIZZES`)는 `anchorText`가 정적 문자열(예: "한국은행은 기준금리를...")이라, **실제 데모 기사 본문에 그 문장이 없으면 anchor 매칭이 실패**(→ 전부 `unanchored`로 하단 강등)할 수 있음. B의 mock.ts는 Step 3 UI 단독 검증용이라 문제 없지만, **T=3 e2e(오케스트레이터 전체 체인) 검증 시에는 C의 mock 모드가 실제 로드된 기사의 `body`에서 anchorText를 뽑아 만드는 편이 안전**하다고 판단해서 위 1번처럼 결정함. A/B 이견 있으면 회신 바람.

**✅ 구현 완료 (T=3):**
- `background/api.ts`
  - `getAccessToken()` — `chrome.storage.local`에서 `STORAGE_KEYS.ACCESS_TOKEN` 조회, 없으면 `null`
  - `buildHeaders()` — 토큰 있으면 `Authorization: Bearer <token>`, 없으면 헤더 생략
  - `sendQuizRequest`: `VITE_MOCK_QUIZ === 'true'`면 `buildMockQuizzes(body)` 반환(fetch 안 함), 아니면 `buildHeaders()`로 실제 `POST /quiz` 호출
- `background/mockQuiz.ts` (신규)
  - `buildMockQuizzes(body)`: `body`를 `'\n\n'`으로 split(A §2.2 규약과 동일 경계) → 20%/60% 지점 문단을 골라 `anchorText`(앞 50자)·`paragraphIndex`를 실제 값으로 채운 `Quiz[]` 2건 생성 (1건은 2단계 재질문 포함 — followup UI까지 검증 가능)
  - 최소 문단 수(`MIN_ARTICLE_PARAGRAPHS=3`, A 게이트) 케이스에서도 두 인덱스가 겹치지 않게 clamp — 별도 스크립트로 로직 검증함
- `src/vite-env.d.ts`, `.env.example` — `VITE_MOCK_QUIZ` 사용법 문서화 (`.env.local`로 복사해서 켬, `*.local`은 이미 `.gitignore`됨)
- 검증: `npx tsc --noEmit` 통과, `npx vite build` 통과(38 modules — A의 오케스트레이터가 extractor/anchor/observer/session/ui까지 전부 번들에 연결한 것 확인)

**QA 남은 것 (T=5로 이월):**
- [ ] `VITE_MOCK_QUIZ=true`로 실제 브라우저(언팩 확장)에서 observer → session → ui → background 전체 체인 육안 확인 — 코드 레벨 검증은 끝났으나 브라우저 실측은 아직
- [ ] 실서버 붙었을 때 `sendQuizRequest`의 실제 fetch 경로(비-mock) 재검증

---

### T=4 (B ↔ C align) — Stream B RFC(§T4) 검토 결과 → **구현 완료**

> `stream_b_align.md §T4`(B 주재) 전체 검토함. `content/index.tsx`(A)의 `onEnd`가 이미 `flushResults()`→`SEND_SCRAP` 조립까지 배선해둔 것도 재확인.

**✅ 이견 없음 — 근거 확인:**
- **T4.1** (`ScrapRequest` 조립 주체 = 오케스트레이터 A, session/C 아님): `content/index.tsx`의 `onEnd` 콜백을 다시 보니 실제로 `extract.title`/`extract.body` + `useSession.getState().flushResults()`로 이미 조립해서 보내고 있음. B의 정정이 실제 코드와 일치. 내 이전 T=4 체크리스트("세션이 ExtractResult 들고 있다가 넘기는 구조로 추정")는 **틀린 추정이었음 — 정정 수용.**
- **T4.2** (`flushResults` = drain+clear, 부분배치 다중전송 허용, 빈 배치는 송신측 가드 + 수신측 방어): 동의. 구현 시 `sendScrapRequest`(또는 `background/index.ts`)에 `results.length === 0`이면 네트워크 호출 없이 즉시 성공 처리하는 가드 추가 예정.
- **T4.4** (재시도 큐 = C 소유, `buildHeaders()` 재사용, drain 시점 = 다음 성공 직후 + 서비스워커 시작 시, in-flight 플래그로 동시 drain 방지): 동의. 설계 그대로 구현 예정. (구현 시 서비스워커 startup 이벤트만으로는 깨어날 트리거가 없을 수 있어 `chrome.alarms`로 주기적 drain을 보강할지는 C 재량 — 이견 아님, 구현 디테일.)
- **T4.5** (content는 fire-and-forget, 재시도는 전적으로 background 책임): 동의.
- **T4.6** (scrap mock, `VITE_MOCK_SCRAP` 신설 여부는 C 재량): 채택 예정. `VITE_MOCK_QUIZ`와 동일 패턴으로 무서버 e2e에서 `/scrap`도 즉시 성공 처리.

**🟡 정정 수용 (이견 아님):** T4.3 — "전송 시점 처리는 C 소관"이라던 내 이전 T=4 체크리스트 항목은 **틀렸음, 정정 수용.** `flushResults()`가 content-script zustand 상태라 background가 능동적으로 호출할 수 없다는 B의 근거가 맞음(background는 content가 보낸 메시지만 수신 가능, tab close 감지는 되어도 그 시점 세션 상태를 직접 읽을 방법이 없음). **트리거(언제 보낼지) = A, 전송·재시도(어떻게 보낼지) = C**로 소유 분리하는 게 아키텍처상 맞음. 내 align 문서의 해당 항목 취소.

**🟡 참고/약한 우려 (블로킹 아님, 이견까진 아니고 메모):**
- `extension_implementation_plan.md §3.6`은 "beforeunload 신뢰도 낮아 **주기적 자동저장 + 종료 시 flush 병행**"을 명시적으로 요구했는데, B의 T4.3은 주기적 autosave를 "선택/이월 → Step 10 여력 시"로 미룸. B가 든 완화 근거("handoff만 되면 실제 fetch는 background가 이어감")는 `beforeunload`가 **발화는 되는** 경우엔 유효하지만, 탭이 비정상 종료되어 `beforeunload` 자체가 안 뜨는 경우(브라우저 크래시, 강제 종료 등)엔 여전히 데이터가 통째로 유실됨. 다만 이 트리거 구현은 A 영역이고 하카톤 시간 제약을 고려하면 Step 10로 미루는 것도 합리적인 판단이라 **차단하지는 않음** — A/B가 이대로 진행하면 따름. 기록만 남겨둠.
- T4.4의 "서버 저장 후 5xx 재전송 시 서버측 중복 가능 = MVP 허용"은 담당3(서버) 확인 필요 항목으로 아래 외부 협업 접점 표에 추가함.

**✅ 구현 완료 (T=4):**
- `background/api.ts`
  - `postScrap(payload)` — 순수 네트워크 1건 (`buildHeaders()` 재사용). 최초 전송·재시도 큐 drain 양쪽에서 공용
  - `sendScrapRequest(payload)`: `results.length === 0`이면 즉시 반환(no-op) → `VITE_MOCK_SCRAP==='true'`면 즉시 반환(무서버 e2e) → `postScrap` 성공 시 `drainRetryQueue()`도 같이 시도(T4.4-a) → 실패 시 throw 대신 **`RETRY_QUEUE`에 적재 후 정상 반환**(content가 fire-and-forget이라 에러를 던져도 무시되므로, "재시도 예약함"을 성공으로 간주 — T4.5 반영)
  - `drainRetryQueue()`: `RETRY_QUEUE`를 앞에서부터 순서대로 비움, 실패 지점에서 멈추고 그 뒤는 그대로 유지(순서 보존·유실 없음) — ~~`drainInFlight` 플래그로 재진입 방지~~ **T4.9에서 `withQueueLock` 뮤텍스로 교체(아래 참조)**
  - `getRetryQueue`/`setRetryQueue` — `chrome.storage.local[STORAGE_KEYS.RETRY_QUEUE]` 직렬화
- `background/index.ts` — 모듈 최상단에서 `void drainRetryQueue()` 호출 → 서비스워커가 (재)시작될 때마다(유휴 후 깨어남 포함) 1회 drain 시도(T4.4-b). `chrome.alarms`로 주기적 drain을 추가할지는 검토했으나 **MVP 범위 초과로 보류**(§T4.4에서 "구현 디테일, C 재량"이라 명시했던 부분 — 과설계 방지 차원에서 안 넣기로 결정)
- `src/vite-env.d.ts`, `.env.example` — `VITE_MOCK_SCRAP` 문서화 (`VITE_MOCK_QUIZ`와 동일 패턴)
- 검증: `drainRetryQueue`의 큐 순회 로직(전부 성공 / 중간 실패 시 순서 보존·해당 지점 이후만 잔존 / 빈 큐)을 별도 스크립트로 3케이스 확인. `npx tsc --noEmit`·`npx vite build`(38 modules) 통과.

**🔧 버그 수정 (T4.9, B 검증에서 발견한 엣지 결함 2건 대응) — 둘 다 수용, 수정 완료:**
- **finding #1 (read-modify-write 레이스, lost update) 수용·수정:** `sendScrapRequest`의 실패 처리와 `drainRetryQueue`가 각자 `getRetryQueue`→mutate→`setRetryQueue`를 독립적으로 하다 보니, 동시에 실행되면 나중에 쓰는 쪽이 앞선 쓰기를 덮어써서 배치가 통째로 유실될 수 있었음. **`drainInFlight` boolean을 버리고 `withQueueLock` 비동기 뮤텍스로 교체** — `enqueueRetry`(실패 시 큐 추가)와 `drainRetryQueue`(drain 전체)를 같은 락 체인에 태워, 큐에 손대는 연산이 절대 겹쳐 실행되지 않게 함. (부작용: drain 도중 들어온 enqueue는 drain이 끝날 때까지 대기 — 정확성을 위한 의도적 트레이드오프, MVP에서 지연은 무해.)
- **finding #2 (poison message로 큐 영구 정체) 수용·수정:** 큐 항목에 `attempts` 카운터 추가(`RetryEntry{ payload, attempts }`). head가 실패하면 attempts 증가 후, `MAX_RETRY_ATTEMPTS(=5)` 미만이면 기존처럼 그 자리에 두고 이번 drain을 멈추지만(순서 보존), **5회를 채우면 dead-letter로 버리고 다음 항목으로 계속 진행** — 한 번 망가진 요청(예: 서버가 400으로 영구 거부)이 뒤의 정상 요청들까지 막는 일이 없게 함.
- 검증: 두 시나리오를 별도 스크립트로 재현. (1) drain이 네트워크 대기 중(느린 성공)일 때 동시에 enqueue 발생 → 뮤텍스 적용 후 유실 없이 두 결과 모두 큐/스토리지에 정확히 반영됨 확인. (2) head가 계속 실패하는 3항목 큐를 `MAX_RETRY_ATTEMPTS+1`번 drain 반복 호출 → poison 항목은 드롭되고 뒤의 정상 항목 2건은 전부 처리되어 큐가 빔 확인. `npx tsc --noEmit`·`npx vite build` 재통과.
- `RetryEntry`는 `background/api.ts` 내부 저장 포맷일 뿐 `shared/types.ts`에 노출되는 타입이 아니라서 **다른 스트림에 영향 없음**(B의 T4.9 언급대로 타입 계약 변경 없음).

---

### T=5 (전체 QA) — Step 10: 앵커·진입 임계값 튜닝 + QA

> **Step 9(팝업 로그인)는 담당2의 `/auth/login` 요청/응답 스키마·401 규약 미확정으로 착수 못 함** (아래 외부 협업 접점 표 참조). `popup/Popup.tsx`·`background/index.ts`의 `GET_AUTH_STATUS`는 T=1 placeholder 그대로.
> → **A/B는 이 부분과 무관하게 지금 Step 10 착수 가능.** `VITE_MOCK_QUIZ`/`VITE_MOCK_SCRAP`가 인증 여부와 관계없이 전체 체인을 이미 돌리므로, 앵커 임계값·observer rootMargin 튜닝 + quiz→scrap end-to-end 데모 기사 검증은 Step 9를 기다릴 필요 없음. **Step 10 중 "팝업 로그인→401" 한 조각만 Step 9 완료 후로 순연.**

Stream C 역할:
- [ ] `/quiz`, `/scrap` 실서버(or mock) 대상 end-to-end 확인 — **지금 가능**(mock 모드로)
- [ ] 팝업 로그인 → 401 재로그인 유도 플로우 확인 — **Step 9 완료 후에만 가능(현재 블로킹)**
- [ ] 데모 기사 3~5개로 전체 플로우(A/B 포함) 통과 확인 — **지금 가능**

---

## 외부 협업 접점 (서버팀)

| 대상 | 필요한 것 | 상태 |
|------|-----------|------|
| 담당2 (인증) | `POST /auth/login` 요청(`client: "extension"`)·응답 스키마, 401 처리 규약 | 미확인 — Step 9 착수 전 확정 필요 |
| 담당3 (서버 도메인) | `/quiz`·`/scrap` 실제 응답이 `shared/types.ts`와 일치하는지, `anchorText` 포함 여부 | 미확인 — mock 서버 or 실서버로 검증 필요 |
| 담당3 (서버 도메인) | `/scrap` 재시도로 인한 중복 제출 시 서버가 개념 단위로 merge하는지 (5xx 후 재전송 시 실제로는 저장 성공했을 수 있음, B `stream_b_align.md §T4.4`에서 제기) | 미확인 — MVP는 클라이언트 dedup 없이 진행하기로 잠정 합의(B) |

---

## 업데이트 로그

- **T=1** (2026-07-21): 스캐폴딩 완료. `tsc --noEmit`/`vite build` 통과. Stream A/B 파일 추가 확인, 충돌 없음.
- **T=3** (2026-07-21): `stream_a_align.md §T3`(전체 align RFC) 검토. 핵심 결정(T3.1~T3.3, T3.6)에 **이견 없음**, `background/index.ts` 실제 코드와 A 서술 일치 재확인. A가 위임한 2건 확정: ① mock 플래그 = `VITE_MOCK_QUIZ`(DEV와 분리), ② 토큰 미로그인 시 헤더 생략 OK.
- **T=3** (2026-07-21, 완료): Step 7 `/quiz` 연동 구현 완료. `sendQuizRequest`에 Bearer 토큰 best-effort 첨부(`getAccessToken`/`buildHeaders`), `mockQuiz.ts` 신설(`buildMockQuizzes` — 실제 body 문단에서 anchorText 동적 생성), `vite-env.d.ts`/`.env.example`로 `VITE_MOCK_QUIZ` 문서화. A가 `content/index.tsx` 오케스트레이터를 완성해 `sendQuizRequest`를 실제로 호출하는 구조 확인. `tsc --noEmit`·`vite build`(38 modules) 통과. 남은 건 T=5 브라우저 실측 QA.
- **T=4** (2026-07-21, 리뷰): `stream_b_align.md §T4`(B 주재 RFC) 검토. T4.1/T4.2/T4.4/T4.5/T4.6 이견 없음. T4.3에서 내 이전 체크리스트("전송 시점 처리는 C 소관")가 틀렸음을 확인 — B의 정정(트리거=content/A, 전송·재시도=background/C 소유 분리) 수용. 약한 우려 1건 메모(주기적 autosave를 Step 10으로 미루는 것 — beforeunload 미발화 시 유실 가능성, 블로킹 아님). 담당3 확인 필요 항목(재시도 중복 merge) 외부 협업 표에 추가.
- **T=4** (2026-07-21, 완료): Step 8 `/scrap` 구현 완료. `postScrap`(공용 네트워크 1건) + `sendScrapRequest`(빈 배치 방어·mock·실패 시 큐 적재) + `drainRetryQueue`(순서 보존 drain, in-flight 가드) + `background/index.ts`에서 서비스워커 시작 시 drain 호출. `VITE_MOCK_SCRAP` 추가. drain 로직 3케이스(전부 성공/중간 실패/빈 큐) 스크립트로 검증, `tsc --noEmit`·`vite build`(38 modules) 통과. Stream C의 Step 7·8 모두 완료 — 남은 건 Step 9(팝업 로그인)와 T=5 QA.
- **T=5 착수 전** (2026-07-21): Step 9는 담당2의 `/auth/login` 스키마 미확정으로 여전히 blocked(placeholder 그대로). A/B에게 통지: Step 10(전체 QA) 중 앵커/observer 튜닝 + mock 기반 quiz→scrap e2e는 Step 9와 무관하게 지금 시작 가능, "팝업 로그인→401" 검증만 Step 9 완료 후로 순연됨을 `stream_c_align.md`에 명시.
- **T=4.9 버그 수정** (2026-07-21): B가 재시도 큐 실제 구현을 검증하다 발견한 엣지 결함 2건(`stream_b_align.md §T4.9`) 둘 다 재현·수용해서 수정. ① enqueue↔drain read-modify-write 레이스(lost update) → `drainInFlight` boolean을 `withQueueLock` 비동기 뮤텍스로 교체, 큐를 건드리는 모든 연산을 단일 체인으로 직렬화. ② poison message가 큐를 영구 정체시키는 문제 → `RetryEntry{payload, attempts}`로 항목별 시도 횟수 추적, `MAX_RETRY_ATTEMPTS(5)` 도달 시 dead-letter로 버리고 다음 항목 계속 진행. 두 시나리오(느린 성공 중 동시 enqueue / 계속 실패하는 head가 5회 후 드롭) 별도 스크립트로 재현·검증, `tsc --noEmit`·`vite build` 재통과.
