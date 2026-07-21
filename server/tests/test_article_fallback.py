"""기사 추천의 제휴-우선 / 검색-폴백 규칙 (Postgres 필요, LLM 미호출).

명세 §4.4 는 추천 소스를 "신문사 제휴 데이터셋"으로 확정했다. 검색은 그 자리를 뺏지 않고
**모자란 만큼만** 메워야 한다 — 그 경계를 여기서 고정한다.
"""

import pytest
import pytest_asyncio

from app.core.db import engine
from app.domain.schemas import UserContext
from app.domain.search.mock import MockSearchProvider
from app.domain.thoughtmap.recommend import MAX_ARTICLES, recommend_articles

pytestmark = pytest.mark.db


@pytest_asyncio.fixture(autouse=True)
async def _db_session(db_available):
    if not db_available:
        pytest.skip("Postgres 미기동 (docker compose up -d)")
    yield
    # 테스트마다 이벤트 루프가 새로 뜬다. 이전 루프에 묶인 커넥션이 풀에 남으면
    # 다음 테스트에서 터지므로 매번 풀을 비운다(conftest 의 client 픽스처와 같은 이유).
    await engine.dispose()


async def _articles(concepts, limit=MAX_ARTICLES):
    from app.core.db import SessionLocal

    search = MockSearchProvider()
    async with SessionLocal() as db:
        out = await recommend_articles(db, concepts, UserContext(), search, limit=limit)
    return out, search


async def test_partner_dataset_fills_first_and_search_is_not_called():
    """제휴 매칭만으로 정원이 차면 검색을 아예 부르지 않는다(불필요한 과금·지연 방지)."""
    # 시드에 '기준금리' 태그를 가진 기사가 여러 건 있다.
    articles, search = await _articles(["기준금리", "인플레이션", "환율", "국채금리", "반도체"])

    assert len(articles) == MAX_ARTICLES
    assert all(a.source == "partner" for a in articles)
    assert search.calls == []


async def test_search_fills_only_the_shortfall():
    """제휴에서 못 채운 자리만 검색이 메우고, 정원을 넘기지 않는다."""
    # 시드에 없는 개념이라 제휴 매칭이 0건이다.
    articles, search = await _articles(["양자중력", "초끈이론"])

    assert len(search.calls) == 1
    requested_limit = search.calls[0][1]
    assert requested_limit == MAX_ARTICLES
    assert len(articles) <= MAX_ARTICLES
    assert all(a.source == "search" for a in articles)
    assert all(a.url.startswith("https://") for a in articles)


async def test_explore_limit_is_respected():
    """탐색 탭은 같은 로직을 limit=2 로 재사용한다."""
    articles, _ = await _articles(["양자중력", "초끈이론"], limit=2)
    assert len(articles) <= 2


async def test_no_concepts_means_no_search():
    articles, search = await _articles([])
    assert articles == []
    assert search.calls == []
