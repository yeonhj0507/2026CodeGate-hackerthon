"""흐름 B 통합 테스트 — Postgres 필요.

/scrap 버퍼링 → /thoughtmap/update 병합·추천·버퍼 소비까지 한 번에 확인한다.
"""

import pytest

pytestmark = pytest.mark.db


@pytest.fixture(autouse=True)
def _requires_db(db_available):
    if not db_available:
        pytest.skip("Postgres 미기동 (docker compose up -d)")


def scrap_payload(title: str, main: str, prereq: str, main_correct: bool):
    return {
        "articleTitle": title,
        "articleBody": f"{main}에 대한 기사 본문.",
        "results": [
            {"conceptTag": main, "parentConcept": None, "level": 0, "correct": main_correct},
            {"conceptTag": prereq, "parentConcept": main, "level": 1, "correct": False},
        ],
    }


async def test_scrap_then_sync_consumes_buffer(client):
    r1 = await client.post("/scrap", json=scrap_payload("금리 기사", "기준금리", "통화정책", False))
    assert r1.status_code == 201
    assert r1.json() == {"ok": True, "buffered": 2}

    await client.post("/scrap", json=scrap_payload("환율 기사", "환율", "기준금리", True))

    res = await client.post("/thoughtmap/update", json={"graph": {"nodes": [], "edges": []}})
    assert res.status_code == 200
    body = res.json()
    assert body["consumedScraps"] == 2

    nodes = {n["concept"]: n for n in body["graph"]["nodes"]}
    assert nodes["기준금리"]["state"] == "not_understood"   # 마지막 스크랩에서 선행 오답
    assert nodes["환율"]["state"] == "understood"
    assert nodes["통화정책"]["isPrereq"] is True

    # 미이해 노드에는 개인화 요약이 붙는다(명세 §4.4).
    assert nodes["통화정책"]["summaryMeta"]

    # 크로스기사: 기준금리가 두 기사에서 등장 → 출처 병합.
    assert len(nodes["기준금리"]["sourceArticles"]) == 2

    edges = {(e["from"], e["to"]) for e in body["graph"]["edges"]}
    assert edges  # 선행 → 후행 엣지 복원

    # 재동기화하면 버퍼는 비어 있다.
    again = await client.post("/thoughtmap/update", json={"graph": body["graph"]})
    assert again.json()["consumedScraps"] == 0
    assert len(again.json()["graph"]["nodes"]) == len(body["graph"]["nodes"])


async def test_recommendations_use_partner_dataset(client):
    await client.post("/scrap", json=scrap_payload("금리 기사", "기준금리", "통화정책", False))

    res = await client.post(
        "/thoughtmap/update",
        json={
            "graph": {"nodes": [], "edges": []},
            "userContext": {"preferredCategories": ["경제"], "preferredKeywords": ["환율"]},
        },
    )
    rec = res.json()["recommendations"]
    assert "기준금리" in {c["concept"] for c in rec["concepts"]}

    # 시드 데이터셋의 conceptTags 와 매칭되어 기사가 추천된다.
    assert rec["articles"], "제휴 기사 시드가 필요하다 (python scripts/seed.py)"
    for article in rec["articles"]:
        assert article["url"].startswith("http")
    # 개념이 매칭된 기사가 선호 카테고리만 맞은 기사보다 먼저 온다.
    assert rec["articles"][0]["matchedConcepts"]


async def test_user_isolation(client, other_client):
    await client.post("/scrap", json=scrap_payload("남의 기사", "환율", "무역수지", False))

    # 남의 계정 동기화는 내 버퍼를 건드리지 못한다.
    other = await other_client.post(
        "/thoughtmap/update", json={"graph": {"nodes": [], "edges": []}}
    )
    assert other.json()["consumedScraps"] == 0

    mine = await client.post("/thoughtmap/update", json={"graph": {"nodes": [], "edges": []}})
    assert mine.json()["consumedScraps"] == 1


async def test_requires_authentication():
    """토큰 없이는 도메인 라우트에 접근할 수 없다."""
    from httpx import ASGITransport, AsyncClient

    from app.main import app

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        for path in ("/quiz", "/scrap", "/thoughtmap/update"):
            res = await ac.post(path, json={})
            assert res.status_code in (401, 403), path
            assert "error" in res.json()
