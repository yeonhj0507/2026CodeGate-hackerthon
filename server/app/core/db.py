"""공유 DB 계층 — 담당3 도메인 모델도 이 Base / get_db 를 그대로 사용한다."""
from collections.abc import AsyncGenerator

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase

from app.core.config import settings


class Base(DeclarativeBase):
    """공유 선언적 베이스.

    담당3의 도메인 모델(TempScrap 등)도 반드시 이 Base 를 상속해야
    하나의 Alembic 마이그레이션 체인을 공유한다(명세 §7, 협업 §6).
    """


# create_async_engine 은 지연 연결 — import 시점에 DB 로 실제 접속하지 않는다.
engine = create_async_engine(settings.database_url, echo=False, future=True)

SessionLocal = async_sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    """FastAPI 의존성: 요청 스코프 AsyncSession 제공."""
    async with SessionLocal() as session:
        yield session
