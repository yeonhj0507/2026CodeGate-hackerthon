# 서버 배포 — Render (앱 + PostgreSQL)

FastAPI 앱과 PostgreSQL(pgvector)을 **모두 Render**에 둔다. `render.yaml`(레포 루트)이
웹 서비스(`prober-api`)와 DB(`prober-db`)를 한 번에 프로비저닝하고 `DATABASE_URL` 을
자동 연결한다. 클라이언트(데스크톱 앱)는 Render URL 을 바라보게 빌드한다.

> **왜 Render(서버리스 아님)인가:** `/quiz/stream`(NDJSON 스트리밍)·`/thoughtmap/update`
> (LLM+검색 병렬, 수십 초)가 서버리스의 요청 시간 제한·스트리밍 제약에 걸리기 쉬워,
> 시간 제한 없는 상시가동 컨테이너가 맞는다. DB 도 같은 플랫폼에 둬서 내부망으로 붙는다.

관련 파일(이미 레포에 포함):
- `render.yaml` — 웹 서비스 + Postgres + 환경변수 정의(레포 루트)
- `server/app/core/config.py` — Render 가 주는 `postgresql://...` 를 `postgresql+asyncpg://`
  로 정규화(+ libpq `sslmode` 쿼리 제거)
- `server/app/core/db.py` — `async_engine_options()` 가 SSL·풀러 옵션을 호스트/포트로 자동 판단

---

## 1. Blueprint 배포 (앱 + DB 생성)

1. https://render.com → **New → Blueprint** → 이 GitHub 레포 연결.
   레포 루트의 `render.yaml` 을 자동 인식해 `prober-db`(무료 Postgres)와
   `prober-api`(웹 서비스)를 만든다.
2. 시크릿 환경변수 입력(`render.yaml` 에서 `sync: false` 로 표시된 값):

   | 키 | 값 | 필요 시점 |
   |---|---|---|
   | `ANTHROPIC_API_KEY` | Claude 키 | `LLM_PROVIDER=claude` 로 바꿀 때 |
   | `NAVER_CLIENT_ID` / `NAVER_CLIENT_SECRET` | 뉴스 검색 키 | 기사 검색 쓸 때(선택) |

   > `DATABASE_URL` 은 `prober-db` 에서 자동 주입(입력 불필요). `JWT_SECRET` 은 Render 가
   > 자동 생성. `LLM_PROVIDER` 기본 `mock`(키 없이 전 파이프라인 동작).
3. **Apply** → DB 와 앱이 생성된다. 이 시점엔 아직 테이블이 없어 DB 를 쓰는 엔드포인트는
   실패하지만, `GET /health` 는 200 이다(앱 기동 자체는 정상).

## 2. 마이그레이션 & 시드 (로컬에서 1회)

Render 무료 Postgres 는 배포 시 마이그레이션을 자동 실행하지 않으므로 사람이 한 번 돌린다.
로컬에서는 DB 의 **External(외부) 연결 URL** 로 붙는다(내부 URL 은 Render 망 밖에서 안 됨).

1. Render → `prober-db` → **Connections** → **External Database URL** 복사
   (`postgresql://prober:...@dpg-....render.com/prober_db` 형태).
2. 로컬 실행:

```bash
cd server
python -m venv .venv && source .venv/Scripts/activate   # PS: .venv\Scripts\Activate.ps1
pip install -r requirements.txt

export DATABASE_URL="postgresql://prober:<pw>@dpg-xxxx.oregon-postgres.render.com/prober_db"
export DB_REQUIRE_SSL=1     # 외부 연결은 SSL 필수. 접두사/드라이버는 config.py 가 정규화.

alembic upgrade head       # 0001~0004 스키마 + CREATE EXTENSION vector
python scripts/seed.py     # 제휴 기사 데이터셋 시드(기사 추천에 필요, 선택)
```

> `CREATE EXTENSION vector` 가 권한 오류로 실패하면, Render `prober-db` → **PSQL/Shell**
> 에서 `CREATE EXTENSION IF NOT EXISTS vector;` 를 한 번 실행한 뒤 `alembic upgrade head` 재시도.

## 3. 확인

```
https://prober-api.onrender.com/health   →  {"status":"ok"}
https://prober-api.onrender.com/docs     →  Swagger UI
```
`/docs` 에서 `/auth/signup` 을 눌러 DB 왕복까지 되면 성공(여기서 실패하면 대개 2단계 미실행).

> **무료 플랜 주의:** 웹 서비스가 15분 유휴 시 슬립 → 다음 요청 콜드스타트(수십 초).
> 데모 직전 `/health` 로 깨워두거나 `render.yaml` 의 `plan: starter`($7/월)로 상시가동.
> 무료 Postgres 는 생성 ~30일 뒤 만료되니 데모 후 유지하려면 유료로 승급.

## 4. 클라이언트 연결

```powershell
cd deploy
pwsh ./build.ps1 -ApiBaseUrl https://prober-api.onrender.com
```
(익스텐션도: `cd extension; $env:VITE_API_BASE_URL="https://prober-api.onrender.com"; npm ci; npm run build`)

## 5. 설치 파일 다운로드 페이지

서버가 다운로드 랜딩 페이지를 겸한다(별도 프론트 불필요):
- `GET /download` → 설치 안내 + **Windows용 다운로드** 버튼(HTML).
- `GET /download/win` → 실제 설치 파일로 302 리다이렉트.

실제 `.exe` 는 **GitHub Releases 의 `app-latest` 태그 애셋**(`ProberSetup.exe`)에 둔다
(Render 리눅스 컨테이너는 Windows exe 를 만들 수 없다). 빌드하면서 함께 올리려면:

```powershell
cd deploy
pwsh ./build.ps1 -ApiBaseUrl https://prober-api.onrender.com -PublishRelease
# gh CLI 로그인 필요. app-latest 릴리스에 ProberSetup.exe 로 업로드(--clobber)한다.
```

이후 사용자에게는 `https://prober-api.onrender.com/download` 만 안내하면 된다.
바이너리를 다른 곳(R2/스토리지)으로 옮기려면 `DOWNLOAD_URL` 환경변수만 바꾼다(코드 변경 없음).

---

## 트러블슈팅

| 증상 | 원인 / 해결 |
|---|---|
| 로컬 `alembic` SSL 오류 | 외부 URL 인데 `DB_REQUIRE_SSL=1` 안 줌 |
| `password authentication` / 접속 불가 | **내부** URL 로 로컬에서 시도한 경우. **External** URL 사용 |
| `type "vector" does not exist` | pgvector 미설치 — 위 PSQL 로 `CREATE EXTENSION vector` 후 재마이그레이션 |
| `/health` OK 인데 `/auth/*` 500 | 2단계 마이그레이션 미실행(테이블 없음) |
| 빌드 실패(파이썬 버전) | `render.yaml` 의 `PYTHON_VERSION=3.12` 확인 |
| 첫 요청 매우 느림 | 무료 플랜 콜드스타트. 앱 `receiveTimeout`(180s)이 넉넉해 실패는 안 함 |

> DB 를 Render 대신 Supabase/Neon 으로 바꾸려면: `render.yaml` 의 `databases:` 블록과
> `DATABASE_URL` 의 `fromDatabase` 를 빼고, `DATABASE_URL` 을 `sync: false` 로 두어 해당
> 서비스의 연결 문자열을 직접 입력하면 된다(코드 변경 불필요 — config/db 가 알아서 정규화·SSL 처리).
