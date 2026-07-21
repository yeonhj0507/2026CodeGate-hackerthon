"""흐름 B 통합 테스트 — Postgres 필요.

/scrap 버퍼링 → /thoughtmap/update 병합·추천·버퍼 소비까지 한 번에 확인한다.
"""

import pytest

pytestmark = pytest.mark.db


@pytest.fixture(autouse=True)
def _requires_db(db_available):
    if not db_available:
        pytest.skip("Postgres 미기동 (docker compose up -d)")


def scrap_payload(title: str, main: str, prereq: str, main_correct: bool, url: str | None = None):
    """스크랩 페이로드에는 원문이 없다(명세 §3.4). URL이 출처 식별자다."""
    return {
        "articleUrl": url or f"https://news.example.com/{main}",
        "articleTitle": title,
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

    # 크로스기사: 기준금리가 두 기사(다른 URL)에서 등장 → 출처 누적.
    sources = nodes["기준금리"]["sourceArticles"]
    assert len(sources) == 2
    assert {s["title"] for s in sources} == {"금리 기사", "환율 기사"}
    assert all(s["url"].startswith("https://") for s in sources)

    edges = {(e["from"], e["to"]) for e in body["graph"]["edges"]}
    assert edges  # 선행 → 후행 엣지 복원

    # 재동기화하면 버퍼는 비어 있다.
    again = await client.post("/thoughtmap/update", json={"graph": body["graph"]})
    assert again.json()["consumedScraps"] == 0
    assert len(again.json()["graph"]["nodes"]) == len(body["graph"]["nodes"])


async def test_same_article_read_twice_keeps_one_source(client):
    """같은 기사를 두 번 읽어도 출처는 URL 기준으로 1건이다."""
    url = "https://news.example.com/same-article"
    await client.post("/scrap", json=scrap_payload("금리 기사", "기준금리", "통화정책", False, url))
    # 제목이 살짝 바뀌어 다시 들어와도 URL이 같으면 같은 기사다.
    await client.post(
        "/scrap", json=scrap_payload("금리 기사(수정)", "기준금리", "통화정책", True, url)
    )

    body = (
        await client.post("/thoughtmap/update", json={"graph": {"nodes": [], "edges": []}})
    ).json()
    nodes = {n["concept"]: n for n in body["graph"]["nodes"]}
    assert len(nodes["기준금리"]["sourceArticles"]) == 1
    assert nodes["기준금리"]["sourceArticles"][0]["url"] == url


async def test_scrap_rejects_legacy_payload(client):
    """구형 페이로드(원문 포함, URL 없음)는 422 로 거절한다."""
    res = await client.post(
        "/scrap",
        json={
            "articleTitle": "옛 계약",
            "articleBody": "원문 전체...",
            "results": [{"conceptTag": "환율", "parentConcept": None, "level": 0, "correct": True}],
        },
    )
    assert res.status_code == 422
    assert res.json()["error"]["code"] == "VALIDATION_ERROR"


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
    assert "기준금리" in {c["conceptTag"] for c in rec["gapConcepts"]}
    # 첫 동기화라 이해완료가 없다 → 확장 후보 0건이 정상(콜드스타트, 명세 §4.4).
    assert rec["expansionConcepts"] == []

    # 시드 데이터셋의 conceptTags 와 매칭되어 기사가 추천된다.
    assert rec["articles"], "제휴 기사 시드가 필요하다 (python scripts/seed.py)"
    for article in rec["articles"]:
        assert article["url"].startswith("http")
    # 개념이 매칭된 기사가 선호 카테고리만 맞은 기사보다 먼저 온다.
    assert rec["articles"][0]["matchedConcepts"]


async def test_expansion_recommends_retry_after_prereq_recovered(client):
    """오답 → 선행개념으로 내려가 선행만 맞힌 뒤, 원래 주장을 다시 권하는 흐름(명세 §4.4)."""
    await client.post(
        "/scrap",
        json={
            "articleUrl": "https://news.example.com/econ/rate",
            "articleTitle": "금리 기사",
            "results": [
                # 본문 주장은 틀렸고, 내려간 선행개념은 맞혔다.
                {"conceptTag": "기준금리", "parentConcept": None, "level": 0, "correct": False},
                {
                    "conceptTag": "통화정책",
                    "parentConcept": "기준금리",
                    "level": 1,
                    "correct": True,
                },
            ],
        },
    )

    body = (
        await client.post("/thoughtmap/update", json={"graph": {"nodes": [], "edges": []}})
    ).json()
    rec = body["recommendations"]

    retry = [e for e in rec["expansionConcepts"] if e["reason"] == "retry"]
    assert [e["conceptTag"] for e in retry] == ["기준금리"]

    # 확장으로 뽑힌 개념은 결핍 목록에 중복 등장하지 않는다.
    assert "기준금리" not in {c["conceptTag"] for c in rec["gapConcepts"]}

    # 노드는 강등되지 않는다 — promoted 는 단조 증가.
    assert all(n["promoted"] is True for n in body["graph"]["nodes"])


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
