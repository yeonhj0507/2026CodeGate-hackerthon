"""탈퇴 시 서버 잔여 데이터 파기 검증 — Postgres 필요.

기획서 §6 '탈퇴 시 즉시 파기'. `temp_scraps.user_id` 는 FK 가 아니라 DB cascade 가
걸리지 않으므로, 계정 삭제가 버퍼까지 지우는지 회귀 테스트로 고정한다.
"""

import pytest
from sqlalchemy import func, select

from app.auth.models import User
from app.core.db import SessionLocal
from app.domain.models import TempScrap

pytestmark = pytest.mark.db


@pytest.fixture(autouse=True)
def _requires_db(db_available):
    if not db_available:
        pytest.skip("Postgres 미기동 (docker compose up -d)")


def scrap_payload():
    return {
        "articleTitle": "탈퇴 테스트 기사",
        "articleBody": "기준금리에 대한 기사 본문.",
        "results": [
            {"conceptTag": "기준금리", "parentConcept": None, "level": 0, "correct": False},
            {"conceptTag": "통화정책", "parentConcept": "기준금리", "level": 1, "correct": False},
        ],
    }


async def _scrap_count(user_id: str) -> int:
    async with SessionLocal() as db:
        return await db.scalar(
            select(func.count()).select_from(TempScrap).where(TempScrap.user_id == user_id)
        )


async def _user_exists(user_id: str) -> bool:
    async with SessionLocal() as db:
        return await db.get(User, user_id) is not None


async def test_delete_account_purges_temp_scraps(client):
    user_id = (await client.get("/auth/me")).json()["userId"]

    assert (await client.post("/scrap", json=scrap_payload())).status_code == 201
    assert await _scrap_count(user_id) == 1, "사전 조건: 버퍼에 스크랩이 남아 있어야 한다"

    assert (await client.delete("/auth/me")).status_code == 204

    # 계정과 기사 원문 버퍼가 함께 사라져야 한다(§6 즉시 파기).
    assert await _scrap_count(user_id) == 0
    assert not await _user_exists(user_id)


async def test_delete_account_leaves_other_users_scraps(client, other_client):
    """남의 탈퇴가 내 버퍼를 지우면 안 된다(계정 단위 격리, 명세 §4.5)."""
    mine = (await client.get("/auth/me")).json()["userId"]

    await client.post("/scrap", json=scrap_payload())
    await other_client.post("/scrap", json=scrap_payload())

    assert (await other_client.delete("/auth/me")).status_code == 204

    assert await _scrap_count(mine) == 1
