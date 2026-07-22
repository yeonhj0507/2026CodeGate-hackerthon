"""NAVER API HUB 의 뉴스 검색으로 기사를 찾는다.

Claude 의 `web_search` 를 대체한다. 같은 일을 시켰을 때 이쪽이 압도적으로 싸고 빠르다.

    web_search : 59초 → 214초 → 533초 (점점 악화), 입력 1만9천 토큰 + 검색 건수 과금
    API HUB    : ~0.3초

느려진 원인은 `allowed_domains` 로 언론사만 훑게 한 것이었다. 후보가 좁아지자 모델이
검색을 반복하며 결과를 통째로 되읽었고, 그 되읽기가 그대로 입력 토큰이 됐다. 애초에
"뉴스만"이 목적이면 뉴스 검색 엔진을 쓰는 게 맞다.

**구 developers.naver.com 방식이 아니다.** 검색 API 는 네이버 클라우드 플랫폼의
NAVER API HUB 로 제공되며, 엔드포인트와 인증 헤더가 다르다.

    구:  https://openapi.naver.com/v1/search/news.json
         X-Naver-Client-Id / X-Naver-Client-Secret
    현:  https://naverapihub.apigw.ntruss.com/search/v1/news
         X-NCP-APIGW-API-KEY-ID / X-NCP-APIGW-API-KEY

응답 본문 구조(`items[].title/originallink/link/description`)는 양쪽이 같다.
구 방식 키로 새 엔드포인트를 부르거나 그 반대면 **둘 다 401 errorCode 024** 라
메시지만으로는 구분되지 않는다 — 실제로 그렇게 한 시간을 잃었다.

추천은 부가 기능이므로 **어떤 실패도 동기화를 막지 않는다** — 예외는 삼키고 빈 목록을 낸다.
"""

import html
import logging
import re

import httpx

from app.core.config import get_settings
from app.domain.search.base import FoundArticle, SearchError
from app.domain.search.news_domains import host_of

logger = logging.getLogger(__name__)

ENDPOINT = "https://naverapihub.apigw.ntruss.com/search/v1/news"
TIMEOUT_SEC = 5.0

_TAG = re.compile(r"<[^>]+>")


def _plain(text: str) -> str:
    """검색어 강조 태그(`<b>`)와 HTML 엔티티를 벗긴다."""
    return html.unescape(_TAG.sub("", text or "")).strip()


class NaverSearchProvider:
    def __init__(self) -> None:
        settings = get_settings()
        self._id = settings.naver_client_id
        self._secret = settings.naver_client_secret

    @property
    def configured(self) -> bool:
        return bool(self._id and self._secret)

    async def search_articles(self, concepts: list[str], limit: int) -> list[FoundArticle]:
        if not concepts or limit <= 0:
            return []
        if not self.configured:
            # 키가 없으면 조용히 넘어간다. 제휴 데이터셋만으로도 추천은 성립한다.
            logger.info("네이버 검색 키 미설정 — 검색 없이 진행")
            return []

        query = " ".join(concepts[:3])
        try:
            async with httpx.AsyncClient(timeout=TIMEOUT_SEC) as client:
                res = await client.get(
                    ENDPOINT,
                    params={"query": query, "display": min(limit * 2, 20), "sort": "sim"},
                    headers={
                        "X-NCP-APIGW-API-KEY-ID": self._id,
                        "X-NCP-APIGW-API-KEY": self._secret,
                    },
                )
                res.raise_for_status()
                items = res.json().get("items", [])
        except Exception as exc:  # noqa: BLE001
            # 결과 0건이 아니라 **호출 실패**다. 빈 목록으로 뭉개지 않고 SearchError
            # 로 알린다 — 호출부(동기화/융합검색)가 삼킬지 표면화할지 정한다.
            logger.warning("네이버 검색 실패: %s", exc)
            raise SearchError(str(exc)) from exc

        found: list[FoundArticle] = []
        seen: set[str] = set()
        for item in items:
            # originallink 가 실제 언론사 주소. 없으면 네이버 뉴스 링크로 대체한다.
            url = (item.get("originallink") or item.get("link") or "").strip()
            title = _plain(item.get("title", ""))
            if not url or not title or url in seen:
                continue
            seen.add(url)
            found.append(
                FoundArticle(
                    title=title,
                    url=url,
                    publisher=host_of(url),
                    summary=_plain(item.get("description", "")),
                )
            )
            if len(found) >= limit:
                break
        return found
