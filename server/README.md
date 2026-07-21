# Prober — 백엔드 서버

FastAPI · PostgreSQL(pgvector) · SQLAlchemy 2.0(async) · Alembic · JWT

담당2의 **인증/계정 모듈**과 담당3의 **도메인 로직**(`/quiz`, `/scrap`, `/thoughtmap/update`)이
**하나의 FastAPI 앱**을 공유한다. 공유 자산(`Base`, `get_db`, `get_current_user`, 에러 포맷)
사용 규약은 [`app/domain/README.md`](app/domain/README.md) 참고.

## 구조

```
server/
├─ app/
│  ├─ main.py            # FastAPI 앱, 라우터/에러/rate limit 등록
│  ├─ core/              # 공유: 설정·DB·보안·인증의존성·에러·ratelimit·ID
│  │  ├─ config.py       # .env 로드 (JWT · DB · LLM · 스크랩 버퍼 설정)
│  │  ├─ db.py           # async engine, Base, get_db
│  │  ├─ security.py     # bcrypt 해시 + JWT(HS256)
│  │  ├─ deps.py         # get_current_user (도메인 라우트가 재사용)
│  │  ├─ errors.py       # 통일 에러 포맷 {"error":{code,message}}
│  │  ├─ ratelimit.py    # slowapi limiter
│  │  └─ ids.py          # PK 생성기
│  ├─ auth/              # 담당2: User 모델·스키마·서비스·라우터
│  └─ domain/            # 담당3: 도메인 로직
│     ├─ models.py       # TempScrap, PartnerArticle
│     ├─ schemas.py      # API 계약 (필드명 고정)
│     ├─ quiz/           # 문단 분할 · LLM 출력 정규화/검증
│     ├─ scrap/          # 버퍼 append · TTL/상한 정리
│     ├─ thoughtmap/     # merge(순수) · recommend(결핍·확장) · service(트랜잭션)
│     └─ llm/            # base(프로토콜) · mock · claude · prompts · quiz_prompt_requirements(퀴즈 시스템 프롬프트 본문)
├─ alembic/              # 마이그레이션 (0001 users → 0002 도메인 테이블 → 0003 스크랩 URL화)
├─ seed/                 # 제휴 기사 데이터셋
├─ scripts/              # seed.py · demo_flow.py
└─ tests/
```

## 실행 방법

```bash
cd server
python -m venv .venv
# Windows PowerShell:  .venv\Scripts\Activate.ps1
# Git Bash:            source .venv/Scripts/activate
pip install -r requirements.txt

cp .env.example .env          # 값 채우기 (특히 JWT_SECRET)

docker compose up -d          # pgvector/pgvector:pg16
alembic upgrade head          # DB 스키마 생성
python scripts/seed.py        # 제휴 기사 데이터셋 시드
uvicorn app.main:app --reload # http://127.0.0.1:8000/docs
```

```bash
pytest                        # Postgres 없으면 DB 테스트는 자동 skip
python scripts/demo_flow.py   # 로그인 → 흐름 A → 흐름 B 엔드투엔드
```

> **Postgres 없이 빠르게 확인**하려면 `.env` 의 `DATABASE_URL` 을
> `sqlite+aiosqlite:///./prober_dev.db` 로 바꾸면 인증 경로는 그대로 동작한다(스모크용).
> 단 추천의 pgvector 유사도 검색(스트레치)은 Postgres 전용이다.

## API

| 메서드 | 경로 | 호출자 | 요청 | 응답 |
|---|---|---|---|---|
| POST | `/auth/signup` | 공통 | `{email, password, display_name?}` | `201 {userId}` |
| POST | `/auth/login` | 공통 | `{email, password, client?}` | `200 {accessToken, expiresIn, userId}` |
| GET | `/auth/me` | 공통 | Bearer | `200 {userId, email, displayName}` |
| DELETE | `/auth/me` | 공통 | Bearer | `204` |
| POST | `/quiz` | 익스텐션 | `{articleTitle, articleBody}` | 재질문 트리 포함 퀴즈 전체 정보 (저장 안 함) |
| POST | `/scrap` | 익스텐션 | `{articleUrl, articleTitle, results[]}` — **원문 없음** | `201 {ok, buffered}` |
| POST | `/thoughtmap/update` | 로컬앱 | `{graph, userContext}` | `{graph, recommendations, consumedScraps}` |
| GET | `/health` | – | – | `{status:"ok"}` |

- 도메인 라우트는 전부 `Depends(get_current_user)` — 항상 `current_user.user_id` 기준으로만
  조회/쓰기한다(계정 격리, 명세 §4.5).
- 익스텐션·로컬 앱은 **각자 독립 로그인**(토큰 비공유), 동일 계정으로 서버에서 묶임.
- 에러 응답은 모두 `{"error": {"code": "...", "message": "..."}}`.

## 계약 메모 (담당1·로컬앱과 합의 사항)

- `/quiz`·`/scrap` 스키마는 구현계획① §5, 그래프 스키마는 로컬앱 `lib/data/dto/graph.dart`
  와의 계약이다. 필드명(camelCase)을 바꾸면 양쪽이 깨진다.
- **기사 원문은 `/quiz` 요청에서만 오가고 어디에도 영속되지 않는다**(명세 §3.4·§4.3).
  `/scrap` 은 `articleUrl`·`articleTitle` 만 보내며, `temp_scraps` 에 원문 컬럼이 없다.
- 노드 출처 메타는 `sourceArticles: [{url, title}]` 이고 **URL이 식별자**다. 같은 기사를
  여러 번 읽어도 1건으로 유지되고, 다른 URL에서 같은 개념이 나오면 누적된다(크로스기사 노드).
