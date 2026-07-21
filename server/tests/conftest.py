import asyncio
import uuid

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import delete, text
from sqlalchemy.ext.asyncio import create_async_engine

from app.core.db import SessionLocal, engine
from app.core.settings import get_settings
from app.domain.models import TempScrap
from app.main import app


def pytest_configure(config):
    config.addinivalue_line("markers", "db: Postgres 연결이 필요한 테스트")


@pytest.fixture(scope="session")
def db_available() -> bool:
    """Postgres 없이 돌린 경우 DB 테스트를 건너뛰기 위한 판정.

    앱 전역 엔진의 커넥션 풀이 임시 이벤트 루프에 묶이지 않도록 별도 엔진을 쓴다.
    """

    async def probe() -> bool:
        probe_engine = create_async_engine(get_settings().database_url)
        try:
            async with probe_engine.connect() as conn:
                await conn.execute(text("select 1"))
            return True
        except Exception:
            return False
        finally:
            await probe_engine.dispose()

    return asyncio.run(probe())


@pytest.fixture
def user_id() -> str:
    """테스트마다 격리된 계정. 도메인 로직은 항상 user_id 로만 조회/쓰기한다."""
    return f"test-{uuid.uuid4()}"


@pytest_asyncio.fixture
async def client(user_id: str):
    transport = ASGITransport(app=app)
    async with AsyncClient(
        transport=transport,
        base_url="http://test",
        headers={"X-User-Id": user_id},
    ) as ac:
        yield ac

    # DB 없이 도는 테스트(/quiz 등)도 있으므로 정리 실패는 무시한다.
    try:
        async with SessionLocal() as db:
            await db.execute(delete(TempScrap).where(TempScrap.user_id == user_id))
            await db.commit()
    except Exception:
        pass

    # 테스트마다 이벤트 루프가 새로 뜬다. 이전 루프에 묶인 커넥션이 풀에 남으면
    # 다음 테스트에서 "Event loop is closed" 로 터지므로 매번 풀을 비운다.
    await engine.dispose()
