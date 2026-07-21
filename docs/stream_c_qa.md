# Prober 확장 — Stream C QA & 핸드오프 문서 (T=5 / Step 10)

> **작성: Stream C (Infrastructure).** T=5(전체 QA) 단계에서 수행한 `background/api.ts`(`/quiz`·`/scrap`) 검증 결과와,
> **후속 개발자(서버 연동·Step 9 담당)가 이어서 알아야 할 것들**을 모아둔 핸드오프 문서입니다.
> 관련: [stream_c_align.md](./stream_c_align.md)(C 설계·결정) · [stream_a_qa.md](./stream_a_qa.md)(A QA) · [stream_b_align.md](./stream_b_align.md) · [shared_contract.md](./shared_contract.md)
> 최종 업데이트: 2026-07-21

---

## 0. 지금까지 완성도 (Stream C 담당 영역)

| 영역 | 상태 |
|------|------|
| 스캐폴딩(Vite+crxjs+TS, `manifest.json`) | ✅ Step 1 |
| `POST /quiz` 연동 (`sendQuizRequest`) | ✅ Bearer best-effort + `VITE_MOCK_QUIZ` mock |
| `POST /scrap` 연동 (`sendScrapRequest`/`drainRetryQueue`) | ✅ Bearer best-effort + 재시도 큐 + `VITE_MOCK_SCRAP` mock |
| 재시도 큐 엣지 결함 수정 (B `stream_b_align.md §T4.9` 발견분) | ✅ 레이스(뮤텍스)·poison message(재시도 상한) 둘 다 수정 |
| 팝업 로그인 (Step 9, `/auth`) | 🔲 **placeholder만** — 담당2가 `/auth/login` 스키마 확정해야 착수 가능 |

`npx tsc --noEmit`·`npx vite build` 전체 통과. 실 브라우저 Network 탭 확인은 A의 `stream_a_qa.md §4` 체크리스트("스크랩 전송" 항목)에 포함되어 있어 중복 작성 안 함 — 사람이 브라우저로 확인해야 하는 부분.

---

## 1. QA 하니스 — `npm run qa:scrap`

A의 `qa:anchor`와 같은 패턴: 재구현이 아니라 **실제 `background/api.ts`·`background/mockQuiz.ts` 코드를 그대로 import**해서 `chrome.storage.local`·`fetch`만 스텁으로 갈아끼워 검증한다.

```bash
cd extension
npm run qa:scrap      # rolldown으로 번들 → node 실행
```

하니스: `extension/qa/scrap-qa.ts`. `drainRetryQueue`(export)를 직접 호출해 재시도 큐 로직 전체를, `buildMockQuizzes`(export)를 직접 호출해 mock 퀴즈 생성 로직을 검증한다.

> `sendQuizRequest`/`sendScrapRequest` 최상단의 `import.meta.env.VITE_MOCK_QUIZ`/`VITE_MOCK_SCRAP` 체크 그 자체는 대상에서 제외했다 — 플레인 node 실행 환경엔 `import.meta.env`가 없어 별도 번들 설정(Vite define 상당) 없이는 그 줄에서 즉시 throw한다. 단순 문자열 비교 1줄이라 리스크가 낮고, 그 아래 실제 네트워크·재시도 로직은 `drainRetryQueue`가 `postScrap`을 그대로 재사용하므로 전부 커버된다.

### 결과 — 17/17 통과

| 그룹 | 검증 내용 |
|------|-----------|
| [1] 전부 성공 | FIFO 순서(a→b→c)대로 전송, 큐 완전 소진 |
| [2] 중간(b) 실패 | a만 제거, b는 `attempts=1`로 남고 c는 순서 보존(시도조차 안 됨) |
| [3] poison message | 영구 실패 항목을 6회 drain 트리거 후 드롭 확인, 뒤에 있던 b·c는 정상 처리되어 큐가 빔 |
| [4] 동시 drain | 두 `drainRetryQueue()`를 동시 실행해도 유실·중복 없이 a·b 각 1회씩만 전송(뮤텍스 검증) |
| [5] Bearer 토큰 | 토큰 없으면 헤더 생략, 있으면 `Authorization: Bearer <token>` 첨부 |
| [6] mock 퀴즈 | 실제 5문단 body에서 anchorText가 해당 문단 텍스트로 시작함, 인덱스 서로 다름, 2단계 followup 트리 포함, 최소 3문단 케이스도 인덱스 안 겹침 |

