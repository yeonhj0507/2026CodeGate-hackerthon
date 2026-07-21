"""Anthropic Claude 어댑터.

tool use 로 JSON 스키마를 강제해 파싱 실패를 줄인다. 반환 dict 는 호출부에서
Pydantic 으로 한 번 더 검증한다(스키마 강제만 믿지 않는다).
"""

from anthropic import AsyncAnthropic

from app.core.errors import AppError
from app.core.config import get_settings
from app.domain.llm import prompts

_MAX_TOKENS = 8000


class ClaudeProvider:
    def __init__(self) -> None:
        settings = get_settings()
        if not settings.anthropic_api_key:
            raise AppError(
                status_code=500,
                code="LLM_NOT_CONFIGURED",
                message="ANTHROPIC_API_KEY 가 비어 있다. LLM_PROVIDER=mock 으로 두거나 키를 설정하라.",
            )
        self._client = AsyncAnthropic(api_key=settings.anthropic_api_key)
        self._model = settings.anthropic_model

    async def _call_tool(self, system: str, user: str, tool: dict) -> dict:
        message = await self._client.messages.create(
            model=self._model,
            max_tokens=_MAX_TOKENS,
            system=system,
            messages=[{"role": "user", "content": user}],
            tools=[tool],
            tool_choice={"type": "tool", "name": tool["name"]},
        )
        for block in message.content:
            if block.type == "tool_use":
                return dict(block.input)
        raise AppError(
            status_code=502,
            code="LLM_INVALID_OUTPUT",
            message="Claude 가 tool 출력을 내지 않았다.",
        )

    async def generate_quiz(self, title: str, paragraphs: list[str]) -> dict:
        numbered = "\n\n".join(f"[{i}] {p}" for i, p in enumerate(paragraphs))
        user = prompts.QUIZ_USER_TEMPLATE.format(title=title, paragraphs=numbered)
        return await self._call_tool(prompts.QUIZ_SYSTEM, user, prompts.QUIZ_TOOL)

    async def summarize_concepts(
        self, concepts: list[str], article_titles: dict[str, list[str]]
    ) -> dict[str, str]:
        if not concepts:
            return {}
        lines = []
        for concept in concepts:
            sources = ", ".join(article_titles.get(concept) or []) or "(출처 기사 정보 없음)"
            lines.append(f"- {concept} — 등장 기사: {sources}")
        user = "학습자가 아래 개념들을 이해하지 못했다. 각각 보충설명을 작성하라.\n\n" + "\n".join(lines)

        raw = await self._call_tool(prompts.SUMMARY_SYSTEM, user, prompts.SUMMARY_TOOL)
        out: dict[str, str] = {}
        for entry in raw.get("summaries", []):
            concept = entry.get("concept")
            summary = entry.get("summary")
            if isinstance(concept, str) and isinstance(summary, str):
                out[concept] = summary
        return out
