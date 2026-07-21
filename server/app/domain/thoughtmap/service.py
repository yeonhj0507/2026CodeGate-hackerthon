"""지식그래프 업데이트 연산 (명세 §4.4 / 구현계획③ §2.3).

흐름 B의 서버 측 전부: 버퍼 로드 → 병합 → 개인화 요약 흡수 → 추천 → 버퍼 삭제.
"""

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.domain.llm.base import ConceptContext, LlmProvider
from app.domain.models import TempScrap
from app.domain.schemas import (
    STATE_NOT_UNDERSTOOD,
    STATE_UNDERSTOOD,
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
    """**진단된** 노드 중 아직 설명이 없는 것을 LLM 1회 배치 호출로 채운다.

    서버는 기사 원문을 보관하지 않으므로(명세 §4.4 ⚠️) 재요약의 근거는 원문이 아니라
    **개념 관계(선행/후행) + 진단 결과 + 기사 제목**이다. 그 근거를 여기서 조립한다.

    미이해뿐 아니라 이해완료 노드도 대상이다. 로컬앱의 노드 상세는 상태를 따지지 않고
    `summaryMeta` 가 있으면 보여주므로(node_detail_panel), 여기서 채워 보내면 맞힌
    개념에도 설명이 붙는다. 진단되지 않은(unknown) 노드는 제외한다 — 추천으로만 등장한
    노드라 할 말이 "정의"밖에 없고, MAX_SUMMARIES 자리를 축낸다.
    """
    pending = [
        n
        for n in graph.nodes
        if n.state in (STATE_NOT_UNDERSTOOD, STATE_UNDERSTOOD) and not n.summaryMeta
    ]
    # 후보가 두 배로 늘었으므로 MAX_SUMMARIES 에서 잘릴 일이 잦아졌다. 막힌 개념이
    # 맞힌 개념에 밀려 설명 없이 남는 게 최악이라 미이해를 앞에 세운다.
    pending.sort(key=lambda n: n.state != STATE_NOT_UNDERSTOOD)
    targets = pending[:MAX_SUMMARIES]
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
            understood=n.state == STATE_UNDERSTOOD,
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
