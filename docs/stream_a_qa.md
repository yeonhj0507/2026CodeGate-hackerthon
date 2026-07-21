# Prober 확장 — QA & 핸드오프 문서 (T=5 / Step 10)

> **작성: Stream A (Content Pipeline).** T=5(전체 QA) 단계에서 수행한 앵커 튜닝·검증 결과와,
> **후속 개발자(로컬 앱/서버 연동 담당)가 이어서 알아야 할 것들**을 모아둔 핸드오프 문서입니다.
> 관련: [stream_a_align.md](./stream_a_align.md)(A 설계·결정) · [stream_b_align.md](./stream_b_align.md) · [stream_c_align.md](./stream_c_align.md) · [system_overview.md](./system_overview.md)
> 최종 업데이트: 2026-07-21

---

## 0. 지금까지 완성도 (익스텐션)

| 영역 | 상태 | 담당 |
|------|------|------|
| 본문 추출·문단 인덱싱 (`extractor.ts`) | ✅ | A |
| 앵커 매칭 (`anchor.ts`) ⚠️최대리스크 | ✅ + **QA 튜닝 완료(본 문서 §2)** | A |
| 문단 진입 감지 (`observer.ts`) | ✅ (rootMargin은 브라우저 QA 필요, §4) | A |
| 오케스트레이터 (`content/index.tsx`) | ✅ end-to-end 배선, tsc 통과 | A |
| 세션 상태머신·UI (`session.ts`, `ui/**`) | ✅ | B |
| 제출 큐 (`session-bind.ts`) | ✅ 단위테스트 통과 | B |
| background 메시징·`/quiz`·`/scrap` | ✅ (Bearer 토큰·재시도·mock는 진행) | C |
| 팝업 로그인 (Step 9 `/auth`) | 🔲 **placeholder만** — 서버팀이 `/auth` 완성 후 연결 (§5) | C+서버팀 |

`npx tsc --noEmit` 전체 통과. 실 브라우저 end-to-end 실측은 §4 체크리스트 참고(사람 확인 필요).

---

## 2. 앵커 매칭 QA & 튜닝 결과 ⭐

앵커 매칭은 "서버가 준 `anchorText`/`paragraphIndex`를 실제 문단에 연결"하는 최대 리스크 로직.
실패하면 퀴즈가 엉뚱한 문단에 뜬다. 실제 `anchor.ts`를 그대로 불러와 자동 QA 하니스로 검증했다.

### 실행 방법 (재현 가능)

```bash
cd extension
npm run qa:anchor      # rolldown으로 anchor.ts 번들 → node 실행
```

하니스: `extension/qa/anchor-qa.ts` (실제 `anchorQuizzes`·`diceCoefficient` import, DOM 불필요).

### 결과 — 16/16 통과

한국어 기사 2편(경제·과학) × 8개 시나리오. 서버가 낼 법한 케이스를 모사:

| 시나리오 | 기대 | 실제 method | 판정 |
|----------|------|-------------|------|
| 정확(앞 50자 그대로) | 해당 문단 | `partial` (score 1.0) | ✓ |
| 공백 변형(다중공백·개행) | 해당 문단 | `partial`/`exact` | ✓ (normalizeText 견고) |
| 편집 드리프트(군데군데 글자 훼손) | 해당 문단 | `similarity` (score 0.84) | ✓ |
| paragraphIndex 틀림 + text 정상 | text 기준 문단 | `partial` | ✓ (text 우선) |
| text 쓰레기 + index 정상 | index 문단 | `index` (0.5) | ✓ (폴백) |
| 완전 실패(text·index 둘 다 무효) | 하단 강등 | `none` | ✓ (unanchored) |
| 짧은 anchor(앞 15자) | 해당 문단 | `partial` | ✓ |

method 분포: `exact 1 · partial 9 · similarity 2 · index 2 · none 2`.
→ **정상 케이스는 대부분 `partial`(포함 매칭, score 1.0)** 이 지배. `anchorText`가 문단 앞부분이고
본문을 문단순서대로 `'\n\n'`으로 이어 서버에 보내므로(=`Paragraph.idx`와 `paragraphIndex` 정렬), 1순위 매칭이 잘 걸린다.

### 임계값 튜닝 결정 — `ANCHOR_SIMILARITY_THRESHOLD = 0.55` 유지