그룹 [3]·[4]는 B가 `stream_b_align.md §T4.9`에서 발견한 두 엣지 결함(재시도 상한 없음 → poison message가 큐 영구 정체 / read-modify-write 레이스 → lost update)의 수정을 **실제 코드로 재검증**한 것.

---

## 2. 튜닝 노브 (Stream C 영역)

| 상수 | 위치 | 효과 | 기본값 |
|------|------|------|--------|
| `MAX_RETRY_ATTEMPTS` | `background/api.ts` (내부) | 재시도 큐에서 이 횟수만큼 연속 실패하면 dead-letter로 버림 | `5` |
| `VITE_MOCK_QUIZ` | `.env.local` | `true`면 `/quiz` 실 fetch 대신 canned Quiz[] | 미설정(꺼짐) |
| `VITE_MOCK_SCRAP` | `.env.local` | `true`면 `/scrap` 실 fetch 없이 즉시 성공 | 미설정(꺼짐) |

---

## 3. Step 9 (인증) 핸드오프 — A의 §5와 동일 seam, C 관점 보강

> A의 `stream_a_qa.md §5`에 이미 핸드오프 표가 있음(위치별 현재 상태·할 일). 여기서는 C가 실제로 뭘 준비해뒀는지만 보강.

- `background/api.ts`의 `buildHeaders()`가 **이미 모든 서버 호출에 재사용되도록** 배선되어 있음(`sendQuizRequest`·`postScrap` 둘 다 경유). Step 9에서 로그인이 성공해 `chrome.storage.local[STORAGE_KEYS.ACCESS_TOKEN]`에 토큰만 쓰면, **`api.ts` 쪽은 추가 수정 없이 자동으로 Bearer가 첨부됨.**
- `background/index.ts`의 `GET_AUTH_STATUS` 핸들러만 실제 토큰 존재 여부를 읽어 `AUTH_STATUS`를 반환하도록 바꾸면 됨(현재 `loggedIn:false` 고정).
- 401 처리(재로그인 유도)는 아직 어디에도 없음 — `sendQuizRequest`/`postScrap`이 `res.ok`만 보고 throw하므로, 401을 구분해 팝업에 알리는 로직이 Step 9에서 추가로 필요함(현재는 401도 그냥 일반 실패로 처리되어 `/scrap`은 재시도 큐로, `/quiz`는 그냥 실패로 감).

---

## 4. 알려진 한계 / MVP 범위 밖

- **poison message dead-letter는 조용히 버려짐** — 사용자·개발자에게 알림 없이 5회 실패 후 사라짐. 데모 스코프에서는 문제 없으나, 실서비스라면 로깅/모니터링이 필요.
- **`chrome.alarms` 미도입** — 재시도 큐 drain은 "성공 직후" + "서비스워커 시작 시"에만 일어남. 서비스워커가 오래 깨어나지 않으면(탭이 오래 열려있고 별다른 메시지가 없으면) 그동안 재시도가 안 일어날 수 있음. 필요해지면 주기적 알람으로 보강 가능(§T4.4에서 C 재량으로 명시됐던 부분, MVP 범위 초과로 보류함).
- **서버 실측 미완**: `/quiz`·`/scrap` 실제 응답이 `shared/types.ts`와 정확히 일치하는지는 mock으로 우회했을 뿐 실서버로 검증 안 됨(담당3 확인 필요, `stream_c_align.md` 외부 협업 접점 표 참고).
- **Step 9는 전면 미착수** — 담당2의 `/auth/login` 스키마 확정이 선행 조건.

---

## 5. 한 장 요약

- **`npm run qa:scrap` 17/17 통과** — 실제 코드(재구현 아님)로 재시도 큐(FIFO·중간실패·poison·동시성)와 Bearer best-effort, mock 퀴즈 anchorText 파생을 검증.
- **T4.9 버그 수정 2건(레이스·poison message) 모두 실제 코드 기준 재확인 완료.**
- **Step 9는 자리만 뚫려있고 착수 불가** — 담당2 `/auth` 스키마 대기. 토큰만 저장되면 나머지(Bearer 첨부)는 이미 자동 배선됨.
- **401 처리는 아직 없음** — Step 9에서 추가 필요.
