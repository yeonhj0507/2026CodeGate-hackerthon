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

import json
import logging
import time
from functools import lru_cache

import anthropic
from anthropic import AsyncAnthropic

from app.core.config import get_settings
from app.core.errors import AppError
from app.domain.llm import prompts
from app.domain.llm.base import ConceptContext
from app.domain.llm.jsonstream import JsonArrayScanner

logger = logging.getLogger(__name__)

QUIZ_MAX_TOKENS = 16000
SUMMARY_MAX_TOKENS = 4000


def _log_timing(label: str, message, elapsed: float, payload: dict | None = None) -> None:
    """호출 1건의 입출력 토큰과 실제 소요 시간을 남긴다.

    "느리다"의 원인을 코드 구조에서 추론하지 않고 확정하기 위한 계측이다. 읽는 법:

    - in 이 크고 out 이 작은데 느리다 → 병목이 LLM 출력이 아니다(네트워크·서버 쪽을 보라).
    - out 이 압도적이다 → 출력 생성이 병목. 문항 수를 줄이거나 출력 속도를 올려야 한다.
    - out 이 payload 대비 과하게 크다 → 그 차이가 **thinking 토큰**이다. thinking 은
      화면에 안 보이지만 출력 전에 직렬로 생성되므로 시간을 그대로 쓴다. 이 경우
      effort 를 낮추는 게 모델 교체나 문항 축소보다 먼저다.

    payload_chars 는 tool 로 받은 JSON 의 글자 수다. 토큰이 아니라 대략의 비교 기준이며,
    한국어는 대체로 1토큰이 1글자 남짓이라 out 과 자릿수만 견줘 보면 된다.
    """
    usage = getattr(message, "usage", None)
    tokens_in = getattr(usage, "input_tokens", 0) or 0
    tokens_out = getattr(usage, "output_tokens", 0) or 0
    rate = tokens_out / elapsed if elapsed > 0 else 0.0
    payload_chars = len(json.dumps(payload, ensure_ascii=False)) if payload else 0

    logger.info(
        "%s: in=%d out=%d elapsed=%.1fs (%.0f tok/s) payload_chars=%d cached_read=%d",
        label,
        tokens_in,
        tokens_out,
        elapsed,
        rate,
        payload_chars,
        getattr(usage, "cache_read_input_tokens", 0) or 0,
    )


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

        started = time.monotonic()
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

        payload = _tool_input(message, prompts.QUIZ_TOOL["name"])
        _log_timing("quiz", message, time.monotonic() - started, payload)
        return payload

    async def stream_quiz(self, title: str, paragraphs: list[str]):
        """generate_quiz 와 같은 1회 호출. 다른 건 문항이 도착하는 시점뿐이다.

        tool 입력은 `input_json_delta` 로 조각조각 온다. 이어붙인 중간 상태는 깨진
        JSON 이라 통째로는 파싱되지 않으므로, 배열 원소가 닫히는 순간을 스캐너가
        잡아 그 구간만 파싱한다(jsonstream.py).
        """
        numbered = "\n\n".join(f"[{i}] {p}" for i, p in enumerate(paragraphs))
        user = prompts.QUIZ_USER_TEMPLATE.format(title=title, paragraphs=numbered)

        scanner = JsonArrayScanner("quiz")
        emitted = 0
        started = time.monotonic()

        try:
            async with _client().messages.stream(
                model=self._model,
                max_tokens=QUIZ_MAX_TOKENS,
                system=prompts.QUIZ_SYSTEM,
                messages=[{"role": "user", "content": user}],
                tools=[prompts.QUIZ_TOOL_STREAMING],
                tool_choice={"type": "tool", "name": prompts.QUIZ_TOOL["name"]},
                thinking={"type": "adaptive"},
                output_config={"effort": "high"},
            ) as stream:
                async for event in stream:
                    if getattr(event, "type", None) != "content_block_delta":
                        continue
                    delta = getattr(event, "delta", None)
                    if getattr(delta, "type", None) != "input_json_delta":
                        continue
                    for item in scanner.feed(delta.partial_json):
                        emitted += 1
                        yield item

                message = await stream.get_final_message()
        except Exception as exc:  # noqa: BLE001 - 아래에서 유형별로 변환
            raise _as_app_error(exc) from exc

        # 최종 응답으로 두 가지를 한다: 거절·잘림 판정(_tool_input)과 누락 복구.
        # 스캐너가 경계를 놓쳐 중간에 멈췄더라도 여기서 남은 문항을 마저 내보내므로,
        # 스트리밍이 어긋나도 **결과가 줄어들지는 않는다** — 일찍 오지 않을 뿐이다.
        payload = _tool_input(message, prompts.QUIZ_TOOL["name"])
        rest = payload.get("quiz", [])[emitted:]
        if rest:
            logger.warning("quiz stream desync: %d개를 최종 응답에서 복구했다", len(rest))
        for item in rest:
            yield item

        _log_timing("quiz-stream", message, time.monotonic() - started, payload)

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
            state = "이해완료" if item.understood else "미이해"
            lines.append(
                f"- {item.concept} [{state}]\n  "
                + ("\n  ".join(facts) or "(추가 정보 없음)")
            )

        user = (
            "아래 개념들에 각각 보충설명을 작성하라. 개념어 뒤 대괄호가 학습자의 진단 결과다.\n"
            "주어진 정보는 개념 관계와 기사 제목뿐이며, 기사 원문은 제공되지 않는다.\n\n"
            + "\n".join(lines)
        )

        started = time.monotonic()
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
        _log_timing("summary", message, time.monotonic() - started, raw)

        out: dict[str, str] = {}
        for entry in raw.get("summaries", []):
            concept = entry.get("concept")
            summary = entry.get("summary")
            if isinstance(concept, str) and isinstance(summary, str):
                out[concept] = summary
        return out

    async def explain_concepts(self, concepts: list[str]) -> str:
        """탐색 탭용 묶음 설명. 재요약과 같은 정책(사고 끔 · effort low)으로 짧게 받는다."""
        if not concepts:
            return ""

        started = time.monotonic()
        try:
            message = await _client().messages.create(
                model=self._model,
                max_tokens=1000,
                system=prompts.EXPLORE_SYSTEM,
                messages=[
                    {
                        "role": "user",
                        "content": "다음 개념들을 묶어서 설명하라: " + ", ".join(concepts),
                    }
                ],
                thinking={"type": "disabled"},
                output_config={"effort": "low"},
            )
        except Exception as exc:  # noqa: BLE001
            raise _as_app_error(exc) from exc

        _log_timing("explore", message, time.monotonic() - started)
        return "".join(b.text for b in message.content if b.type == "text").strip()


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
