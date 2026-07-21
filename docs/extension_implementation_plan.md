# 프로버(Prober) — 크롬 익스텐션 구현 계획서

> 근거 문서: Google Drive `코드게이트 해커톤 준비` > `[READ THIS] 제품 specification` > `익스텐션` 탭
> 담당자: 정은택
> 최종 업데이트: 2026-07-21

---

## 0. 담당 범위

기사 화면 위에서 동작하는 **크롬 익스텐션 전부**.

흐름: 본문 인식 → 서버에 퀴즈 요청 → 문단 진입 감지 시 퀴즈 표시 → 채점 → 오답 시 재질문(최대 2단계) → 세션 종료 시 스크랩 전송

**서버 접점은 두 엔드포인트뿐:**
- `POST /quiz` — 퀴즈 트리 요청/수신
- `POST /scrap` — 진단 결과 전송

지식그래프·로컬 앱과는 **무관** (익스텐션은 그래프 원본을 보유·수정하지 않음, 명세 §3.5)

---

## 1. 기술 스택

| 항목 | 값 | 비고 |
|------|-----|------|
| 매니페스트 | Manifest V3 | 기획서 명시 |
| 언어 | TypeScript | |
| 번들러 | Vite + @crxjs/vite-plugin | HMR 지원, MV3 빌드 편의 |
| in-page UI | React + Shadow DOM | 기사 페이지 CSS 격리 |
| 본문 추출 | @mozilla/readability | 본문/광고 분리 |
| 상태관리 | zustand (경량) | 세션 상태 |
| 통신 | fetch + JWT Bearer | 담당2(인증) 규약 준수 |

**퀴즈 형식 (확정): 객관식(MCQ)**
- 클라이언트에서 정답 인덱스로 즉시 채점
- 런타임 LLM 추가 호출 없음

---

## 2. 폴더 구조

```
extension/
├── manifest.json
├── src/
│   ├── background/
│   │   └── api.ts            # 서버 호출(quiz/scrap), 토큰 보관/첨부
│   ├── content/
│   │   ├── extractor.ts      # 본문 인식·문단 인덱싱
│   │   ├── anchor.ts         # 퀴즈 문단 앵커 매칭
│   │   ├── observer.ts       # 문단 진입 감지(IntersectionObserver)
│   │   ├── session.ts        # 진단 루프 상태머신
│   │   └── ui/               # React in-page 위젯 (Shadow DOM)
│   ├── popup/                # 로그인·상태 표시
│   └── shared/               # 타입 정의(퀴즈 트리, 스크랩), 상수
```

**역할 분담 (런타임):**
- `content script`: DOM 접근이 필요한 모든 것 (본문 추출, 앵커, 진입 감지, 위젯 렌더)
- `background (service worker)`: 네트워크 호출 + 토큰 저장(`chrome.storage.local`). content script는 `chrome.runtime.sendMessage`로 background에 요청

---

## 3. 상세 구현

### 3.1 본문 추출 + 문단 인덱싱 (`extractor.ts`)

1. 페이지 로드 완료 후 `document.cloneNode(true)`를 Readability에 투입 → 본문 HTML/텍스트 획득
2. 추출된 텍스트로 원본 DOM의 실제 문단 노드를 재탐색
3. 문단 순회 → `paragraphs: { idx, text, el }[]` 배열 생성
4. 각 문단에 `data-prober-idx` 부여 (앵커 매칭·진입 감지 기준점)
5. 광고·추천·댓글 영역 제외

**폴백 순서 (Readability 실패 시):**
`<article>` → `<main>` → 최대 텍스트 밀도 컨테이너

**출력:** 기사 제목, 본문 원문(문단 배열), 문단별 텍스트

---

### 3.2 퀴즈 요청/수신 (`background/api.ts`)

- content → background: `{ type: 'REQUEST_QUIZ', title, body }` 메시지 전송
- background: `POST /quiz` (Bearer 토큰) → 퀴즈 트리 수신 → content로 반환
- 수신 즉시 content가 `anchor.ts`로 각 퀴즈의 `paragraphAnchor`를 실제 문단에 매칭

---

### 3.3 앵커 매칭 (`anchor.ts`) — ⚠️ 최대 구현 리스크

