"""확장 개념 — 아는 것에서 뻗어나가는 **새** 키워드.

원래 확장 추천은 재도전·형제 신호였는데, 둘 다 **이미 그래프에 있는** 노드만 골랐다.
그래서 화면에 "확장 개념"이라는 이름으로 자기가 틀렸던 개념이 떴다. 이름과 내용이
어긋난 것이라 두 갈래를 나눴다 — 이 파일은 새 쪽(제휴 기사 이웃)을 검증한다.

DB 를 쓰지만 LLM 은 쓰지 않는다(명세 §4.4 "Claude 자유 생성 없음").
"""

import pytest
import pytest_asyncio
from sqlalchemy import delete

from app.core.db import SessionLocal, engine
from app.domain.models import PartnerArticle
from app.domain.schemas import (
    STATE_NOT_UNDERSTOOD,
    STATE_UNDERSTOOD,
    STATE_UNKNOWN,
    Graph,
    GraphNode,
)
from app.domain.thoughtmap.recommend import recommend_expansion_concepts

pytestmark = pytest.mark.db


def node(concept: str, state: str) -> GraphNode:
    return GraphNode(id=concept, concept=concept, state=state, isPrereq=False)


# 이 테스트만 쓰는 기사 URL 접두사. 시드 데이터를 건드리지 않기 위한 표식이다.
_MARK = "https://expansion.test/"


@pytest_asyncio.fixture(autouse=True)
async def _isolated_articles(db_available):
    """제휴 기사 테이블을 **비우지 않는다.**

    처음엔 delete-all 로 시작했는데, 그러면 `scripts/seed.py` 로 넣어 둔 시드가
    사라져 뒤에 도는 test_flow·test_article_fallback 이 무더기로 깨졌다(실제로 겪음).
    대신 이 테스트가 넣은 행만 표식으로 골라 지우고, 그래프에는 시드 개념과 겹치지
    않는 개념어만 쓴다.
    """
    if not db_available:
        pytest.skip("Postgres 미기동 (docker compose up -d)")
    yield
    async with SessionLocal() as db:
        await db.execute(delete(PartnerArticle).where(PartnerArticle.url.startswith(_MARK)))
        await db.commit()
    # 테스트마다 이벤트 루프가 새로 뜬다 — 이전 루프에 묶인 커넥션을 비운다.
    await engine.dispose()


async def seed(*articles: tuple[str, list[str]]) -> None:
    async with SessionLocal() as db:
        for title, tags in articles:
            db.add(
                PartnerArticle(
                    title=title,
                    url=f"{_MARK}{title}",
                    concept_tags=tags,
                )
            )
        await db.commit()


async def expand(graph: Graph):
    async with SessionLocal() as db:
        return await recommend_expansion_concepts(db, graph)


async def test_recommends_concepts_that_share_an_article_with_what_i_know():
    await seed(("테스트 기사", ["조랑말금리", "조랑말환율", "조랑말물가"]))

    out = await expand(Graph(nodes=[node("조랑말금리", STATE_UNDERSTOOD)]))

    assert {e.conceptTag for e in out} == {"조랑말환율", "조랑말물가"}
    assert all(e.reason == "neighbor" for e in out)


async def test_carries_the_reason_it_was_picked():
    """무엇을 발판으로 데려왔는지 알아야 화면이 이유를 설명할 수 있다."""
    await seed(("테스트 기사", ["조랑말금리", "조랑말환율"]))

    out = await expand(Graph(nodes=[node("조랑말금리", STATE_UNDERSTOOD)]))

    assert out[0].viaConcepts == ["조랑말금리"]


async def test_carries_the_article_the_concept_appeared_in():
    """카드에서 바로 읽으러 갈 수 있어야 한다 — 낱말만 던지면 다음 행동이 없다."""
    await seed(("테스트 기사", ["조랑말금리", "조랑말환율"]))

    out = await expand(Graph(nodes=[node("조랑말금리", STATE_UNDERSTOOD)]))

    assert out[0].articleTitle == "테스트 기사"
    assert out[0].articleUrl.startswith(_MARK)


async def test_picks_the_article_that_overlaps_most():
    """같은 개념이 여러 기사에 있으면 내 개념과 가장 많이 겹치는 기사를 준다."""
    await seed(
        ("스치는 기사", ["조랑말금리", "조랑말환율"]),
        ("맞춤 기사", ["조랑말금리", "조랑말채권", "조랑말환율"]),
    )

    out = await expand(
        Graph(nodes=[node("조랑말금리", STATE_UNDERSTOOD), node("조랑말채권", STATE_UNDERSTOOD)])
    )

    picked = next(e for e in out if e.conceptTag == "조랑말환율")
    assert picked.articleTitle == "맞춤 기사"


async def test_never_recommends_something_already_in_the_graph():
    """확장은 '새 키워드'다. 이미 아는 것도, 틀린 것도, 아직 안 본 것도 제외된다."""
    await seed(("테스트 기사", ["조랑말금리", "조랑말환율", "조랑말물가", "조랑말채권"]))

    out = await expand(
        Graph(
            nodes=[
                node("조랑말금리", STATE_UNDERSTOOD),
                node("조랑말환율", STATE_NOT_UNDERSTOOD),
                node("조랑말물가", STATE_UNKNOWN),
            ]
        )
    )

    assert {e.conceptTag for e in out} == {"조랑말채권"}


async def test_ignores_articles_that_do_not_touch_my_concepts():
    await seed(
        ("테스트 기사", ["조랑말금리", "조랑말환율"]),
        ("남의 기사", ["당나귀칩", "당나귀규제"]),
    )

    out = await expand(Graph(nodes=[node("조랑말금리", STATE_UNDERSTOOD)]))

    assert {e.conceptTag for e in out} == {"조랑말환율"}


async def test_more_shared_articles_ranks_higher():
    await seed(
        ("기사1", ["조랑말금리", "조랑말환율"]),
        ("기사2", ["조랑말채권", "조랑말환율"]),
        ("기사3", ["조랑말금리", "조랑말수지"]),
    )

    out = await expand(
        Graph(nodes=[node("조랑말금리", STATE_UNDERSTOOD), node("조랑말채권", STATE_UNDERSTOOD)])
    )

    # 수입물가는 두 기사에서, 무역수지는 한 기사에서 걸린다.
    assert out[0].conceptTag == "조랑말환율"
    assert out[0].viaConcepts == ["조랑말금리", "조랑말채권"]


async def test_understood_only_counts():
    """미이해·미확인 개념은 발판이 될 수 없다 — '아는 것에서' 뻗어나가는 것이다."""
    await seed(("테스트 기사", ["조랑말금리", "조랑말환율"]))

    assert await expand(Graph(nodes=[node("조랑말금리", STATE_NOT_UNDERSTOOD)])) == []
    assert await expand(Graph(nodes=[node("조랑말금리", STATE_UNKNOWN)])) == []


async def test_empty_when_dataset_does_not_cover_my_topics():
    """제휴 데이터셋이 내 주제를 못 덮으면 빈 목록 — 화면은 안내 문구로 남는다."""
    await seed(("남의 기사", ["당나귀칩", "당나귀규제"]))

    assert await expand(Graph(nodes=[node("조랑말금리", STATE_UNDERSTOOD)])) == []


async def test_empty_graph_makes_no_call():
    assert await expand(Graph()) == []
