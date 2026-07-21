# 프로버 백엔드 서버

`기능명세서_Prober.md` §4의 서버 도메인 로직 — 퀴즈 생성, 임시 스크랩 버퍼링, 지식그래프 갱신·추천.
계정/인증(§4.1)은 담당2 소관이며 이 앱에 나중에 얹힌다.

## 실행

```bash
cp .env.example .env
docker compose up -d                 # pgvector/pgvector:pg16
python -m venv .venv && .venv/Scripts/pip install -r requirements.txt
.venv/Scripts/alembic upgrade head
.venv/Scripts/python scripts/seed.py         # 제휴 기사 데이터셋
.venv/Scripts/uvicorn app.main:app --reload  # http://localhost:8000/docs
```

```bash
.venv/Scripts/pytest                          # Postgres 없으면 DB 테스트는 자동 skip
.venv/Scripts/python scripts/demo_flow.py     # 흐름 A → 흐름 B 엔드투엔드
```

## API

| 메서드 | 경로 | 호출자 | 설명 |
|---|---|---|---|
| POST | `/quiz` | 익스텐션 | 기사 → 재질문 트리 포함 퀴즈 전체 정보 (저장 안 함) |
| POST | `/scrap` | 익스텐션 | 세션 진단 결과를 계정 단위로 버퍼링 |
| POST | `/thoughtmap/update` | 로컬앱 | 그래프 병합 + 추천 + 버퍼 소비·삭제 |
| GET | `/health` | — | 헬스체크 |

에러 포맷은 전부 `{"error": {"code": "...", "message": "..."}}`.

### 인증 (임시)

담당2 합류 전까지 `app/core/deps.py:get_current_user` 가 **개발용 스텁**이다.
`X-User-Id` 헤더로 계정을 흉내 내며, 없으면 `dev-user`. JWT 구현이 오면 이 함수 본문만 바뀌고
라우터 시그니처는 그대로다.

## 계약 메모

- `/quiz`·`/scrap` 스키마는 구현계획① §5, 그래프 스키마는 로컬앱 `lib/data/dto/graph.dart` 와의 계약이다.
  필드명(camelCase)을 바꾸면 양쪽이 깨진다.
- `anchorText` 는 LLM 출력을 쓰지 않고 **서버가 해당 문단 앞 50자로 직접 채운다.**
  익스텐션의 앵커 매칭 리스크(구현계획① §3.3)를 서버가 보증하기 위함이다.
- 엣지 방향은 `from` = 선행 개념, `to` = 후행 개념. 스크랩의 `parentConcept` 가 후행이고
  `conceptTag` 가 선행이다(재질문은 얕은 개념으로 내려가므로).
- `/thoughtmap/update` 응답의 `recommendations` 는 `{concepts: [{concept, reason}],
  articles: [{title, url, publisher, summary, matchedConcepts}]}`. 로컬앱 DTO에 아직 없으니 맞춰야 한다.

## LLM

`LLM_PROVIDER=mock`(기본)이면 키 없이 전 구간이 결정론적으로 동작한다.
키가 준비되면 `.env` 에 `ANTHROPIC_API_KEY` 를 넣고 `LLM_PROVIDER=claude` 로 바꾸기만 하면 된다.
프롬프트·tool 스키마는 `app/domain/llm/prompts.py`.

## 구조

```
app/
├─ main.py                 FastAPI 앱 (담당2 auth 라우터가 여기 추가된다)
├─ core/                   settings · db(Base/get_db) · deps(get_current_user) · errors
└─ domain/
   ├─ models.py            TempScrap, PartnerArticle
   ├─ schemas.py           API 계약 (필드명 고정)
   ├─ quiz/                문단 분할 · LLM 출력 정규화/검증
   ├─ scrap/               버퍼 append · TTL/상한 정리
   ├─ thoughtmap/          merge(순수) · recommend · service(트랜잭션)
   └─ llm/                 base(프로토콜) · mock · claude · prompts
```
