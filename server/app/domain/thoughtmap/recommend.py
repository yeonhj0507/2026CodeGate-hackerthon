"""추천 생성 (명세 §4.4).

- 모를 것 같은 개념: 미이해 노드와 그 인접(선행) 개념 중 아직 확인되지 않은 것.
- 읽을 만한 기사: 추천 개념 + 사용자 기사 선호 패턴으로 제휴 데이터셋을 랭킹.
"""

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.domain.models import PartnerArticle
from app.domain.schemas import (
    STATE_NOT_UNDERSTOOD,
    STATE_UNKNOWN,
    ArticleRecommendation,
    ConceptRecommendation,
    Graph,
    Recommendations,
    UserContext,
)
from app.domain.thoughtmap.merge import normalize_concept

MAX_CONCEPTS = 8
MAX_ARTICLES = 5


def recommend_concepts(graph: Graph) -> list[ConceptRecommendation]:
    by_id = {n.id: n for n in graph.nodes}
    not_understood = {n.id for n in graph.nodes if n.state == STATE_NOT_UNDERSTOOD}

    # 개념 → (점수, 사유). 점수가 높을수록 먼저 파고들 가치가 있다.
    scored: dict[str, tuple[int, str]] = {}

    def bump(node_id: str, points: int, reason: str) -> None:
        """점수는 누적하고, 사유는 처음 붙은 것(가장 구체적인 것)을 유지한다."""
        if node_id not in by_id:
            return
        score, first_reason = scored.get(node_id, (0, reason))
        scored[node_id] = (score + points, first_reason)

    for edge in graph.edges:
        # from = 선행 개념. 후행을 모른다면 그 선행부터 확인할 가치가 있다.
        if edge.to in not_understood:
            state = by_id[edge.from_].state if edge.from_ in by_id else STATE_UNKNOWN
            if state != STATE_NOT_UNDERSTOOD:
                bump(
                    edge.from_,
                    3 if state == STATE_UNKNOWN else 1,
                    f"'{by_id[edge.to].concept}'을(를) 이해하려면 먼저 짚어야 하는 선행 개념이다.",
                )

    for node_id in not_understood:
        bump(
            node_id,
            2,
            f"진단에서 '{by_id[node_id].concept}'을(를) 놓쳤다. 개념부터 다시 볼 차례다.",
        )

    # 아직 진단되지 않은 개념(unknown)도 후보. 미이해 노드와 이어져 있을수록 우선.
    for node in graph.nodes:
        if node.state == STATE_UNKNOWN and node.id not in scored:
            bump(node.id, 1, "그래프에 들어왔지만 아직 확인해 보지 않은 개념이다.")

    ordered = sorted(scored.items(), key=lambda kv: (-kv[1][0], by_id[kv[0]].concept))
    return [
        ConceptRecommendation(concept=by_id[node_id].concept, reason=reason)
        for node_id, (_, reason) in ordered[:MAX_CONCEPTS]
    ]


async def recommend_articles(
    db: AsyncSession,
    concepts: list[ConceptRecommendation],
    context: UserContext,
) -> list[ArticleRecommendation]:
    rows = (await db.execute(select(PartnerArticle))).scalars().all()
    if not rows:
        return []

    wanted = {normalize_concept(c.concept): rank for rank, c in enumerate(concepts)}
    preferred_categories = {c.strip().lower() for c in context.preferredCategories if c.strip()}
    preferred_keywords = {normalize_concept(k) for k in context.preferredKeywords if k.strip()}

    scored: list[tuple[float, list[str], PartnerArticle]] = []
    for row in rows:
        matched: list[str] = []
        score = 0.0
        for tag in row.concept_tags or []:
            key = normalize_concept(str(tag))
            if key in wanted:
                # 상위 추천 개념일수록 가중.
                score += 5.0 - min(wanted[key], 4) * 0.5
                matched.append(str(tag))
            if key in preferred_keywords:
                score += 1.0
        if (row.category or "").lower() in preferred_categories:
            score += 1.5
        if score > 0:
            scored.append((score, matched, row))

    scored.sort(key=lambda t: (-t[0], t[2].title))
    return [
        ArticleRecommendation(
            title=row.title,
            url=row.url,
            publisher=row.publisher or "",
            summary=row.summary or "",
            matchedConcepts=matched,
        )
        for _, matched, row in scored[:MAX_ARTICLES]
    ]


async def build_recommendations(
    db: AsyncSession, graph: Graph, context: UserContext
) -> Recommendations:
    concepts = recommend_concepts(graph)
    articles = await recommend_articles(db, concepts, context)
    return Recommendations(concepts=concepts, articles=articles)
