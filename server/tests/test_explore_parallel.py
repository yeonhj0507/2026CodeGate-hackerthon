"""탐색 탭의 설명·기사 동시 실행 (DB·LLM 불필요).

`tests/test_explore.py` 는 Postgres 가 있어야 도는 계약 테스트다. 여기서 보는 건
계약이 아니라 **실행 순서**라 DB 없이 스텁으로 확인한다.

"빨라졌다"를 시간으로 재면 CI 에서 흔들린다. 대신 한쪽이 끝나기 전에 다른 쪽이
시작했는지를 직접 관찰한다 — 직렬이면 절대 관찰될 수 없는 사실이다.
"""

import asyncio

import pytest

from app.domain.explore import service
from app.domain.schemas import ExploreRequest


class _Llm:
    """설명이 끝나기 전에 기사 쪽이 시작했는지 기록하는 스텁."""

    def __init__(self, started: asyncio.Event, saw_articles_start: list[bool], articles_started: asyncio.Event):
        self._started = started
        self._saw = saw_articles_start
        self._articles_started = articles_started

    async def explain_concepts(self, concepts):
        self._started.set()
        # 기사 쪽이 먼저 시작하기를 잠깐 기다려 본다. 직렬이라면 영영 오지 않는다.
        try:
            await asyncio.wait_for(self._articles_started.wait(), timeout=1.0)
            self._saw.append(True)
        except asyncio.TimeoutError:
            self._saw.append(False)
        return "묶음 설명"


@pytest.fixture(autouse=True)
def _clear_cache():
    service._cache.clear()
    yield
    service._cache.clear()


@pytest.mark.asyncio
async def test_explanation_and_articles_run_concurrently(monkeypatch):
    llm_started = asyncio.Event()
    articles_started = asyncio.Event()
    overlapped: list[bool] = []

    async def fake_articles(db, concepts, context, search, limit):
        articles_started.set()
        await llm_started.wait()  # 설명 쪽도 이미 돌고 있어야 한다
        return []

    monkeypatch.setattr(service.recommend, "recommend_articles", fake_articles)

    result = await service.explore(
        db=None,
        payload=ExploreRequest(conceptIds=["a"], conceptTags=["기준금리"]),
        llm=_Llm(llm_started, overlapped, articles_started),
    )

    assert result.explanation == "묶음 설명"
    assert overlapped == [True], "설명이 끝나기 전에 기사 조회가 시작되지 않았다 = 아직 직렬"


@pytest.mark.asyncio
async def test_article_failure_still_returns_explanation(monkeypatch):
    """기사는 부가 기능이다. 실패해도 설명까지 버리지 않는다."""

    async def boom(db, concepts, context, search, limit):
        raise RuntimeError("검색 서버 down")

    class _Ok:
        async def explain_concepts(self, concepts):
            return "설명은 살아 있다"

    monkeypatch.setattr(service.recommend, "recommend_articles", boom)

    result = await service.explore(
        db=None,
        payload=ExploreRequest(conceptIds=["a"], conceptTags=["기준금리"]),
        llm=_Ok(),
    )

    assert result.explanation == "설명은 살아 있다"
    assert result.articles == []


@pytest.mark.asyncio
async def test_explanation_failure_propagates(monkeypatch):
    """설명은 이 탭의 본체다. 직렬이던 시절과 같이 그대로 올린다."""

    async def no_articles(db, concepts, context, search, limit):
        return []

    class _Broken:
        async def explain_concepts(self, concepts):
            raise RuntimeError("LLM down")

    monkeypatch.setattr(service.recommend, "recommend_articles", no_articles)

    with pytest.raises(RuntimeError, match="LLM down"):
        await service.explore(
            db=None,
            payload=ExploreRequest(conceptIds=["a"], conceptTags=["기준금리"]),
            llm=_Broken(),
        )


@pytest.mark.asyncio
async def test_empty_concepts_skips_both_calls(monkeypatch):
    """개념이 없으면 LLM 도 DB 도 건드리지 않는다(기존 동작 유지)."""

    async def fail(*a, **kw):
        raise AssertionError("불려서는 안 된다")

    class _Fail:
        async def explain_concepts(self, concepts):
            raise AssertionError("불려서는 안 된다")

    monkeypatch.setattr(service.recommend, "recommend_articles", fail)

    result = await service.explore(
        db=None,
        payload=ExploreRequest(conceptIds=[], conceptTags=["  "]),
        llm=_Fail(),
    )

    assert result.explanation == ""
    assert result.articles == []
