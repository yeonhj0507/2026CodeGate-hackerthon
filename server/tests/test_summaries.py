"""개념 재요약 대상 선정 규칙 (DB 불필요, LLM 은 mock).

`_attach_summaries` 는 흐름 B 안에 묻혀 있어 test_flow 로만 검증되는데 그쪽은
Postgres 가 떠 있어야 돈다. 대상 선정과 상태 분기는 DB 와 무관하므로 여기서 직접 본다.
"""

import pytest

from app.domain.llm.mock import MockProvider
from app.domain.schemas import (
    STATE_NOT_UNDERSTOOD,
    STATE_UNDERSTOOD,
    STATE_UNKNOWN,
    Graph,
    GraphEdge,
    GraphNode,
)
from app.domain.thoughtmap.service import MAX_SUMMARIES, _attach_summaries


def node(concept, state, *, prereq=False, summary=None):
    return GraphNode(
        id=f"c_{concept}",
        concept=concept,
        state=state,
        isPrereq=prereq,
        summaryMeta=summary,
    )


@pytest.mark.asyncio
async def test_understood_nodes_also_get_a_summary():
    """맞힌 개념에도 설명이 붙는다 — 로컬앱은 상태를 안 따지고 그대로 보여준다."""
    graph = Graph(
        nodes=[
            node("기준금리", STATE_UNDERSTOOD),
            node("실질금리", STATE_NOT_UNDERSTOOD),
        ],
        edges=[GraphEdge(**{"from": "c_실질금리", "to": "c_기준금리"})],
    )

    await _attach_summaries(graph, MockProvider())

    by_concept = {n.concept: n for n in graph.nodes}
    assert by_concept["기준금리"].summaryMeta
    assert by_concept["실질금리"].summaryMeta


@pytest.mark.asyncio
async def test_summary_tone_splits_on_diagnosis():
    """이해완료에 '막혔다'고 쓰면 안 된다. 상태가 프롬프트까지 흘러가는지 본다."""
    graph = Graph(
        nodes=[
            node("환율", STATE_UNDERSTOOD),
            node("통화정책", STATE_NOT_UNDERSTOOD),
        ]
    )

    await _attach_summaries(graph, MockProvider())

    by_concept = {n.concept: n for n in graph.nodes}
    assert "맞힌" in by_concept["환율"].summaryMeta
    assert "막힌" in by_concept["통화정책"].summaryMeta


@pytest.mark.asyncio
async def test_unknown_nodes_are_skipped():
    """추천으로만 등장한 노드는 진단 결과가 없어 할 말이 없다."""
    graph = Graph(nodes=[node("탄소배출권", STATE_UNKNOWN)])

    await _attach_summaries(graph, MockProvider())

    assert graph.nodes[0].summaryMeta is None


@pytest.mark.asyncio
async def test_existing_summary_is_not_regenerated():
    graph = Graph(nodes=[node("기준금리", STATE_UNDERSTOOD, summary="예전 설명")])

    await _attach_summaries(graph, MockProvider())

    assert graph.nodes[0].summaryMeta == "예전 설명"


@pytest.mark.asyncio
async def test_not_understood_wins_the_cap():
    """후보가 MAX_SUMMARIES 를 넘으면 막힌 개념이 먼저다.

    이해완료까지 대상에 넣으면서 후보가 두 배로 늘었다. 잘려서 설명 없이 남는 쪽이
    미이해가 되면 기능의 원래 목적을 잃는다.
    """
    understood = [node(f"안다{i}", STATE_UNDERSTOOD) for i in range(MAX_SUMMARIES)]
    blocked = [node("막혔다", STATE_NOT_UNDERSTOOD)]
    graph = Graph(nodes=understood + blocked)  # 미이해가 목록 맨 뒤에 있어도

    await _attach_summaries(graph, MockProvider())

    by_concept = {n.concept: n for n in graph.nodes}
    assert by_concept["막혔다"].summaryMeta
    # 자리는 MAX_SUMMARIES 개뿐이라 이해완료 하나는 밀려난다.
    filled = sum(1 for n in graph.nodes if n.summaryMeta)
    assert filled == MAX_SUMMARIES
