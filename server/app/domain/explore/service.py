"""탐색 — 고른 키워드 2~3개를 묶어 설명 + 관련 기사 2건 (명세 §5.3 확장).

그래프를 서버가 보관하지 않으므로 로컬앱이 개념명을 함께 보낸다.
설명은 Claude 1회, 기사는 제휴 데이터셋 우선 + 검색 폴백(추천 탭과 같은 경로 재사용).
"""

import time

from sqlalchemy.ext.asyncio import AsyncSession

from app.domain.llm.base import LlmProvider
from app.domain.schemas import ExploreRequest, ExploreResponse, UserContext
from app.domain.search.base import SearchProvider
from app.domain.thoughtmap import recommend
from app.domain.thoughtmap.merge import normalize_concept

EXPLORE_ARTICLES = 2

_CACHE_TTL_SEC = 60 * 30
_cache: dict[str, tuple[float, ExploreResponse]] = {}


def _cache_key(concepts: list[str]) -> str:
    # 고른 순서가 달라도 같은 조합이면 같은 결과를 준다.
    return "|".join(sorted(normalize_concept(c) for c in concepts))


async def explore(
    db: AsyncSession,
    payload: ExploreRequest,
    llm: LlmProvider,
    search: SearchProvider | None = None,
) -> ExploreResponse:
    concepts = [c.strip() for c in payload.conceptTags if c.strip()]
    if not concepts:
        return ExploreResponse(explanation="", articles=[])

    key = _cache_key(concepts)
    hit = _cache.get(key)
    if hit and time.time() - hit[0] < _CACHE_TTL_SEC:
        return hit[1]

    explanation = await llm.explain_concepts(concepts)

    # 추천 탭과 같은 랭킹 로직 재사용 — 제휴 우선, 부족분만 검색.
    articles = await recommend.recommend_articles(
        db, concepts, UserContext(), search, limit=EXPLORE_ARTICLES
    )

    result = ExploreResponse(explanation=explanation, articles=articles)
    _cache[key] = (time.time(), result)
    return result
