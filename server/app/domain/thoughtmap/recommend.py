"""추천 생성 (명세 §4.4).

네 갈래를 낸다.

- **결핍 보완(gap):** 미이해 노드와 그 인접(선행) 개념 중 아직 확인되지 않은 것.
- **확장(expansion):** 이해한 개념과 같은 기사에서 함께 다뤄지는 **새 개념**. 아직 그래프에 없다.
- **다시 도전(retry):** 선행은 익혔는데 본 주장은 틀린 것. 그래프 구조만으로 뽑는다.
- **읽을 만한 기사:** 위 갈래를 모두 근거로 제휴 데이터셋을 랭킹.

확장과 다시 도전을 나눈 이유: 둘 다 이해완료를 발판 삼지만 확장은 **아직 없는 새 것**,
다시 도전은 **이미 있고 틀린 것**이다. 한 섹션에 섞으면 "확장"이 오답 복기를 가리킨다.
"""

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.domain.models import PartnerArticle
from app.domain.schemas import (
    STATE_NOT_UNDERSTOOD,
    STATE_UNDERSTOOD,
    STATE_UNKNOWN,
    ArticleRecommendation,
    ConceptRecommendation,
    ExpansionConcept,
    Graph,
    RetryConcept,
    Recommendations,
    UserContext,
)
from app.domain.search.base import SearchProvider, get_search_provider
from app.domain.thoughtmap.merge import normalize_concept

MAX_CONCEPTS = 8
# 확장은 지도 위에 임시 노드로 함께 그려진다. 많이 뿌리면 지도가 추천으로 뒤덮여
# 정작 내가 쌓은 개념이 묻히므로 상위 2개만 남긴다. 없으면 없다고 말하는 게 낫다.
MAX_EXPANSION = 2
MAX_RETRY = 5
MAX_ARTICLES = 5


def recommend_gap_concepts(graph: Graph) -> list[ConceptRecommendation]:
    """모를 것 같은 개념 — 미이해를 메우는 방향."""
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
        # to = 선행 개념(from=후행). 후행을 모른다면 그 선행부터 확인할 가치가 있다.
        # 단 **이미 이해완료한 선행은 결핍이 아니다** — 그건 확장 추천(형제 신호) 소관이다.
        if edge.from_ in not_understood:
            state = by_id[edge.to].state if edge.to in by_id else STATE_UNKNOWN
            if state == STATE_UNKNOWN:
                bump(
                    edge.to,
                    3,
                    f"'{by_id[edge.from_].concept}'을(를) 이해하려면 먼저 짚어야 하는 선행 개념이다.",
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
        ConceptRecommendation(
            conceptId=node_id, conceptTag=by_id[node_id].concept, reason=reason
        )
        for node_id, (_, reason) in ordered[:MAX_CONCEPTS]
    ]


