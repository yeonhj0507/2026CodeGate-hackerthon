"""탐색 — 고른 키워드 2~3개를 묶어 설명 + 관련 기사 2건 (명세 §5.3 확장).

그래프를 서버가 보관하지 않으므로 로컬앱이 개념명을 함께 보낸다.
설명은 Claude 1회, 기사는 제휴 데이터셋 우선 + 검색 폴백(추천 탭과 같은 경로 재사용).
"""

import asyncio
import logging
import time

from sqlalchemy.ext.asyncio import AsyncSession

from app.domain.llm.base import LlmProvider
from app.domain.schemas import ExploreRequest, ExploreResponse, UserContext
from app.domain.search.base import SearchProvider
from app.domain.thoughtmap import recommend
from app.domain.thoughtmap.merge import normalize_concept

logger = logging.getLogger(__name__)

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

    # 설명과 기사는 서로의 결과를 쓰지 않는다. 둘 다 concepts 만 있으면 되는데
    # 순서대로 기다리면 대기 시간이 **합계**가 된다. 특히 기사 쪽은 제휴 데이터셋이
    # 부족하면 웹 검색 툴을 단 두 번째 Claude 호출까지 하므로(claude_search.py),
    # 직렬로 두면 탐색 탭이 눈에 띄게 느려진다. 함께 돌려 둘 중 긴 쪽으로 만든다.
    #
    # db 세션을 건드리는 건 recommend_articles 뿐이다(AsyncSession 은 동시 사용 불가).
    explanation_task, articles_task = await asyncio.gather(
        llm.explain_concepts(concepts),
        # 추천 탭과 같은 랭킹 로직 재사용 — 제휴 우선, 부족분만 검색.
        recommend.recommend_articles(
            db, concepts, UserContext(), search, limit=EXPLORE_ARTICLES
        ),
        return_exceptions=True,
    )

    # 설명은 이 탭의 본체다. 실패하면 그대로 올린다(직렬일 때와 같은 동작).
    if isinstance(explanation_task, BaseException):
        raise explanation_task
    explanation = explanation_task

    # 기사는 부가 기능이라 실패해도 설명까지 버리지 않는다. 직렬이던 시절에는
    # 여기서 터지면 탐색 전체가 실패했는데, 그건 사용자에게 손해였다.
    if isinstance(articles_task, BaseException):
        logger.warning("탐색 기사 추천 실패(설명만 반환한다): %s", articles_task)
        articles = []
    else:
        articles = articles_task

    result = ExploreResponse(explanation=explanation, articles=articles)
    _cache[key] = (time.time(), result)
    return result
