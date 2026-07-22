"""공유 DB 계층 — 담당3 도메인 모델도 이 Base / get_db 를 그대로 사용한다."""
import os
from collections.abc import AsyncGenerator
from urllib.parse import urlparse

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase
from sqlalchemy.pool import NullPool

from app.core.config import settings


class Base(DeclarativeBase):
    """공유 선언적 베이스.

    담당3의 도메인 모델(TempScrap 등)도 반드시 이 Base 를 상속해야
    하나의 Alembic 마이그레이션 체인을 공유한다(명세 §7, 협업 §6).
    """


def async_engine_options(url: str) -> tuple[dict, dict]:
    """DB URL 을 보고 (engine_kwargs, connect_args) 를 계산한다.

    매니지드 PostgreSQL(Supabase 등)과 pgbouncer 커넥션 풀러의 요구사항을 흡수한다.
    호스트/포트로 판단하므로 배포 대상(Render·Fly·Vercel·로컬)에 상관없이 동작한다.
    db.py 와 alembic/env.py 가 공유한다.

      - Supabase 호스트면 ``ssl=require`` — asyncpg 기본값은 비암호화(ssl=None)라
        명시하지 않으면 TLS 강제인 Supabase 가 접속을 거부한다. (`DB_REQUIRE_SSL`
        환경변수로도 강제 가능 — Supabase 외 매니지드 PG 대비)
      - **트랜잭션 풀러(6543)** 면 ``statement_cache_size=0`` + ``NullPool`` —
        pgbouncer 트랜잭션 모드는 prepared statement 를 세션에 고정할 수 없어
        asyncpg 캐시를 꺼야 하고, 커넥션 수명 관리는 풀러에 맡긴다.
      - **세션 풀러(5432)·직접 연결·로컬** 은 일반 커넥션 풀 그대로 —
        상시가동 서버(Render 등)에 유리하고 prepared statement 도 문제없다.
    """
    engine_kwargs: dict = {"echo": False, "future": True}
    connect_args: dict = {}
    if url.startswith("postgresql+asyncpg"):
        parsed = urlparse(url)
        host = parsed.hostname or ""
        if "supabase" in host or os.getenv("DB_REQUIRE_SSL"):
            connect_args["ssl"] = "require"
        if parsed.port == 6543:
            connect_args["statement_cache_size"] = 0
            engine_kwargs["poolclass"] = NullPool
    return engine_kwargs, connect_args


_engine_kwargs, _connect_args = async_engine_options(settings.database_url)

# create_async_engine 은 지연 연결 — import 시점에 DB 로 실제 접속하지 않는다.
engine = create_async_engine(settings.database_url, connect_args=_connect_args, **_engine_kwargs)

SessionLocal = async_sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    """FastAPI 의존성: 요청 스코프 AsyncSession 제공."""
    async with SessionLocal() as session:
        yield session
