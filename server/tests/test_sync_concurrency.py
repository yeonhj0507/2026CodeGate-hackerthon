"""동기화가 재요약과 추천을 **동시에** 돌리는지 (Postgres 필요, LLM 은 가짜).

순서대로 돌리면 두 LLM 구간의 시간이 그대로 더해져 로컬앱 receiveTimeout 을 넘긴다.
그런데 넘기면 단순히 느린 게 아니라 **스크랩이 소실된다** — 서버는 응답을 다 만든 뒤
버퍼를 지우고 커밋하는데(service.py 5단계) 클라이언트는 결과를 못 받기 때문이다.
실제로 검색이 59초를 먹으면서 그 일이 벌어졌다.

그래서 "빨라졌는가"가 아니라 **"겹쳐서 도는가"**를 직접 관찰한다.
"""

import asyncio

import pytest
import pytest_asyncio

from app.core.db import SessionLocal, engine
from app.domain.llm.base import ConceptContext
from app.domain.llm.mock import MockProvider
from app.domain.schemas import (
    STATE_NOT_UNDERSTOOD,
    Graph,
    GraphNode,
    ThoughtmapUpdateRequest,
)
from app.domain.thoughtmap import recommend
from app.domain.thoughtmap.service import update_thoughtmap

pytestmark = pytest.mark.db

USER = "concurrency-test-user"


@pytest_asyncio.fixture(autouse=True)
async def _db(db_available):
    if not db_available:
        pytest.skip("Postgres 미기동 (docker compose up -d)")
    yield
    await engine.dispose()


class _BlockingProvider(MockProvider):
    """재요약을 붙잡아 창(window)을 열어 둔다. 그 사이에 추천이 시작되면 겹친 것."""

    def __init__(self) -> None:
        self.summarizing = asyncio.Event()
        self.may_finish = asyncio.Event()

    async def summarize_concepts(self, items: list[ConceptContext]) -> dict[str, str]:
        self.summarizing.set()
        await self.may_finish.wait()
        return await super().summarize_concepts(items)


async def test_recommendations_start_before_summaries_finish(monkeypatch):
    """**재요약이 아직 안 끝났는데 추천이 시작되는가**를 직접 본다.

    처음엔 "재요약이 돌던 중에 결과가 나온다" 정도로 짰다가, 순차 구현으로
    되돌려도 그대로 통과해서 못 쓸 테스트임이 드러났다. 테스트 자신의 gather 가
    동시성을 만들어 주고 있었다. 그래서 추천 쪽 시작 시점에 직접 표식을 단다.
    """
    llm = _BlockingProvider()
    recommending = asyncio.Event()

    original = recommend.build_recommendations

    async def spy(*args, **kwargs):
        recommending.set()
        return await original(*args, **kwargs)

    monkeypatch.setattr(recommend, "build_recommendations", spy)

    graph = Graph(
        nodes=[
            GraphNode(
                id="환율", concept="환율", state=STATE_NOT_UNDERSTOOD, isPrereq=False
            )
        ]
    )

    async with SessionLocal() as db:
        task = asyncio.create_task(
            update_thoughtmap(db, USER, ThoughtmapUpdateRequest(graph=graph), llm)
        )

        await asyncio.wait_for(llm.summarizing.wait(), timeout=5)
        # 여기서 재요약은 아직 붙잡혀 있다. 순차 구현이라면 추천은 시작조차 못 한다.
        await asyncio.wait_for(recommending.wait(), timeout=5)

        llm.may_finish.set()
        result = await asyncio.wait_for(task, timeout=10)

    # 겹쳐 돌렸다고 결과가 비면 안 된다.
    node = next(n for n in result.graph.nodes if n.id == "환율")
    assert node.summaryMeta
    assert result.recommendations is not None
