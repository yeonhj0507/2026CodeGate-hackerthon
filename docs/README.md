# 프로버(Prober) — 코드게이트 해커톤 2026

기사를 읽다가 "내가 뭘 모르는지도 모르는" 지점을 AI가 짚어내고,
관련 배경지식을 지도처럼 펼쳐 보여주는 능동적 읽기 도우미.

팀명: 돌고레이전트

---

## 문서 목록

| 파일 | 내용 |
|------|------|
| [system_overview.md](./system_overview.md) | 전체 시스템 구조, 컴포넌트, API, 데이터 모델 |
| [extension_implementation_plan.md](./extension_implementation_plan.md) | 크롬 익스텐션 상세 구현 계획 + Day별 Step |
| [shared_contract.md](./shared_contract.md) | 스트림 분할(A/B/C), 타입 계약, Align 일정(T=0~5) |
| [stream_c_align.md](./stream_c_align.md) | Stream C(인프라) 진행 상태 + T별 align 체크리스트 — **계속 갱신됨** |

---

## 작업 현황

| 파트 | 담당자 | 상태 |
|------|--------|------|
| 크롬 익스텐션 | 정은택 | 🔲 미시작 |
| 로컬 앱 (Flutter) | 연현중 | 🔲 미시작 |
| 백엔드 서버 | 서버 담당 | 🔲 미시작 |

---

## 빠른 참조

- 익스텐션 서버 접점: `POST /quiz`, `POST /scrap`
- 퀴즈 형식: 객관식(MCQ), 클라이언트 즉시 채점
- 최대 리스크: 앵커 매칭 (`anchor.ts`) — 프로토타이핑 최우선
- Day 1 목표: 스캐폴딩 + 본문 추출 + mock UI + 앵커 매칭 + 진단 루프 + /quiz 실연동
- Day 2 목표: 스크랩 전송 + 로그인 연동 + 튜닝 + QA
