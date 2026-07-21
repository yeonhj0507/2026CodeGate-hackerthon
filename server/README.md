# Prober — 백엔드 서버 (담당2: 인증/계정)

FastAPI · PostgreSQL · SQLAlchemy 2.0(async) · Alembic · JWT

담당2가 소유하는 **인증/계정 모듈**과, 담당3가 붙일 도메인 라우터가 **하나의 FastAPI 앱**을 공유한다.
공유 자산(`Base`, `get_db`, `get_current_user`, 에러 포맷) 사용법은 [`app/domain/README.md`](app/domain/README.md) 참고.

## 구조

```
server/
├─ app/
│  ├─ main.py            # FastAPI 앱, 라우터/에러/rate limit 등록
│  ├─ core/              # 공유: 설정·DB·보안·인증의존성·에러·ratelimit
│  │  ├─ config.py       # .env 로드
│  │  ├─ db.py           # async engine, Base, get_db
│  │  ├─ security.py     # bcrypt 해시 + JWT(HS256)
│  │  ├─ deps.py         # get_current_user (담당3 재사용)
│  │  ├─ errors.py       # 통일 에러 포맷 {"error":{code,message}}
│  │  ├─ ratelimit.py    # slowapi limiter
│  │  └─ ids.py          # PK 생성기
│  ├─ auth/              # 담당2: User 모델·스키마·서비스·라우터
│  └─ domain/            # 담당3: quiz/scrap/thoughtmap (README만)
├─ alembic/              # 마이그레이션 (async env)
├─ alembic.ini
├─ requirements.txt
└─ .env.example
```

## 실행 방법

```bash
cd server
python -m venv .venv
# Windows PowerShell:  .venv\Scripts\Activate.ps1
# Git Bash:            source .venv/Scripts/activate
pip install -r requirements.txt

cp .env.example .env          # 값 채우기 (특히 JWT_SECRET)

alembic upgrade head          # DB 스키마 생성
uvicorn app.main:app --reload # http://127.0.0.1:8000/docs
```

> **Postgres 없이 빠르게 확인**하려면 `.env` 의 `DATABASE_URL` 을
> `sqlite+aiosqlite:///./prober_dev.db` 로 바꾸면 그대로 동작한다(스모크 테스트용).

## API

| 메서드 | 경로 | 요청 | 응답 |
|---|---|---|---|
| POST | `/auth/signup` | `{email, password, display_name?}` | `201 {userId}` |
| POST | `/auth/login` | `{email, password, client?}` | `200 {accessToken, expiresIn, userId}` |
| GET | `/auth/me` | Bearer | `200 {userId, email, displayName}` |
| DELETE | `/auth/me` | Bearer | `204` |
| GET | `/health` | – | `{status:"ok"}` |

- `client` 는 `"extension"` \| `"local"` (토큰 클레임에 기록, 권한 차이 없음).
- 익스텐션·로컬 앱은 **각자 독립 로그인**(토큰 비공유), 동일 계정으로 서버에서 묶임.
- `/auth/refresh` 는 데모 스코프에서 생략(설계 §3.3).

에러 응답은 모두 `{"error": {"code": "...", "message": "..."}}` 형태.

## 담당3 연동 요약

1. 도메인 모델은 `from app.core.db import Base` 상속 → 같은 Alembic 체인.
2. 라우트에 `Depends(get_current_user)` → `current_user.user_id` 로만 데이터 접근(계정 격리).
3. 에러는 `raise AppError(status_code, code, message)`.
4. `app/domain/router.py` 만들고 `main.py` 에 `include_router`.
