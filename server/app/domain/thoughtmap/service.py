"""지식그래프 업데이트 연산 (명세 §4.4 / 구현계획③ §2.3).

흐름 B의 서버 측 전부: 버퍼 로드 → 병합 → 개인화 요약 흡수 → 추천 → 버퍼 삭제.
"""

import asyncio

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

    # 3·4. 개인화 요약(명세 §4.4)과 추천을 **동시에** 돌린다.
    #
    # 둘 다 LLM 을 타고 각각 20~60초가 걸리는데, 순서대로 하면 그 합이 그대로
    # 응답 시간이 되어 로컬앱의 receiveTimeout 을 넘긴다. 넘기면 단순히 느린 게
    # 아니라 **스크랩이 소실된다** — 서버는 5번에서 버퍼를 지우고 커밋하는데
    # 클라이언트는 결과를 못 받기 때문이다.
    #
    # 서로 기다릴 이유가 없다. 재요약은 노드에 summaryMeta 만 덧붙이고, 추천은
    # 그 필드를 읽지 않는다(노드 id·상태·개념어와 엣지만 본다). 같은 세션(db)을
    # 동시에 쓰지도 않는다 — 재요약은 DB 를 건드리지 않는다.
    _, recommendations = await asyncio.gather(
        _attach_summaries(graph, llm),
        recommend.build_recommendations(db, graph, payload.userContext),
    )

    # 5. **버퍼는 아직 지우지 않는다.**
    #
    # 예전에는 여기서 지우고 커밋했는데, 클라이언트가 응답을 못 받으면(타임아웃·
    # 네트워크 순단·앱 종료) 진단 결과가 서버에서도 로컬에서도 사라졌다. 서버는
    # 응답을 다 만들었으니 삭제까지 끝내고, 클라이언트는 아무것도 못 받은 상태가
    # 되기 때문이다. 실제로 QA 중 한 세션이 통째로 날아갔다.
    #
    # 이제 id 만 돌려주고, 로컬 반영을 마친 클라이언트가 `/thoughtmap/ack` 로
    # 알려줄 때 지운다(명세 §4.3 의 "소비" 시점을 클라이언트 확인 뒤로 미룬 것).
    return ThoughtmapUpdateResponse(
        graph=graph,
        recommendations=recommendations,
        consumedScraps=len(consumed_ids),
        consumedScrapIds=consumed_ids,
    )


async def ack_scraps(db: AsyncSession, user_id: str, scrap_ids: list[str]) -> int:
    """로컬 반영이 끝난 스크랩을 버퍼에서 지운다.

    `user_id` 로 한 번 더 좁힌다 — 남의 id 를 보내 지우게 두지 않는다.
    이미 지워진 id 가 섞여 와도 그냥 0건이 더 지워질 뿐이라 재시도가 안전하다.
    """
    if not scrap_ids:
        return 0

    result = await db.execute(
        delete(TempScrap).where(
            TempScrap.user_id == user_id, TempScrap.id.in_(scrap_ids)
        )
    )
    await db.commit()
    return result.rowcount or 0


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
    # 엣지는 from=후행 → to=선행(schemas.GraphEdge). 노드 기준 양쪽 이웃을 모아 둔다.
    prereqs: dict[str, list[str]] = {}
    parents: dict[str, list[str]] = {}
    for edge in graph.edges:
        if edge.from_ in concept_of and edge.to in concept_of:
            prereqs.setdefault(edge.from_, []).append(concept_of[edge.to])
            parents.setdefault(edge.to, []).append(concept_of[edge.from_])

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