def recommend_retry_concepts(graph: Graph) -> list[RetryConcept]:
    """다시 도전할 개념 — 오답 되짚기 (명세 §4.4, 구현계획③ §2.3-5).

    두 신호를 쓰며 **Claude 호출이 없다**. 순수 그래프 쿼리다.

    1. 재도전(주): 엣지 `C→M` 에서 C(선행)는 이해완료인데 M(후행)이 미이해로 남은 경우.
       오답 → 선행으로 내려가 선행만 맞힌 케이스를 되짚어 "이제 M에 다시 도전"을 권한다.
    2. 형제(보조): 같은 후행 M 을 공유하는 선행들 중 하나가 이해완료라면, 아직 이해완료가
       아닌 나머지 형제를 권한다.

    **확장 추천과 분리돼 있다.** 둘 다 이해완료를 발판 삼지만 이쪽은 이미 그래프에 있고
    틀린 것이고, 확장은 아직 그래프에 없는 새 개념이다([recommend_expansion_concepts]).

    오답·역탐색 이력이 없는 초반(콜드스타트)에는 빈 목록이 나오며, 그것이 정상 동작이다.
    """
    by_id = {n.id: n for n in graph.nodes}

    def state_of(node_id: str) -> str | None:
        node = by_id.get(node_id)
        return node.state if node else None

    picked: dict[str, RetryConcept] = {}

    # (1) 재도전 — 주 신호라 먼저 채운다.
    #     엣지는 from=후행 → to=선행. 선행을 이미 이해했는데 후행이 미이해면
    #     "선행을 뚫었으니 원래 막혔던 주장에 다시 도전하라"가 된다.
    for edge in graph.edges:
        if state_of(edge.to) == STATE_UNDERSTOOD and state_of(edge.from_) == STATE_NOT_UNDERSTOOD:
            picked.setdefault(
                edge.from_,
                RetryConcept(
                    conceptId=edge.from_,
                    conceptTag=by_id[edge.from_].concept,
                    reason="retry",
                ),
            )

    # (2) 형제 — 후행별로 선행을 모아, 이해완료가 하나라도 있으면 나머지를 권한다.
    prereqs_by_parent: dict[str, list[str]] = {}
    for edge in graph.edges:
        if edge.from_ in by_id and edge.to in by_id:
            prereqs_by_parent.setdefault(edge.from_, []).append(edge.to)

    for siblings in prereqs_by_parent.values():
        if not any(state_of(s) == STATE_UNDERSTOOD for s in siblings):
            continue
        for sibling in siblings:
            if state_of(sibling) != STATE_UNDERSTOOD:
                picked.setdefault(
                    sibling,
                    RetryConcept(
                        conceptId=sibling,
                        conceptTag=by_id[sibling].concept,
                        reason="sibling",
                    ),
                )

    # 재도전이 먼저 오도록 정렬한 뒤 상한을 건다.
    ordered = sorted(picked.values(), key=lambda e: (e.reason != "retry", e.conceptTag))
    return ordered[:MAX_RETRY]


async def recommend_expansion_concepts(
    db: AsyncSession, graph: Graph
) -> list[ExpansionConcept]:
    """확장 개념 — **아는 것에서 뻗어나가는 새 키워드**.

    제휴 기사의 `concept_tags` 를 이웃 관계로 쓴다. 내가 이해완료한 개념이 들어 있는
    기사를 찾고, 그 기사가 함께 다루는 개념 중 **아직 내 그래프에 없는 것**을 권한다.
    "같은 기사에서 함께 설명되는 개념이면 다음에 알 만하다"는 가정이다.

    LLM 호출이 없다(명세 §4.4 "Claude 자유 생성 없음"). 순수 쿼리다.

    그래프 안에서 뽑는 신호는 쓸 수 없었다. 관계 방향이 선행→후행이라 `unknown` 노드는
    거의 항상 **아래쪽(더 깊은 선행)**에 생기고, 그러면 "아는 것 위로 한 걸음"이 아니라
    "아는 것 아래로 파고들기"가 된다. 그건 결핍 보완이 이미 하는 일이다.

    제휴 데이터셋이 사용자의 관심 주제를 못 덮으면 빈 목록이 나온다. 그때는 화면이
    "아직 추천할 키워드가 없어요"로 남으며, 그것이 정상 동작이다.
    """
    understood = {n.id for n in graph.nodes if n.state == STATE_UNDERSTOOD}
    if not understood:
        return []

    known = {n.id for n in graph.nodes}
    rows = (await db.execute(select(PartnerArticle))).scalars().all()

    # 새 개념 → (동시 등장 횟수, 근거가 된 내 개념들, 표기, 가장 잘 맞는 기사)
    score: dict[str, int] = {}
    via: dict[str, list[str]] = {}
    label: dict[str, str] = {}
    # 겹치는 개념이 가장 많은 기사를 그 개념의 출처로 삼는다. 같으면 먼저 본 것을 둔다.
    best: dict[str, tuple[int, PartnerArticle]] = {}

    for row in rows:
        tags = [str(t) for t in (row.concept_tags or [])]
        keyed = [(normalize_concept(t), t) for t in tags]
        mine = [key for key, _ in keyed if key in understood]
        if not mine:
            continue
        for key, tag in keyed:
            # 이미 그래프에 있으면 "새 키워드"가 아니다.
            if key in known:
                continue
            score[key] = score.get(key, 0) + len(mine)
            label.setdefault(key, tag)
            for m in mine:
                if m not in via.setdefault(key, []):
                    via[key].append(m)
            if key not in best or len(mine) > best[key][0]:
                best[key] = (len(mine), row)

    ordered = sorted(score.items(), key=lambda kv: (-kv[1], label[kv[0]]))
    out: list[ExpansionConcept] = []
    for key, _ in ordered[:MAX_EXPANSION]:
        article = best[key][1]
        out.append(
            ExpansionConcept(
                conceptId=key,
                conceptTag=label[key],
                reason="neighbor",
                viaConcepts=via[key],
                articleTitle=article.title,
                articleUrl=article.url,
            )
        )
    return out


