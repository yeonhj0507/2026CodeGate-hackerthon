"""탐색 탭 `POST /explore` 계약 (Postgres 필요, LLM 은 mock)."""

import pytest

pytestmark = pytest.mark.db


async def test_explore_returns_joint_explanation_and_two_articles(client):
    res = await client.post(
        "/explore",
        json={
            "conceptIds": ["기준금리", "환율"],
            "conceptTags": ["기준금리", "환율"],
        },
    )
    assert res.status_code == 200
    body = res.json()

    # 개별 정의 나열이 아니라 묶음 설명이어야 한다 — 최소한 두 개념이 모두 등장한다.
    assert "기준금리" in body["explanation"]
    assert "환율" in body["explanation"]

    # 탐색은 2건까지만.
    assert len(body["articles"]) <= 2
    for article in body["articles"]:
        assert article["url"].startswith("http")
        assert article["source"] in ("partner", "search")


async def test_explore_requires_at_least_one_concept(client):
    res = await client.post("/explore", json={"conceptIds": [], "conceptTags": []})
    assert res.status_code == 422
    assert res.json()["error"]["code"] == "VALIDATION_ERROR"


async def test_explore_requires_auth():
    from httpx import ASGITransport, AsyncClient

    from app.main import app

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        res = await ac.post("/explore", json={"conceptTags": ["기준금리"]})
        assert res.status_code in (401, 403)