민감도 분석(하니스 자동 출력):

| 지표 | 값 |
|------|-----|
| 서로 다른 문단 간 최고 유사도(오탐 위험) | **0.271** |
| 편집 드리프트 매칭 최저치 | **~0.84** |
| 현재 임계값 | 0.55 |
| 안전 마진 | 0.569 |

**0.271 < 0.55 < 0.84** — 오탐(다른 문단)과 정탐(드리프트) 사이 간극이 커서 0.55는 견고.
대략 0.35~0.75 어디든 동작하나 중앙값 0.55 유지가 안전. **변경 불필요.**

---

## 3. 튜닝 노브 (어디를 만지면 뭐가 바뀌나)

| 상수 | 위치 | 효과 | 기본값 |
|------|------|------|--------|
| `MIN_ARTICLE_PARAGRAPHS` | `content/index.tsx` (로컬) | 이보다 문단 적으면 퀴즈 안 뜸(비기사 게이트). 낮추면 완화 | `3` (미만 차단) |
| `ANCHOR_SIMILARITY_THRESHOLD` | `shared/constants.ts` | 유사도 폴백 채택 하한. 높이면 엄격(미매칭↑), 낮추면 오탐↑ | `0.55` |
| `ANCHOR_COMPARE_LENGTH` | `shared/constants.ts` | anchor·문단 비교 시 앞 몇 자 볼지 | `80` |
| `OBSERVER_OPTIONS.rootMargin` | `shared/constants.ts` | 문단이 화면 어디에 오면 "진입"으로 볼지. ⚠️ **브라우저 QA로 튜닝(§4)** | `'-40% 0px -60% 0px'` |
| `MIN_PARAGRAPH_LEN` / `NOISE_PATTERN` / `isWhitelisted` | `content/extractor.ts` (내부) | 본문/광고·댓글 판별 정책. 비기사 처리하려면 여기 완화 | — |

> 비기사에서도 퀴즈를 띄우거나 문단 제한을 푸는 유지보수 방법은 위 노브 참고. 특히 비기사는
> `extractArticle()`이 `null`을 반환하는 지점(`isWhitelisted` 필터)이 핵심 차단막이다.

---

## 4. 브라우저 수동 QA 체크리스트 (헤드리스로 못 하는 것)

DOM·IntersectionObserver·실제 스크롤이 필요한 부분은 사람이 브라우저에서 확인해야 한다.

### 준비

```bash
cd extension
# mock 모드로 서버 없이 확인 (C가 VITE_MOCK_QUIZ 구현)
VITE_MOCK_QUIZ=1 npm run build     # 또는 npm run dev (crxjs HMR)
# Chrome → chrome://extensions → 개발자 모드 → "압축해제된 확장 프로그램 로드" → dist/
```

### 체크리스트

- [ ] **본문 추출**: 실제 뉴스 기사 3~5개에서 본문 문단이 인식되고 광고·댓글·추천이 제외되는가 (`data-prober-idx` DOM에 부여되는지 devtools로 확인)
- [ ] **비기사 게이트**: 검색결과·SNS·대시보드 등에서 패널이 뜨지 않는가 (문단 <3 또는 비기사)
- [ ] **앵커 배치**: 각 퀴즈가 **의도한 문단 위치**에서 트리거되는가 (엉뚱한 문단 아님)
- [ ] **진입 타이밍(rootMargin 튜닝)**: 문단이 화면 중앙쯤 왔을 때 퀴즈가 뜨는가. 너무 이르거나 늦으면 `OBSERVER_OPTIONS.rootMargin` 조정
- [ ] **진단 루프**: 정답 → 초록 피드백 → 다음 대기 / 오답 → 빨강 + 설명 → 재질문 1단계 → 2단계 → IDLE
- [ ] **큐(유실 방지)**: 한 문단 풀이 중 아래로 스크롤해 다른 문단 진입 → 현재 문항 끝난 뒤 **순차 제시**(유실 없음)
- [ ] **하단 강등(unanchored)**: 매칭 실패 퀴즈가 마지막 문단 도달 시 패널로 노출되는가
- [ ] **종료(onEnd 회귀)**: "학습 종료" 후 **새 문항이 더 뜨지 않는가** (dispose/disconnect 확인) + ended 상태 표시
- [ ] **스크랩 전송**: 종료 시 Network 탭에서 `POST /scrap` payload가 `{articleTitle, articleBody, results[]}` 형태이고 `results[].parentConcept`가 채워지는가

