"""Anthropic Claude 어댑터.

tool use 로 JSON 스키마를 강제해 파싱 실패를 줄인다. 반환 dict 는 호출부에서
Pydantic 으로 한 번 더 검증한다(스키마 강제만 믿지 않는다).

호출 지점별 정책(사용자 확정):
- 퀴즈 생성: adaptive thinking + effort high. 품질이 서비스의 핵심이라 사고를 켠다.
  사고 토큰도 max_tokens 에 포함되므로 넉넉히 잡고 **스트리밍**으로 받는다
  (큰 max_tokens 비스트리밍은 HTTP 타임아웃 위험).
- 개념 재요약: thinking 끄고 effort low. 근거가 개념 관계뿐이라 깊은 사고가 불필요하고,
  로컬앱의 60초 receiveTimeout(config.dart) 안에 들어와야 한다.
"""

import logging
from functools import lru_cache

import anthropic
from anthropic import AsyncAnthropic

from app.core.config import get_settings
from app.core.errors import AppError
from app.domain.llm import prompts
from app.domain.llm.base import ConceptContext

logger = logging.getLogger(__name__)

QUIZ_MAX_TOKENS = 16000
SUMMARY_MAX_TOKENS = 4000


@lru_cache(maxsize=1)
def _client() -> AsyncAnthropic:
    """프로세스당 1개. get_llm_provider() 가 요청마다 불려도 커넥션 풀을 재사용한다."""
    settings = get_settings()
    if not settings.anthropic_api_key:
        raise AppError(
            status_code=500,
            code="LLM_NOT_CONFIGURED",
            message="ANTHROPIC_API_KEY 가 비어 있다. LLM_PROVIDER=mock 으로 두거나 키를 설정하라.",
        )
    return AsyncAnthropic(api_key=settings.anthropic_api_key)


class ClaudeProvider:
    def __init__(self) -> None:
        self._model = get_settings().anthropic_model
        _client()  # 키 미설정이면 요청 처리 중이 아니라 여기서 바로 드러나게 한다.

    async def generate_quiz(self, title: str, paragraphs: list[str]) -> dict:
        numbered = "\n\n".join(f"[{i}] {p}" for i, p in enumerate(paragraphs))
        user = prompts.QUIZ_USER_TEMPLATE.format(title=title, paragraphs=numbered)

        try:
            # 스트리밍으로 받되 이벤트는 쓰지 않는다. 목적은 긴 응답의 타임아웃 회피.
            async with _client().messages.stream(
                model=self._model,
                max_tokens=QUIZ_MAX_TOKENS,
                system=prompts.QUIZ_SYSTEM,
                messages=[{"role": "user", "content": user}],
                tools=[prompts.QUIZ_TOOL],
                tool_choice={"type": "tool", "name": prompts.QUIZ_TOOL["name"]},
                # Opus 4.8 은 thinking 을 생략하면 사고 없이 실행된다. 명시가 필요하다.
                thinking={"type": "adaptive"},
                output_config={"effort": "high"},
            ) as stream:
                message = await stream.get_final_message()
        except Exception as exc:  # noqa: BLE001 - 아래에서 유형별로 변환
            raise _as_app_error(exc) from exc

        return _tool_input(message, prompts.QUIZ_TOOL["name"])

    async def summarize_concepts(self, items: list[ConceptContext]) -> dict[str, str]:
        if not items:
            return {}

        lines = []
        for item in items:
            facts = []
            if item.parent_concepts:
                facts.append(f"이 개념을 선행으로 두는 상위 개념: {', '.join(item.parent_concepts)}")
            if item.prereq_concepts:
                facts.append(f"이 개념의 선행 개념: {', '.join(item.prereq_concepts)}")
            if item.is_prereq:
                facts.append("그래프 말단의 선행 개념")
            if item.source_titles:
                facts.append(f"등장 기사 제목: {', '.join(item.source_titles)}")
            lines.append(f"- {item.concept}\n  " + ("\n  ".join(facts) or "(추가 정보 없음)"))

        user = (
            "학습자가 아래 개념들을 이해하지 못했다(오답). 각각 보충설명을 작성하라.\n"
            "주어진 정보는 개념 관계와 기사 제목뿐이며, 기사 원문은 제공되지 않는다.\n\n"
            + "\n".join(lines)
        )

        try:
            message = await _client().messages.create(
                model=self._model,
                max_tokens=SUMMARY_MAX_TOKENS,
                system=prompts.SUMMARY_SYSTEM,
                messages=[{"role": "user", "content": user}],
                tools=[prompts.SUMMARY_TOOL],
                tool_choice={"type": "tool", "name": prompts.SUMMARY_TOOL["name"]},
                # 근거가 개념 관계뿐이라 사고가 필요 없다. 로컬앱 60초 예산을 지키는 선택.
                thinking={"type": "disabled"},
                output_config={"effort": "low"},
            )
        except Exception as exc:  # noqa: BLE001
            raise _as_app_error(exc) from exc

        raw = _tool_input(message, prompts.SUMMARY_TOOL["name"])
        out: dict[str, str] = {}
        for entry in raw.get("summaries", []):
            concept = entry.get("concept")
            summary = entry.get("summary")
            if isinstance(concept, str) and isinstance(summary, str):
                out[concept] = summary
        return out


