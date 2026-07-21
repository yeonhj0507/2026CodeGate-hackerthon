"""그래프 병합 규칙 (DB·LLM 불필요)."""

from app.domain.schemas import (
    STATE_NOT_UNDERSTOOD,
    STATE_UNDERSTOOD,
    Graph,
    GraphNode,
)
from app.domain.thoughtmap.merge import ScrapInput, merge, normalize_concept


def result(concept, parent=None, level=0, correct=True):
    return {
        "conceptTag": concept,
        "parentConcept": parent,
        "level": level,
        "correct": correct,
    }


def test_normalize_merges_surface_variants():
    assert normalize_concept("기준금리는") == normalize_concept(" 기준금리 ")
    assert normalize_concept("Base Rate") == normalize_concept("base   rate")
    assert normalize_concept("'환율 전가'") == normalize_concept("환율 전가")


def test_normalize_keeps_noun_endings():
    """명사 어미와 겹치는 조사는 깎지 않는다 — 오병합이 병합 실패보다 나쁘다."""
    assert normalize_concept("소비자물가") == "소비자물가"
    assert normalize_concept("민주주의") == "민주주의"
    assert normalize_concept("국채금리는") == "국채금리"


def test_new_nodes_and_prereq_edge():
    scrap = ScrapInput(
        article_title="금리 기사",
        results=[
            result("기준금리", None, 0, correct=False),
            result("통화정책", "기준금리", 1, correct=False),
            result("중앙은행", "통화정책", 2, correct=True),
        ],
    )
    graph = merge(Graph(), [scrap])

    by_concept = {n.concept: n for n in graph.nodes}
    assert by_concept["기준금리"].state == STATE_NOT_UNDERSTOOD
    assert by_concept["중앙은행"].state == STATE_UNDERSTOOD

    # 말단(선행) 판정: level 0 개념은 말단이 아니다.
    assert by_concept["기준금리"].isPrereq is False
    assert by_concept["통화정책"].isPrereq is True

    # 엣지 방향은 선행 → 후행.
    edges = {(e.from_, e.to) for e in graph.edges}
    assert (normalize_concept("통화정책"), normalize_concept("기준금리")) in edges
    assert (normalize_concept("중앙은행"), normalize_concept("통화정책")) in edges


def test_later_scrap_recovers_state():
    old = ScrapInput("기사1", [result("환율", correct=False)])
    new = ScrapInput("기사2", [result("환율", correct=True)])
    graph = merge(Graph(), [old, new])

    assert graph.nodes[0].state == STATE_UNDERSTOOD
    # 크로스기사 병합: 노드 하나에 출처 기사 둘.
    assert graph.nodes[0].sourceArticles == ["기사1", "기사2"]


def test_wrong_answer_in_same_session_wins():
    scrap = ScrapInput(
        "기사",
        [result("환율", correct=True), result("환율", correct=False)],
    )
    graph = merge(Graph(), [scrap])
    assert graph.nodes[0].state == STATE_NOT_UNDERSTOOD


def test_existing_graph_is_preserved():
    existing = Graph(
        nodes=[
            GraphNode(
                id=normalize_concept("환율"),
                concept="환율",
                state=STATE_UNDERSTOOD,
                sourceArticles=["예전 기사"],
                summaryMeta="예전 설명",
            )
        ]
    )
    graph = merge(existing, [ScrapInput("새 기사", [result("환율", correct=False)])])

    node = graph.nodes[0]
    assert node.state == STATE_NOT_UNDERSTOOD
    assert node.summaryMeta == "예전 설명"
    assert node.sourceArticles == ["예전 기사", "새 기사"]


def test_empty_scraps_returns_graph_unchanged():
    existing = Graph(nodes=[GraphNode(id="환율", concept="환율", state=STATE_UNDERSTOOD)])
    graph = merge(existing, [])
    assert len(graph.nodes) == 1
    assert graph.nodes[0].state == STATE_UNDERSTOOD