---

## 5. Step 9 (인증) 핸드오프 — `/auth` 붙이는 자리

> Step 9는 **서버팀이 `/auth`를 완성해 넘기면 연결**. 현재는 **placeholder만** 있음. 아래가 이미 뚫려있는 seam이다.

| 위치 | 현재 상태 | Step 9에서 할 일 |
|------|-----------|------------------|
| `popup/Popup.tsx` | placeholder("TODO Step 9") | 로그인 폼 + 진행률 표시 |
| `background/index.ts` `GET_AUTH_STATUS` | `{loggedIn:false}` 고정 반환 | `chrome.storage.local`의 토큰 조회해 실제 상태 반환 |
| `background/api.ts` | 토큰 미첨부(TODO) | `/quiz`·`/scrap`에 `Authorization: Bearer <token>` 첨부 |
| `shared/constants.ts` | `ENDPOINTS.LOGIN/ME/LOGOUT`, `STORAGE_KEYS.ACCESS_TOKEN` 정의됨 | 그대로 사용 |
| `shared/types.ts` | `ChromeMessage`에 `GET_AUTH_STATUS`/`AUTH_STATUS` 정의됨 | 그대로 사용 |

**로그인 계약(명세):**
- `POST /auth/login` 요청에 `client: "extension"` 포함 → 토큰 수신
- 토큰은 **background가** `chrome.storage.local[STORAGE_KEYS.ACCESS_TOKEN]`에 저장 (content script는 접근 안 함)
- 모든 서버 호출에 `Authorization: Bearer` 첨부. **401 응답 시 팝업으로 재로그인 유도**
- 익스텐션·로컬 앱은 **독립 로그인**(동일 계정, 별도 세션)

> **T=3 QA 임시조치:** 로그인 전에도 e2e가 되도록, 토큰이 없으면 헤더를 **생략**(best-effort 첨부)하기로 함(C 결정). Step 9 붙은 뒤엔 401 플로우로 대체.

---

## 6. 알려진 한계 / MVP 범위 밖 (다음 사람이 알 것)

- **SPA 재이동 재추출 미배선**: `observer.reset()`/`rearm()`·`extractArticle` 재실행 훅은 있으나 오케스트레이터가 SPA 라우팅 변화에 재부팅하진 않음. 정적 기사 기준 MVP. (`content/index.tsx` teardown 주석 참고)
- **unanchored flush 트리거**: "마지막 문단 진입 1회"에 의존. 독자가 끝까지 안 내려오면 강등 퀴즈 미제시(허용된 MVP 손실). 개선안: 스크롤 N% 트리거.
- **큐 상한 없음**: 안 풀고 계속 스크롤하면 대기 퀴즈가 쌓임. MVP 무제한. 필요 시 `session-bind.ts`에 상한/만료 추가.
- **스크랩 재전송 시점**: 현재 "학습 종료" 버튼만. 탭 닫힘/`beforeunload`/주기적 자동저장·재시도 큐는 C의 Step 8 잔여.
- **서버 응답 실측 미완**: `anchorText`가 **실제 문단 앞 40~60자**로 채워져 와야 앵커 1순위가 작동. 서버팀(담당3)과 `/quiz` 실응답 스키마 대조 필요(mock은 body를 `'\n\n'` split해 동적 생성하므로 OK).

---

## 7. 한 장 요약

- **앵커 QA 통과(16/16), 임계값 0.55 유지 확정** — `npm run qa:anchor`로 재현.
- **튜닝 노브**: 문단 게이트=`MIN_ARTICLE_PARAGRAPHS`, 유사도=`ANCHOR_SIMILARITY_THRESHOLD`, 진입=`OBSERVER_OPTIONS.rootMargin`(브라우저 튜닝).
- **브라우저 e2e는 사람 확인 필요**(§4) — 특히 rootMargin 진입 타이밍.
- **Step 9 auth는 seam만 뚫려있음**(§5) — 서버팀 `/auth` 완성 후 background 토큰 저장 + Bearer 첨부 + 401 재로그인만 채우면 됨.