async def recommend_articles(
    db: AsyncSession,
    concepts: list[str],
    context: UserContext,
    search: SearchProvider | None = None,
    limit: int = MAX_ARTICLES,
) -> list[ArticleRecommendation]:
    """읽을 만한 기사 — 결핍 보완 + 확장 개념 모두를 근거로 랭킹한다(명세 §4.4).

    제휴 데이터셋을 먼저 채우고, 모자란 자리만 웹 검색으로 보충한다.
    탐색 탭은 같은 로직을 `limit=2` 로 재사용한다.
    """
    rows = (await db.execute(select(PartnerArticle))).scalars().all()
    if not rows:
        return []

    wanted = {normalize_concept(c): rank for rank, c in enumerate(concepts)}
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
    partner = [
        ArticleRecommendation(
            title=row.title,
            url=row.url,
            publisher=row.publisher or "",
            summary=row.summary or "",
            matchedConcepts=matched,
            source="partner",
        )
        for _, matched, row in scored[:limit]
    ]

    # 제휴 데이터셋이 먼저다(명세 §4.4). 모자란 자리만 웹 검색으로 메운다.
    shortfall = limit - len(partner)
    if shortfall <= 0 or not concepts:
        return partner

    taken = {a.url for a in partner}
    found = await (search or get_search_provider()).search_articles(concepts, shortfall)
    for item in found:
        if item.url in taken:
            continue
        taken.add(item.url)
        partner.append(
            ArticleRecommendation(
                title=item.title,
                url=item.url,
                publisher=item.publisher,
                summary=item.summary,
                matchedConcepts=concepts[:1],
                source="search",
            )
        )
    return partner[:limit]


async def build_recommendations(
    db: AsyncSession,
    graph: Graph,
    context: UserContext,
    search: SearchProvider | None = None,
) -> Recommendations:
    expansion = await recommend_expansion_concepts(db, graph)
    retry = recommend_retry_concepts(graph)

    # 같은 개념이 두 섹션에 동시에 뜨면 사용자가 혼란스럽다. 재도전 쪽 안내가 더 구체적이므로
    # (무엇을 발판으로 어디로 가라) 겹치는 개념은 결핍 목록에서 뺀다.
    # 확장은 그래프에 없는 개념만 담으므로 결핍과 겹칠 일이 없다.
    retry_ids = {e.conceptId for e in retry}
    gap = [c for c in recommend_gap_concepts(graph) if c.conceptId not in retry_ids]

    articles = await recommend_articles(
        db,
        [c.conceptTag for c in gap]
        + [e.conceptTag for e in retry]
        + [e.conceptTag for e in expansion],
        context,
        search,
    )
    return Recommendations(
        gapConcepts=gap,
        expansionConcepts=expansion,
        retryConcepts=retry,
        articles=articles,
    )
