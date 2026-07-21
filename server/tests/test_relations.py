"""퀴즈 트리의 선행 관계 병합 (DB·LLM 불필요).

엣지는 원래 `parentConcept` 로만 생겼고, 그건 사용자가 **틀려서** 재질문으로
내려갔을 때만 채워진다. 그래서 다 맞힌 세션에서는 개념이 전부 고립됐고,
`graph.edges` 를 훑는 결핍·확장 추천까지 함께 굶었다.

관계는 출제 시점에 이미 정해진 사실이므로 정오답과 무관하게 반영한다.
"""

from app.domain.schemas import STATE_UNDERSTOOD, STATE_UNKNOWN, Graph
from app.domain.thoughtmap.merge import ScrapInput, merge

URL = "https://news.example.com/ndf"


def result(concept: str, *, correct: bool = True, level: int = 0, parent: str | None = None) -> dict:
    return {
        "conceptTag": concept,
        "parentConcept": parent,
        "level": level,
        "correct": correct,
    }


def scrap(results: list[dict], relations: list[dict]) -> ScrapInput:
    return ScrapInput(
        article_url=URL,
        article_title="NDF 기사",
        results=results,
        relations=relations,
    )


def edge_set(graph: Graph) -> set[tuple[str, str]]:
    """그래프 엣지를 (from, to) 로 훑는다.

    ⚠️ 익스텐션이 보내는 relations 는 {from: 선행, to: 후행} 인데, 그래프 엣지는
    **from=후행 → to=선행** 이다(schemas.GraphEdge). 그래서 아래 기대값은 입력
    relations 와 방향이 뒤집혀 보이는 게 정상이다.
    """
    return {(e.from_, e.to) for e in graph.edges}


def test_all_correct_session_still_gets_edges():
    """이 픽스처가 원래 버그 그 자체 — 다 맞히면 엣지가 0개였다."""
    graph = merge(
        Graph(),
        [
            scrap(
                [result("NDF의 환율 전가 경로", correct=True)],
                [
                    {"from": "환헤지", "to": "NDF의 환율 전가 경로"},
                    {"from": "환율", "to": "환헤지"},
                ],
            )
        ],
    )

    assert edge_set(graph) == {("ndf의 환율 전가 경로", "환헤지"), ("환헤지", "환율")}


def test_relation_only_concepts_enter_as_unknown():
    """아직 문제로 만나지 않은 선행 개념도 노드로 들어오되, 집계를 흔들지 않는다."""
    graph = merge(
        Graph(),
        [scrap([result("환율 전가", correct=True)], [{"from": "환헤지", "to": "환율 전가"}])],
    )

    by_id = {n.id: n for n in graph.nodes}
    assert by_id["환헤지"].state == STATE_UNKNOWN
    # 실제로 푼 개념의 상태는 그대로다.
    assert by_id["환율 전가"].state == STATE_UNDERSTOOD


def test_relation_nodes_carry_the_source_article():
    """보관함이 기사별로 묶으려면 출처가 있어야 한다."""
    graph = merge(
        Graph(),
        [scrap([result("환율 전가")], [{"from": "환헤지", "to": "환율 전가"}])],
    )

    node = next(n for n in graph.nodes if n.id == "환헤지")
    assert [a.url for a in node.sourceArticles] == [URL]


def test_normalizes_both_ends():
    """표기가 흔들려도 노드 병합 키와 같은 규칙을 타야 엣지가 붕 뜨지 않는다."""
    graph = merge(
        Graph(),
        [scrap([result("환율전가")], [{"from": " 환헤지 ", "to": "환율전가"}])],
    )

    ids = {n.id for n in graph.nodes}
    assert edge_set(graph) == {("환율전가", "환헤지")}
    assert {"환헤지", "환율전가"} <= ids


def test_ignores_degenerate_relations():
    graph = merge(
        Graph(),
        [
            scrap(
                [result("환율")],
                [
                    {"from": "환율", "to": "환율"},  # 자기 자신
                    {"from": "", "to": "환율"},  # 빈 값
                    {"from": "환율", "to": ""},
                ],
            )
        ],
    )

    assert edge_set(graph) == set()


def test_does_not_duplicate_the_parent_concept_edge():
    """오답으로 내려간 경로와 트리 관계가 같은 엣지를 가리키면 하나로 남는다."""
    graph = merge(
        Graph(),
        [
            scrap(
                [
                    result("환율 전가", correct=False),
                    result("환헤지", correct=True, level=1, parent="환율 전가"),
                ],
                [{"from": "환헤지", "to": "환율 전가"}],
            )
        ],
    )

    assert len(graph.edges) == 1
    assert edge_set(graph) == {("환율 전가", "환헤지")}


def test_relations_accumulate_across_articles():
    """크로스기사 — 같은 개념이 다른 기사에서 재등장하면 관계가 쌓인다."""
    graph = merge(
        Graph(),
        [
            scrap([result("환율 전가")], [{"from": "환헤지", "to": "환율 전가"}]),
            ScrapInput(
                article_url="https://news.example.com/rate",
                article_title="금리 기사",
                results=[result("기준금리")],
                relations=[{"from": "환헤지", "to": "기준금리"}],
            ),
        ],
    )

    assert edge_set(graph) == {("환율 전가", "환헤지"), ("기준금리", "환헤지")}


def test_missing_relations_is_backward_compatible():
    """구버전 익스텐션은 relations 를 보내지 않는다 — 예전 동작 그대로."""
    graph = merge(Graph(), [ScrapInput(article_url=URL, article_title="t", results=[result("환율")])])

    assert edge_set(graph) == set()
    assert [n.id for n in graph.nodes] == ["환율"]
