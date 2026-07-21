# 프로버(Prober) — 시스템 개요

> 근거 문서: Google Drive `코드게이트 해커톤 준비` > `[READ THIS] 제품 specification`
> 최종 업데이트: 2026-07-21

---

## 제품 한 줄 요약

기사를 읽다가 "내가 뭘 모르는지도 모르는" 지점을 AI가 질문으로 짚어내고,
관련 배경지식을 지도처럼 펼쳐 보여주는 능동적 읽기 도우미.

---

## 컴포넌트 구성

| 컴포넌트 | 역할 | 담당자 |
|----------|------|--------|
| 크롬 익스텐션 | 기사 본문 인식, 진단 퀴즈 표시/채점 UI, 스크랩 데이터 전송 | 정은택 |
| 로컬 앱 | 지식그래프(생각 지도) 원본 보유·표시, 개념/기사 추천 열람 | 연현중 |
| 백엔드 서버 | 퀴즈 생성, 지식그래프 업데이트 연산, 계정·인증 관리, 임시 스크랩 버퍼링 | 서버 담당 |

---

## 통신 규칙 (확정)

- 익스텐션과 로컬 앱은 **서로 직접 통신하지 않는다.**
- 모든 상호작용은 **서버를 경유**한다.
- 채널: 익스텐션 ↔ 서버, 로컬 앱 ↔ 서버 두 개뿐

---

## 데이터 저장 주체 (확정)

| 저장소 | 저장 대상 |
|--------|-----------|
| 서버 DB | 계정·인증 정보, 사용자 프로필 (학습 데이터는 저장 안 함) |
| 로컬 앱 | 지식그래프 원본, 학습이력, 기사 선호 패턴 |
| 서버 임시 버퍼 | 익스텐션이 보낸 스크랩 (로컬 앱이 동기화 시 소비 후 삭제) |

---

## 전체 데이터 흐름

### 흐름 A — 읽기 중 진단 (익스텐션 ↔ 서버)

```
1. 익스텐션: 기사 제목·원문 + 인증 정보 → 서버
2. 서버: 핵심 주장 추출 → 문단 태깅 → 퀴즈 전체 트리 생성 → 익스텐션
3. 익스텐션: 문단 진입 시 질문 제시 → 채점 → (오답 시) 설명+재질문(최대 2단계)
4. 익스텐션: 세션 진단 결과(기사 제목·원문 + 퀴즈별 개념 태그·정답/오답) → 서버 (임시 스크랩으로 버퍼링)
```

### 흐름 B — 생각 지도 업데이트 (로컬 앱 ↔ 서버)

```
1. 트리거: 로컬 앱 실행 시 최초 1회 자동, 또는 "내 이력 가져오기" 수동 클릭
2. 로컬: 현재 생각 지도 상태 + 사용자 전체 정보 → 서버
3. 서버: (기존 그래프 + 임시 스크랩 + 사용자 컨텍스트) 종합 → 그래프 갱신 + 추천 생성
4. 서버: 갱신된 생각 지도 → 로컬
5. 서버: 반영 완료된 임시 스크랩 삭제
6. 로컬: 갱신 그래프 반영·표시, 추천 열람
```

---

## API 엔드포인트 목록

| 채널 | 엔드포인트 | 요청 | 응답 |
|------|-----------|------|------|
| 익스텐션→서버 | `POST /quiz` | 기사 제목·원문, 인증 | 퀴즈 전체 트리 |
| 익스텐션→서버 | `POST /scrap` | 기사 제목·원문, 퀴즈별 개념 태그·정답/오답, 인증 | 저장 확인 |
| 로컬→서버 | `POST /thoughtmap/update` | 현재 그래프 상태, 사용자 전체 정보, 인증 | 갱신 그래프 + 추천 |
| 공통 | `POST /auth/*` | 계정·인증 | 토큰 |

---

## 핵심 데이터 모델

### 퀴즈 전체 트리 (서버 → 익스텐션)

```ts
interface Quiz {
  claimId: string
  conceptTag: string          // 핵심 개념명
  anchorText: string          // 문단 앞 40~60자 (앵커 매칭용)
  paragraphIndex: number      // 문단 번호 (앵커 매칭 폴백용)
  question: string
  options: string[]           // 객관식 보기 (확정)
  answerIndex: number
  explanation: string
  followups: Followup[]       // 재질문 트리 (최대 2단계)
}

interface Followup {
  level: number               // 1 또는 2
  prereqConceptTag: string    // 선행 개념명
  question: string
  options: string[]
  answerIndex: number
  explanation: string
  followups: Followup[]
}
```

### 스크랩 결과 (익스텐션 → 서버)

```ts
interface ScrapResult {
  conceptTag: string
  parentConcept: string | null  // main이면 null, 재질문이면 부모 개념명
  level: number                 // 0=main, 1=1단계, 2=2단계
  correct: boolean
}
```

### 지식그래프 (로컬 원본 / 서버↔로컬 교환)

```ts
interface Node {
  id: string
  concept: string
  state: 'understood' | 'misunderstood'
  isPrereq: boolean
  sourceArticles: string[]
  summaryMeta: string           // 미이해 개념 재요약 (개인화 요약 흡수)
}

interface Edge {
  from: string
  to: string
  type: string                  // 'prereq' 등
}
```

---

## 기술 스택 전체

| 파트 | 스택 |
|------|------|
| 크롬 익스텐션 | TypeScript, Manifest V3, Vite + @crxjs/vite-plugin, React + Shadow DOM, @mozilla/readability, zustand |
| 백엔드 서버 | Python 3.11+, FastAPI, SQLAlchemy 2.0 (async), PostgreSQL, Anthropic Claude API |
| 로컬 앱 | Flutter (Windows/macOS 데스크톱), Dart, SQLite (drift), graphview |

---

## 미해결 항목 (구현 시 결정)

- **문단 진입 감지 기준:** 뷰포트 노출 / 스크롤 위치 / 클릭 중 무엇으로 판정할지
- **앵커 매칭 정확도:** LLM이 지정한 문단과 실제 DOM 문단의 매칭 방식 — 최대 구현 리스크, 프로토타이핑 우선
- **스크랩 버퍼 안전장치:** 로컬 업데이트 요청이 오랫동안 없을 때 서버 버퍼 무한 누적 방지 (선택)

## 확정된 항목

- 퀴즈 형식: 객관식(MCQ), 클라이언트 즉시 채점
- 익스텐션·로컬 앱 독립 로그인 (동일 계정, 별도 세션)
- 개인화 요약: 별도 기능 없음, 지식그래프 노드 메타에 흡수
- 동기화: 로컬 앱 실행 시 1회 자동 + 수동 버튼, 실시간 폴링 없음
- 기기 변경·재설치 시 학습 데이터 유실 감수 (별도 백업 없음)
