import asyncio
import uuid

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import delete, text
from sqlalchemy.ext.asyncio import create_async_engine

from app.auth.models import User
from app.core.config import get_settings
from app.core.db import SessionLocal, engine
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


async def _make_client(prefix: str):
    """계정을 새로 만들어 로그인한 클라이언트를 반환.

    담당2의 인증을 우회하지 않고 그대로 태운다 — 계정 단위 격리(명세 §4.5)가
    도메인 로직의 전제이기 때문이다.
    """
    email = f"{prefix}-{uuid.uuid4().hex[:12]}@example.com"
    password = "test-password-1234"

    ac = AsyncClient(transport=ASGITransport(app=app), base_url="http://test")

    signup = await ac.post("/auth/signup", json={"email": email, "password": password})
    assert signup.status_code == 201, signup.text
    login = await ac.post(
        "/auth/login", json={"email": email, "password": password, "client": "extension"}
    )
    assert login.status_code == 200, login.text

    body = login.json()
    ac.headers["Authorization"] = f"Bearer {body['accessToken']}"
    return ac, body["userId"]


async def _cleanup(ac: AsyncClient, user_id: str) -> None:
    await ac.aclose()
    async with SessionLocal() as db:
        await db.execute(delete(TempScrap).where(TempScrap.user_id == user_id))
        await db.execute(delete(User).where(User.id == user_id))
        await db.commit()


@pytest_asyncio.fixture
async def client(db_available):
    if not db_available:
        pytest.skip("Postgres 미기동 (docker compose up -d)")

    ac, user_id = await _make_client("test")
    yield ac
    await _cleanup(ac, user_id)

    # 테스트마다 이벤트 루프가 새로 뜬다. 이전 루프에 묶인 커넥션이 풀에 남으면
    # 다음 테스트에서 "Event loop is closed" 로 터지므로 매번 풀을 비운다.
    await engine.dispose()


@pytest_asyncio.fixture
async def other_client(db_available):
    """다른 계정. 계정 간 데이터 격리 검증용."""
    if not db_available:
        pytest.skip("Postgres 미기동 (docker compose up -d)")

    ac, user_id = await _make_client("other")
    yield ac
    await _cleanup(ac, user_id)