서버(Claude)가 반환한 퀴즈의 문단 지정 정보를 실제 DOM 문단에 연결하는 작업.

> **앵커란?** 서버가 퀴즈를 만들 때 "이 퀴즈는 N번째 문단에 해당"이라고 알려주는 표식.
> `anchorText`(문단 앞 40~60자)와 `paragraphIndex`(번호) 두 가지로 구성됨.
> 서버는 Claude에게 문단 번호를 붙인 원문을 전달하므로 Claude가 이를 반환 가능.

**매칭 우선순위:**
1. `anchorText`와 문단 텍스트 정규화 후 **정확 일치/부분 일치** (가장 신뢰)
2. 문자열 유사도 (Dice coefficient / trigram) 최고 문단 선택
3. `paragraphIndex`로 번호 직접 접근 (LLM이 틀릴 수 있으나 보조 수단)
4. 완전 실패 시: 해당 퀴즈를 **기사 하단 일괄 노출**로 강등 (UX 보전)

> 담당3(서버)와 계약: 퀴즈 응답에 `anchorText`(40~60자) + `paragraphIndex` 모두 포함

---

### 3.4 문단 진입 감지 (`observer.ts`)

- `IntersectionObserver`로 `data-prober-idx` 문단 관찰
- **문단 상단이 뷰포트 60% 지점을 통과**할 때 진입으로 판정 (threshold·rootMargin 튜닝 대상)
- 문단당 **1회만 트리거** (중복 방지 플래그)
- 진입 순서와 무관하게 각 문단 독립 처리 (사용자가 아래로 점프해도 동작)

---

### 3.5 진단 루프 상태머신 (`session.ts`)

```
IDLE
  → (문단 진입) → ASK(main)
  → (답 제출)   → GRADE
                  정답 → MARK_UNDERSTOOD → IDLE (다음 문단 대기)
                  오답 → SHOW_EXPLANATION + MARK_MISUNDERSTOOD
                          → (followup 있고 level < 2) → ASK(followup[level+1])
                          → (없거나 2단계 소진)       → IDLE
```

**규칙:**
- 설명(`explanation`)은 답 제출 전 항상 숨김
- 재질문 분기는 이미 수신한 퀴즈 트리 내부에서 처리 (추가 서버 호출 없음)

**세션 버퍼 `results[]` 누적 구조:**
```ts
{
  conceptTag: string,      // 해당 개념명
  parentConcept: string | null,  // main이면 null, 재질문이면 부모 개념명
  level: number,           // 0=main, 1=1단계 재질문, 2=2단계 재질문
  correct: boolean
}
```
`parentConcept`를 포함하는 이유: 서버가 스크랩을 받아 선행→후행 엣지를 복원할 수 있게 하기 위함

---

### 3.6 스크랩 전송 (`background/api.ts`)

**전송 시점:** 탭 닫힘 / 기사 이탈 / "학습 종료" 버튼 중 먼저 오는 것
(`beforeunload` 신뢰도 낮아 주기적 자동저장 + 종료 시 flush 병행)

**페이로드:**
```json
{
  "articleTitle": "...",
  "articleBody": "...",
  "results": [
    { "conceptTag": "기준금리", "parentConcept": null, "level": 0, "correct": true },
    { "conceptTag": "통화정책", "parentConcept": "기준금리", "level": 1, "correct": false }
  ]
}
```

**실패 처리:** `chrome.storage.local` 재시도 큐에 보관 → 다음 기회에 재전송

---

### 3.7 팝업 (`popup/`)

- 로그인 폼 (`POST /auth/login` with `client: "extension"`)
- 토큰은 background가 `chrome.storage.local`에 보관, 팝업은 상태만 조회
- 현재 기사 진단 진행률 표시
- 401 응답 시 재로그인 유도

---

## 4. 서버와의 데이터 계약 (담당3와 합의 필요)

### `POST /quiz` 요청
```json
{ "articleTitle": "string", "articleBody": "string" }
```

