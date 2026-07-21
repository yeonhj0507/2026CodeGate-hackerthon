"""추천 도출 규칙 (DB·LLM 불필요).

확장 추천은 그래프 구조만으로 뽑히므로 순수 함수로 규칙을 못 박아 둔다(명세 §4.4).
"""

from app.domain.schemas import (
    STATE_NOT_UNDERSTOOD,
    STATE_UNDERSTOOD,
    STATE_UNKNOWN,
    Graph,
    GraphEdge,
    GraphNode,
)
from app.domain.thoughtmap.recommend import (
    recommend_retry_concepts,
    recommend_gap_concepts,
)


def node(node_id: str, state: str, *, is_prereq: bool = False) -> GraphNode:
    return GraphNode(id=node_id, concept=node_id, state=state, isPrereq=is_prereq)


def edge(prereq: str, parent: str) -> GraphEdge:
    """선행(from) → 후행(to). graph.dart 계약과 같은 방향."""
    return GraphEdge(from_=prereq, to=parent)


def test_retry_signal_recommends_the_unsolved_parent():
    """선행을 이해했는데 원래 주장이 미이해로 남았다면 그 주장에 다시 도전할 때다."""
    graph = Graph(
        nodes=[
            node("기준금리", STATE_NOT_UNDERSTOOD),
            node("통화정책", STATE_UNDERSTOOD, is_prereq=True),
        ],
        edges=[edge("통화정책", "기준금리")],
    )
    out = recommend_retry_concepts(graph)

    assert [(e.conceptId, e.reason) for e in out] == [("기준금리", "retry")]


def test_sibling_signal_recommends_the_other_prereq():
    """같은 상위 개념을 공유하는 형제 중 아직 이해완료가 아닌 것."""
    graph = Graph(
        nodes=[
            node("기준금리", STATE_UNDERSTOOD),
            node("통화정책", STATE_UNDERSTOOD, is_prereq=True),
            node("공개시장운영", STATE_UNKNOWN, is_prereq=True),
        ],
        edges=[edge("통화정책", "기준금리"), edge("공개시장운영", "기준금리")],
    )
    out = recommend_retry_concepts(graph)

    assert [(e.conceptId, e.reason) for e in out] == [("공개시장운영", "sibling")]


def test_retry_comes_before_sibling():
    graph = Graph(
        nodes=[
            node("기준금리", STATE_NOT_UNDERSTOOD),
            node("통화정책", STATE_UNDERSTOOD, is_prereq=True),
            node("공개시장운영", STATE_UNKNOWN, is_prereq=True),
        ],
        edges=[edge("통화정책", "기준금리"), edge("공개시장운영", "기준금리")],
    )
    out = recommend_retry_concepts(graph)

    assert [e.reason for e in out] == ["retry", "sibling"]


def test_cold_start_returns_empty():
    """이해완료가 하나도 없으면 확장 후보가 없다 — 명세 §4.4 가 인정한 한계."""
    graph = Graph(
        nodes=[
            node("기준금리", STATE_NOT_UNDERSTOOD),
            node("통화정책", STATE_NOT_UNDERSTOOD, is_prereq=True),
        ],
        edges=[edge("통화정책", "기준금리")],
    )
    assert recommend_retry_concepts(graph) == []


def test_understood_parent_is_not_recommended():
    """이미 이해완료한 주장은 다시 도전할 대상이 아니다."""
    graph = Graph(
        nodes=[
            node("기준금리", STATE_UNDERSTOOD),
            node("통화정책", STATE_UNDERSTOOD, is_prereq=True),
        ],
        edges=[edge("통화정책", "기준금리")],
    )
    assert recommend_retry_concepts(graph) == []


def test_understood_prereq_is_not_a_gap():
    """이미 이해완료한 개념을 '모를 것 같은 개념'으로 권하면 안 된다.

    그 개념은 결핍이 아니라 확장(형제 신호)의 재료다.
    """
    graph = Graph(
        nodes=[
            node("기준금리", STATE_NOT_UNDERSTOOD),
            node("통화정책", STATE_UNDERSTOOD, is_prereq=True),
        ],
        edges=[edge("통화정책", "기준금리")],
    )
    assert "통화정책" not in {c.conceptId for c in recommend_gap_concepts(graph)}


def test_gap_concepts_carry_node_id():
    graph = Graph(
        nodes=[node("기준금리", STATE_NOT_UNDERSTOOD)],
        edges=[],
    )
    out = recommend_gap_concepts(graph)

    assert out[0].conceptId == "기준금리"
    assert out[0].conceptTag == "기준금리"
    assert out[0].reason
