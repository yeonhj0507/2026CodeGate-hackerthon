"""LLM 프로바이더 경계.

퀴즈 생성과 개념 재요약만 LLM을 쓴다. 채점은 서버 미개입(객관식·클라이언트).
`LLM_PROVIDER` 환경변수로 mock/claude 를 갈아끼운다.
"""

from typing import Protocol

from app.core.settings import get_settings


class LlmProvider(Protocol):
    async def generate_quiz(self, title: str, paragraphs: list[str]) -> dict:
        """`{"quiz": [...]}` 형태의 원시 dict 를 반환. 검증은 호출부가 한다."""
        ...

    async def summarize_concepts(
        self, concepts: list[str], article_titles: dict[str, list[str]]
    ) -> dict[str, str]:
        """미이해 개념 → 보충설명(재요약) 매핑. 명세 §4.4의 "개인화 요약 흡수"."""
        ...


def get_llm_provider() -> LlmProvider:
    settings = get_settings()
    if settings.llm_provider == "claude":
        from app.domain.llm.claude import ClaudeProvider

        return ClaudeProvider()

    from app.domain.llm.mock import MockProvider

    return MockProvider()