### `POST /quiz` 응답 (퀴즈 트리)
```json
{
  "quiz": [
    {
      "claimId": "c1",
      "conceptTag": "기준금리",
      "anchorText": "한국은행은 기준금리를 0.25%포인트 인상했",
      "paragraphIndex": 3,
      "question": "금리 인상이 환율에 미치는 직접적 영향은?",
      "options": ["A안", "B안", "C안", "D안"],
      "answerIndex": 2,
      "explanation": "...",
      "followups": [
        {
          "level": 1,
          "prereqConceptTag": "통화정책",
          "question": "...",
          "options": ["A", "B", "C", "D"],
          "answerIndex": 1,
          "explanation": "...",
          "followups": [
            { "level": 2, "prereqConceptTag": "...", "question": "...", "options": [...], "answerIndex": 0, "explanation": "..." }
          ]
        }
      ]
    }
  ]
}
```

### `POST /scrap` 요청
위 3.6 페이로드 참조. `results[].parentConcept` 포함 필수 (서버 엣지 복원용)

---

## 5. 인증 연동 (담당2 규약)

- 로그인 시 `client: "extension"` 필드 포함
- 토큰: background가 `chrome.storage.local`에 보관, 모든 서버 호출에 `Authorization: Bearer` 첨부
- 익스텐션은 로컬 앱과 **독립 로그인** (동일 계정, 별도 세션)
- 401 시 팝업으로 재로그인 유도

---

## 6. 개발 Step (Day 기준)

### Day 1 오전

**Step 1. 스캐폴딩**
- Vite + @crxjs/vite-plugin + TypeScript 프로젝트 생성
- `manifest.json` (MV3) 작성
- 위 폴더 구조 생성 (background, content, popup, shared)

**Step 2. 본문 추출 + 문단 인덱싱 (`extractor.ts`)**
- @mozilla/readability 연동
- `paragraphs: { idx, text, el }[]` 생성
- `data-prober-idx` 부여
- 폴백 전략 구현

**Step 3. mock 퀴즈로 위젯 UI 렌더 (`content/ui/`, React + Shadow DOM)**
- 기사 75% / 패널 25% 레이아웃
- Shadow DOM으로 CSS 격리
- 객관식 보기(A/B/C/D) + 제출 버튼 UI
- 정답/오답 피드백 UI
- 재질문 2단계 UI
- **이 단계는 실제 API 없이 하드코딩 mock 데이터로 동작 확인**

### Day 1 오후

**Step 4. 앵커 매칭 (`anchor.ts`) ⚠️**
- anchorText 부분 일치 → 유사도 → paragraphIndex → 하단 강등 순 구현
- 프로토타이핑 우선 (리스크 최우선 해소)

**Step 5. 문단 진입 감지 (`observer.ts`)**
- `IntersectionObserver` 세팅 (뷰포트 60% 기준)
- 중복 트리거 방지 플래그

**Step 6. 진단 루프 상태머신 (`session.ts`)**
- 위 상태 전이 구현
- `results[]` 누적 로직

**Step 7. 서버 연동 `POST /quiz` (`background/api.ts`)**
- content ↔ background 메시지 통신
- JWT Bearer 첨부
- 퀴즈 트리 수신 후 anchor.ts 실행

### Day 2 오전

**Step 8. 스크랩 수집·전송 `POST /scrap` (`background/api.ts`)**
- 전송 시점 처리 (자동저장 + flush)
- 재시도 큐 (`chrome.storage.local`)

**Step 9. 팝업 로그인 연동 (`popup/`)**
- `/auth/login` 연동
- 토큰 보관 및 진행률 표시
- 401 처리

### Day 2 오후

**Step 10. 앵커·진입 임계값 튜닝 + QA**
- 데모 기사 3~5개로 앵커 매칭 정확도 확인
- `threshold`·`rootMargin` 조정
- 오답 재질문 2단계 흐름 end-to-end 확인

---

## 7. 협업 접점

| 담당 | 협의 내용 |
|------|-----------|
| 담당2 (인증/서버) | `/auth/login` 응답 스키마, 401 처리·재로그인 규약 |
| 담당3 (서버 도메인) | `/quiz`·`/scrap` 스키마 확정, 특히 `anchorText` 포함 여부와 `results[].parentConcept` 링크 |

> 담당3 주의: 스크랩의 `conceptTag`는 퀴즈 트리의 값을 그대로 echo (main=`conceptTag`, 재질문=`prereqConceptTag`)
