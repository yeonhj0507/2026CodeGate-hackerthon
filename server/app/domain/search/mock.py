"""결정론적 검색 목. 키 없이 전 파이프라인이 돌고, 테스트가 과금되지 않는다."""

import hashlib

from app.domain.search.base import FoundArticle


class MockSearchProvider:
    #: 테스트가 "검색이 실제로 불렸는지"를 단언할 수 있게 호출을 기록한다.
    def __init__(self) -> None:
        self.calls: list[tuple[tuple[str, ...], int]] = []

    async def search_articles(self, concepts: list[str], limit: int) -> list[FoundArticle]:
        self.calls.append((tuple(concepts), limit))
        out: list[FoundArticle] = []
        for concept in concepts[:limit]:
            slug = hashlib.sha256(concept.encode("utf-8")).hexdigest()[:10]
            out.append(
                FoundArticle(
                    title=f"{concept} 쉽게 읽기",
                    url=f"https://search.example.com/{slug}",
                    publisher="검색결과",
                    summary=f"{concept}을(를) 다룬 기사입니다.",
                )
            )
        return out[:limit]