- 미이해 개념의 `summaryMeta` 는 원문 재독해가 아니라 **개념 관계(선행/후행)·진단 결과·기사 제목**
  만으로 생성된다(명세 §4.4 ⚠️). 서버가 원문을 갖지 않기 때문이며, 의도된 범위 축소다.
- `anchorText` 는 LLM 출력을 쓰지 않고 **서버가 해당 문단 앞 50자로 직접 채운다.**
  익스텐션의 앵커 매칭 리스크(구현계획① §3.3)를 서버가 보증하기 위함이다.
- 엣지 방향은 `from` = 선행 개념, `to` = 후행 개념. 스크랩의 `parentConcept` 가 후행이고
  `conceptTag` 가 선행이다(재질문은 얕은 개념으로 내려가므로).
- `/thoughtmap/update` 응답의 `recommendations` 는 **세 갈래**다(명세 §4.4):
  ```
  {
    gapConcepts:       [{conceptId, conceptTag, reason}],   // 결핍 보완, reason 은 자연어
    expansionConcepts: [{conceptId, conceptTag, reason}],   // 심화, reason 은 "retry"|"sibling"
    articles:          [{title, url, publisher, summary, matchedConcepts}]
  }
  ```
  두 개념 목록은 같은 모양이고 `conceptId` 는 그래프 노드 id 라 로컬앱이 위치를 짚을 수 있다.
  `expansionConcepts` 의 `reason` 은 신호 종류이며 사용자에게 보일 문구 매핑은 로컬앱 소관이다.
  같은 개념이 두 목록에 동시에 오르지 않는다(확장 쪽이 우선).

## LLM

`LLM_PROVIDER=mock`(기본)이면 키 없이 전 구간이 결정론적으로 동작한다.
키가 있으면 `.env` 에 `ANTHROPIC_API_KEY` 를 넣고 `LLM_PROVIDER=claude` 로 바꾼다.
프롬프트·tool 스키마는 `app/domain/llm/prompts.py`. **퀴즈 출제 시스템 프롬프트 본문은
`app/domain/llm/quiz_prompt_requirements.py::QUIZ_SYSTEM_PROMPT` 로 분리**했다(`prompts.py::QUIZ_SYSTEM`
이 재노출). 좋은 퀴즈 질문·개념어(conceptTag)를 뽑기 위한 프롬프트 튜닝은 그 파일에서만 한다.

**모델·호출 정책** (`app/domain/llm/claude.py`) — 모델은 `claude-opus-4-8`.

| 호출 지점 | thinking | effort | max_tokens | 실측 지연 |
|---|---|---|---|---|
| `/quiz` 퀴즈 생성 | adaptive | high | 16000 (스트리밍) | 약 40~47초 |
| 개념 재요약 (`/thoughtmap/update`) | 끔 | low | 4000 | 약 8초 |

- 퀴즈는 품질이 서비스의 핵심이라 사고를 켠다. **사고 토큰도 `max_tokens` 에 포함**되므로
  넉넉히 잡고 스트리밍으로 받는다(큰 `max_tokens` 비스트리밍은 HTTP 타임아웃 위험).
- 재요약은 근거가 개념 관계뿐이라 사고가 불필요하고, 로컬앱의 60초 `receiveTimeout`
  안에 들어와야 한다. 초과하기 시작하면 `thoughtmap/service.py:MAX_SUMMARIES`(12)를 낮추는 게
  첫 번째 레버다.
- tool 스키마는 `strict: True`. **strict 는 재귀 스키마와 `minItems`/`maxItems`/`minimum`/
  `maximum` 을 지원하지 않는다**(400) — 그래서 재질문을 L1/L2로 펼쳐 정의했고, 개수·범위는
  스키마 `description` 과 시스템 프롬프트로 요구한 뒤 `quiz/service.py` 가 최종 검증·클램프한다.
- 에러는 전부 공통 포맷으로 변환된다: `LLM_REFUSED`(모델 거절) · `LLM_TRUNCATED`(max_tokens) ·
  `LLM_RATE_LIMITED`(429) · `LLM_API_ERROR`(5xx) · `LLM_UNREACHABLE`(네트워크) ·
  `LLM_NOT_CONFIGURED`(키 없음).

**실호출 테스트** — 기본 `pytest` 는 `conftest.py` 가 `LLM_PROVIDER=mock` 을 강제하므로
`.env` 가 `claude` 여도 과금되지 않는다. 실제 호출을 검증하려면 명시적으로 켠다:

```bash
PROBER_LIVE_LLM=1 pytest -m live      # 퀴즈 1회 + 요약 1회, 약 55초 · 대략 $0.05~0.15
```

## 탈퇴 시 파기 규약 (담당2 ↔ 담당3, 해결됨)

`temp_scraps.user_id` 는 FK가 아니라 문자열이라 DB cascade 가 걸리지 않는다.
그래서 `auth/service.delete_user()` 가 **계정과 같은 트랜잭션에서** `TempScrap` 을
직접 지운다(기획서 §6 '탈퇴 시 즉시 파기'). 회귀 테스트는 `tests/test_account_deletion.py`.

> **도메인 테이블을 추가하면 `delete_user()` 에도 삭제를 함께 넣어야 한다.**
> 빠뜨리면 탈퇴 후에도 학습 기록(개념 태그·정답/오답)이 버퍼 TTL(기본 7일) 동안 서버에 남아
> "학습 데이터는 로컬이 소유한다"는 전제가 깨진다.
> (명세 개정 이후 원문은 애초에 버퍼에 들어오지 않는다 — `temp_scraps` 에 원문 컬럼이 없다.)
