"""지식그래프 병합 — 순수 함수 (구현계획③ §2.3).

입력: 로컬이 보낸 기존 graph + 서버 버퍼의 스크랩들(오래된 것부터).
출력: 갱신된 graph.

DB·LLM 을 모르는 순수 로직이라 단위 테스트로 규칙을 못 박아 둔다.
"""

import re
import unicodedata
from dataclasses import dataclass, field

from app.domain.schemas import (
    EDGE_PREREQ,
    STATE_NOT_UNDERSTOOD,
    STATE_UNDERSTOOD,
    STATE_UNKNOWN,
    Graph,
    GraphEdge,
    GraphNode,
)

# 개념어 꼬리에 붙어 표기만 흔드는 조사. 정규화로 크로스기사 병합률을 올린다.
#
# 이/가/의/와/과/들 은 일부러 제외했다. "소비자물가"→"소비자물", "민주주의"→"민주주"
# 처럼 명사의 일부를 깎아 서로 다른 개념을 잘못 병합시킨다. 병합 실패(노드 중복)보다
# 오병합(그래프 오염)이 더 나쁘므로, 명사 어미와 겹치지 않는 조사만 제거한다.
_TAIL = re.compile(r"(에서|으로|은|는|을|를)$")
_SPACE = re.compile(r"\s+")


def normalize_concept(concept: str) -> str:
    """노드 id 로 쓸 정규화 키. 표기가 조금 달라도 같은 개념으로 묶기 위함.

    같은 개념이 다른 기사에서 재등장하면 여기서 같은 키가 나와 병합된다
    (명세 §5.1 "크로스기사 노드 연관").
    """
    text = unicodedata.normalize("NFKC", concept).strip().lower()
    text = _SPACE.sub(" ", text)
    text = re.sub(r"[\"'“”‘’()\[\]{}·,.]", "", text)
    if len(text) > 2:
        text = _TAIL.sub("", text)
    return text or concept.strip().lower()


@dataclass
class ScrapInput:
    """DB 행에서 뽑아낸 병합 입력. 오래된 것부터 정렬되어 들어온다."""

    article_title: str
    results: list[dict] = field(default_factory=list)


def merge(graph: Graph, scraps: list[ScrapInput]) -> Graph:
    nodes: dict[str, GraphNode] = {}
    for node in graph.nodes:
        key = normalize_concept(node.id) or node.id
        nodes[key] = node.model_copy(update={"id": key})

    edges: dict[tuple[str, str, str], GraphEdge] = {
        (normalize_concept(e.from_), normalize_concept(e.to), e.type): e.model_copy(
            update={
                "from_": normalize_concept(e.from_),
                "to": normalize_concept(e.to),
            }
        )
        for e in graph.edges
    }

    # 한 번이라도 본문 주장(level 0)으로 출제된 개념. 말단(선행개념) 판정에서 제외된다.
    main_concepts = {n.id for n in nodes.values() if not n.isPrereq and n.state != STATE_UNKNOWN}

    for scrap in scraps:
        # 한 세션 안에서 같은 개념을 여러 번 틀렸다면 미이해로 본다.
        session_state: dict[str, bool] = {}
        for raw in scrap.results:
            concept = (raw.get("conceptTag") or "").strip()
            if not concept:
                continue
            key = normalize_concept(concept)
            level = raw.get("level") or 0
            correct = bool(raw.get("correct"))

            node = _ensure_node(nodes, key, concept)
            _touch_source(node, scrap.article_title)

            # 말단 노드 = 선행 개념어(명세 §5.1). level 0 로 한 번이라도 출제된 개념은
            # 본문 주장이므로 말단이 아니고, 그 판정은 이후 스크랩에도 유지된다.
            if level >= 1:
                node.isPrereq = key not in main_concepts
            else:
                main_concepts.add(key)
                node.isPrereq = False

            session_state[key] = session_state.get(key, True) and correct

            parent = (raw.get("parentConcept") or "").strip()
            if parent:
                parent_key = normalize_concept(parent)
                parent_node = _ensure_node(nodes, parent_key, parent)
                _touch_source(parent_node, scrap.article_title)
                if parent_key != key:
                    # 엣지 방향은 graph.dart 계약(from=선행, to=후행)을 따른다.
                    # 재질문으로 내려간 개념(conceptTag)이 부모 개념(parentConcept)의 선행이다.
                    edge_key = (key, parent_key, EDGE_PREREQ)
                    edges.setdefault(
                        edge_key, GraphEdge(from_=key, to=parent_key, type=EDGE_PREREQ)
                    )

        # 세션 결과를 노드 상태에 반영. 최신 스크랩이 이전 상태를 덮는다
        # (오답 → 이후 정답이면 이해완료로 회복).
        for key, ok in session_state.items():
            nodes[key].state = STATE_UNDERSTOOD if ok else STATE_NOT_UNDERSTOOD

    return Graph(nodes=list(nodes.values()), edges=list(edges.values()))


def _ensure_node(nodes: dict[str, GraphNode], key: str, concept: str) -> GraphNode:
    node = nodes.get(key)
    if node is None:
        node = GraphNode(id=key, concept=concept, state=STATE_UNKNOWN)
        nodes[key] = node
    elif not node.concept:
        node.concept = concept
    return node


def _touch_source(node: GraphNode, article_title: str) -> None:
    """출처 기사 메타. 2개 이상 쌓인 노드가 곧 크로스기사 노드다."""
    if article_title and article_title not in node.sourceArticles:
        node.sourceArticles = [*node.sourceArticles, article_title]