def _tool_input(message, tool_name: str) -> dict:
    """tool_use 블록을 꺼낸다. stop_reason 을 먼저 확인해야 원인이 드러난다."""
    stop = getattr(message, "stop_reason", None)

    if stop == "refusal":
        # stop_details 는 refusal 일 때만 채워지고, 그때도 None 일 수 있다.
        details = getattr(message, "stop_details", None)
        category = getattr(details, "category", None) or "unknown"
        logger.warning("Claude refused (category=%s, request_id=%s)", category, message._request_id)
        raise AppError(
            status_code=502,
            code="LLM_REFUSED",
            message=f"모델이 이 기사에 대한 생성을 거절했다 (분류: {category}).",
        )

    if stop == "max_tokens":
        logger.warning("Claude output truncated (request_id=%s)", message._request_id)
        raise AppError(
            status_code=502,
            code="LLM_TRUNCATED",
            message="응답이 max_tokens 에서 잘렸다. 기사가 지나치게 길거나 한도가 낮다.",
        )

    for block in message.content:
        if block.type == "tool_use" and block.name == tool_name:
            return dict(block.input)

    logger.warning(
        "Claude returned no tool_use (stop_reason=%s, request_id=%s)", stop, message._request_id
    )
    raise AppError(
        status_code=502,
        code="LLM_INVALID_OUTPUT",
        message=f"Claude 가 {tool_name} 출력을 내지 않았다 (stop_reason={stop}).",
    )


def _as_app_error(exc: Exception) -> Exception:
    """SDK 예외를 공통 에러 포맷으로. 구체적인 것부터 검사한다."""
    if isinstance(exc, AppError):
        return exc

    if isinstance(exc, anthropic.RateLimitError):
        retry_after = exc.response.headers.get("retry-after", "60")
        return AppError(
            status_code=429,
            code="LLM_RATE_LIMITED",
            message=f"Anthropic API 요청 한도를 넘었다. {retry_after}초 후 재시도.",
        )

    if isinstance(exc, anthropic.APIStatusError):
        logger.error("Anthropic API error %s: %s", exc.status_code, exc.message)
        return AppError(
            status_code=502,
            code="LLM_API_ERROR",
            message=f"Anthropic API 오류 ({exc.status_code}): {exc.message}",
        )

    if isinstance(exc, anthropic.APIConnectionError):
        return AppError(
            status_code=503,
            code="LLM_UNREACHABLE",
            message="Anthropic API 에 연결하지 못했다. 네트워크를 확인하라.",
        )

    return exc
