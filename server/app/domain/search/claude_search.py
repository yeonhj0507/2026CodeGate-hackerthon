"""Claude 서버측 web_search 도구로 기사를 찾는다.

별도 검색 API 키가 필요 없다 — 이미 붙어 있는 anthropic SDK 로 끝난다.
결과 블록에서 title/url 을 **기계적으로** 뽑아 쓰고, 모델이 쓴 산문은 쓰지 않는다.

추천은 부가 기능이므로 **어떤 실패도 동기화를 막지 않는다** — 예외는 삼키고 빈 목록을 낸다.
"""

import logging
import time

from app.core.config import get_settings
from app.domain.llm.claude import _client, _log_timing
from app.domain.search.base import FoundArticle
from app.domain.search.news_domains import SEARCHABLE_NEWS_DOMAINS, host_of, is_news

logger = logging.getLogger(__name__)

# Opus 4.8 이 지원하는 최신 변형(동적 필터링 내장). 코드 실행 도구를 따로 선언하면 안 된다.
#
# allowed_domains 로 언론사만 훑게 한다. 이게 없으면 나무위키·네이버 지식백과·블로그가
# 상위를 차지한다. 도구가 이 힌트를 어겨도 _collect 가 한 번 더 거르므로 이중 방어다.
#
# 크롤러를 막아 둔 언론사는 빼야 한다(SEARCHABLE_NEWS_DOMAINS). 하나라도 들어가면
# 400 으로 호출 전체가 죽는다 - 일부만 걸러지는 게 아니다.
WEB_SEARCH_TOOL = {
    "type": "web_search_20260209",
    "name": "web_search",
    "max_uses": 2,
    "allowed_domains": list(SEARCHABLE_NEWS_DOMAINS),
}

SYSTEM = """\
당신은 한국어 뉴스 기사를 찾아 주는 검색 도우미다.

- 주어진 개념어들을 이해하는 데 도움이 되는 **한국어 기사**를 찾는다.
- 백과사전 항목·광고·쇼핑 페이지가 아니라 언론사 기사를 우선한다.
- 찾기만 하면 된다. 긴 설명은 쓰지 마라.
"""


class ClaudeSearchProvider:
    def __init__(self) -> None:
        self._model = get_settings().anthropic_model

    async def search_articles(self, concepts: list[str], limit: int) -> list[FoundArticle]:
        if not concepts or limit <= 0:
            return []

        query = ", ".join(concepts[:5])
        started = time.monotonic()
        try:
            message = await _client().messages.create(
                model=self._model,
                max_tokens=2000,
                system=SYSTEM,
                messages=[
                    {
                        "role": "user",
                        "content": f"다음 개념을 다룬 한국어 기사를 찾아 줘: {query}",
                    }
                ],
                tools=[WEB_SEARCH_TOOL],
                thinking={"type": "disabled"},
                output_config={"effort": "low"},
            )
        except Exception as exc:  # noqa: BLE001 - 추천은 실패해도 동기화를 막지 않는다
            logger.warning("web_search 실패: %s", exc)
            return []

        # 서버측 web_search 는 모델 생성 시간에 검색 왕복까지 얹히므로 tok/s 가 낮게 찍힌다.
        # 탐색 탭이 느릴 때 설명 생성과 이 검색 중 어느 쪽이 오래 걸렸는지 가르는 값이다.
        _log_timing("search", message, time.monotonic() - started)
        return _collect(message, limit)


def _collect(message, limit: int) -> list[FoundArticle]:
    """web_search_tool_result 블록에서 기사만 추려 낸다.

    검색 실패 시 content 는 리스트가 아니라 error 객체다 — 타입을 보고 건너뛴다.
    """
    found: list[FoundArticle] = []
    seen: set[str] = set()

    for block in getattr(message, "content", []):
        if getattr(block, "type", None) != "web_search_tool_result":
            continue
        results = getattr(block, "content", None)
        if not isinstance(results, list):
            logger.warning("web_search 결과 오류: %s", getattr(results, "error_code", results))
            continue

        for item in results:
            url = getattr(item, "url", "") or ""
            title = getattr(item, "title", "") or ""
            if not url or url in seen:
                continue
            seen.add(url)
            # 도구가 allowed_domains 를 어길 수 있다. 여기서 최종적으로 거른다 —
            # "읽을 만한 기사"라고 해 놓고 사전 항목을 보여 주면 안 된다.
            if not is_news(url):
                logger.info("뉴스가 아니라 건너뜀: %s", url)
                continue
            found.append(FoundArticle(title=title or url, url=url, publisher=host_of(url)))
            if len(found) >= limit:
                return found
    return found
