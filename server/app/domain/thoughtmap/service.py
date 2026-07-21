"""지식그래프 업데이트 연산 (명세 §4.4 / 구현계획③ §2.3).

흐름 B의 서버 측 전부: 버퍼 로드 → 병합 → 개인화 요약 흡수 → 추천 → 버퍼 삭제.
"""

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.domain.llm.base import ConceptContext, LlmProvider
from app.domain.models import TempScrap
from app.domain.schemas import (
    STATE_NOT_UNDERSTOOD,
    Graph,
    ThoughtmapUpdateRequest,
    ThoughtmapUpdateResponse,
)
from app.domain.thoughtmap import recommend
from app.domain.thoughtmap.merge import ScrapInput, merge

MAX_SUMMARIES = 12


async def update_thoughtmap(
    db: AsyncSession,
    user_id: str,
    payload: ThoughtmapUpdateRequest,
    llm: LlmProvider,
) -> ThoughtmapUpdateResponse:
    # 1. 미소비 스크랩 로드. 여기서 잡은 id 집합만 삭제 대상이다 — 연산 중 들어온
    #    새 스크랩은 다음 동기화로 미룬다.
    rows = (
        (
            await db.execute(
                select(TempScrap)
                .where(TempScrap.user_id == user_id)
                .order_by(TempScrap.created_at.asc())
            )
        )
        .scalars()
        .all()
    )
    consumed_ids = [row.id for row in rows]

    # 2. 병합 (순수 로직)
    scraps = [
        ScrapInput(
            article_url=r.article_url,
            article_title=r.article_title,
            results=r.results or [],
            relations=r.relations or [],
        )
        for r in rows
    ]
    graph = merge(payload.graph, scraps)

    # 3. 개인화 요약 흡수: 미이해 노드에 보충설명을 붙인다(명세 §4.4).
    await _attach_summaries(graph, llm)

    # 4. 추천 생성
    recommendations = await recommend.build_recommendations(db, graph, payload.userContext)

    # 5. 반영된 버퍼 삭제 (명세 §4.3)
    if consumed_ids:
        await db.execute(delete(TempScrap).where(TempScrap.id.in_(consumed_ids)))
    await db.commit()

    return ThoughtmapUpdateResponse(
        graph=graph,
        recommendations=recommendations,
        consumedScraps=len(consumed_ids),
    )


async def _attach_summaries(graph: Graph, llm: LlmProvider) -> None:
    """미이해 노드 중 아직 설명이 없는 것만 LLM 1회 배치 호출로 채운다.

    서버는 기사 원문을 보관하지 않으므로(명세 §4.4 ⚠️) 재요약의 근거는 원문이 아니라
    **개념 관계(선행/후행) + 진단 결과 + 기사 제목**이다. 그 근거를 여기서 조립한다.
    """
    targets = [
        n
        for n in graph.nodes
        if n.state == STATE_NOT_UNDERSTOOD and not n.summaryMeta
    ][:MAX_SUMMARIES]
    if not targets:
        return

    concept_of = {n.id: n.concept for n in graph.nodes}
    # 엣지는 from=선행 → to=후행. 노드 기준 양쪽 이웃을 모아 둔다.
    prereqs: dict[str, list[str]] = {}
    parents: dict[str, list[str]] = {}
    for edge in graph.edges:
        if edge.from_ in concept_of and edge.to in concept_of:
            prereqs.setdefault(edge.to, []).append(concept_of[edge.from_])
            parents.setdefault(edge.from_, []).append(concept_of[edge.to])

    items = [
        ConceptContext(
            concept=n.concept,
            is_prereq=n.isPrereq,
            parent_concepts=parents.get(n.id, []),
            prereq_concepts=prereqs.get(n.id, []),
            source_titles=[s.title for s in n.sourceArticles if s.title],
        )
        for n in targets
    ]

    summaries = await llm.summarize_concepts(items)
    for node in targets:
        text = summaries.get(node.concept)
        if text:
            node.summaryMeta = text
