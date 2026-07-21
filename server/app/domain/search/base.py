"""기사 검색 프로바이더 경계.

제휴 데이터셋(`partner_articles`)이 **먼저**이고, 거기서 채우지 못한 자리만 웹 검색으로
메운다(명세 §4.4 확정 소스를 유지하면서 커버리지만 넓히는 절충).

`llm/base.py` 와 같은 패턴 — `SEARCH_PROVIDER` 대신 `LLM_PROVIDER` 를 그대로 따라간다.
mock 이면 검색도 mock 이라 테스트가 결정론을 유지하고 과금되지 않는다.
"""

from dataclasses import dataclass
from typing import Protocol

from app.core.config import get_settings


@dataclass
class FoundArticle:
    """검색으로 찾은 기사 1건. 제휴 데이터셋 행과 같은 자리에 놓이도록 정규화된 형태."""

    title: str
    url: str
    publisher: str = ""
    summary: str = ""


class SearchProvider(Protocol):
    async def search_articles(self, concepts: list[str], limit: int) -> list[FoundArticle]:
        """개념어들과 관련된 한국어 기사를 찾는다. 실패 시 빈 목록(추천은 부가 기능이다)."""
        ...


def get_search_provider() -> SearchProvider:
    """실서버에서는 네이버 뉴스 검색을 쓴다.

    Claude 의 `web_search` 로도 되지만 호출당 수 분·입력 1만9천 토큰이 들어
    동기화 응답 시간과 비용을 혼자 지배했다(naver_search.py 주석 참고). 뉴스
    검색은 전용 API 가 훨씬 싸고 빠르므로 그쪽을 기본으로 둔다.

    키가 없으면 검색 없이 제휴 데이터셋만 쓴다 — 프로바이더가 빈 목록을 낸다.
    """
    if get_settings().llm_provider == "claude":
        from app.domain.search.naver_search import NaverSearchProvider

        return NaverSearchProvider()

    from app.domain.search.mock import MockSearchProvider

    return MockSearchProvider()
