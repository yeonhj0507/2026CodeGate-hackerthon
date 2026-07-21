"""퀴즈 생성 (명세 §4.2 / 구현계획③ §2.1).

서버는 퀴즈를 저장하지 않는다(stateless). 개념 태그는 `/scrap` 으로 echo 되어
돌아오며 그때가 그래프 갱신 근거가 된다.
"""

import hashlib
import re
import time

from pydantic import ValidationError

from app.core.errors import AppError
from app.domain.llm.base import LlmProvider
from app.domain.schemas import QuizItem, QuizResponse

ANCHOR_LEN = 50
# 한 기사에서 낼 문항 상한(명세 §3.2 "핵심 주장 2~4개").
MAX_QUIZ_ITEMS = 4
_CACHE_TTL_SEC = 60 * 30
_cache: dict[str, tuple[float, QuizResponse]] = {}


def split_paragraphs(body: str) -> list[str]:
    """본문을 문단 배열로 나눈다. 인덱스가 곧 `paragraphIndex` 계약이다.

    익스텐션도 같은 순서로 문단을 들고 있으므로(구현계획① §3.1), 빈 줄 기준
    분할 후 공백만 정리하는 최소 규칙만 쓴다.
    """
    chunks = re.split(r"\n\s*\n|\r\n\s*\r\n", body)
    paragraphs = []
    for chunk in chunks:
        text = re.sub(r"\s+", " ", chunk).strip()
        if text:
            paragraphs.append(text)
    if len(paragraphs) < 2:
        # 개행이 없는 본문. 문장 단위로라도 쪼개 문단 위치를 만든다.
        sentences = [s.strip() for s in re.split(r"(?<=[.!?。])\s+", body) if s.strip()]
        if len(sentences) > len(paragraphs):
            return sentences
    return paragraphs


def anchor_for(paragraph: str) -> str:
    """문단 앞부분 스니펫. 익스텐션 앵커 매칭의 1차 키(구현계획① §3.3)."""
    return paragraph[:ANCHOR_LEN]


def _cache_key(title: str, body: str) -> str:
    return hashlib.sha256(f"{title}\x00{body}".encode("utf-8")).hexdigest()


def _normalize(raw: dict, paragraphs: list[str]) -> QuizResponse:
    """LLM 원시 출력을 계약 스키마로 정규화·검증한다.

    - `paragraphIndex` 범위를 서버가 강제(초과 시 마지막 문단으로 클램프).
    - `anchorText` 는 LLM 출력을 믿지 않고 **서버가 문단에서 직접 채운다**.
    - `answerIndex` 가 options 범위를 벗어나면 그 문항은 버린다.
    """
    items: list[QuizItem] = []
    last = len(paragraphs) - 1

    for entry in raw.get("quiz", []):
        if not isinstance(entry, dict):
            continue
        idx = entry.get("paragraphIndex", 0)
        if not isinstance(idx, int) or idx < 0:
            idx = 0
        idx = min(idx, last)

        entry = {**entry, "paragraphIndex": idx, "anchorText": anchor_for(paragraphs[idx])}
        entry["followups"] = _clamp_followups(entry.get("followups"), depth=1)

        try:
            item = QuizItem.model_validate(entry)
        except ValidationError:
            continue
        if not 0 <= item.answerIndex < len(item.options):
            continue
        items.append(item)

    # 개수는 프롬프트로만 요청하고 있었다(명세 §3.2 "핵심 주장 2~4개"). 모델이 더 내면
    # 그대로 나가 한 기사에서 문항이 쏟아진다. strict 스키마는 minItems/maxItems 를
    # 지원하지 않으므로(400) 여기서 잠근다. 적게 오는 쪽은 만들어 낼 수 없어 그대로 둔다.
    return QuizResponse(quiz=items[:MAX_QUIZ_ITEMS])


def _clamp_followups(raw, depth: int) -> list:
    """재질문 깊이를 2로 강제한다(명세 §3.2). 깊이 초과분은 잘라 낸다."""
    if depth > 2 or not isinstance(raw, list):
        return []
    out = []
    for entry in raw[:1]:  # 한 단계당 분기 1개 — 오답 경로는 선형이다.
        if not isinstance(entry, dict):
            continue
        entry = {**entry, "level": depth}
        entry["followups"] = _clamp_followups(entry.get("followups"), depth + 1)
        out.append(entry)
    return out


async def generate_quiz(title: str, body: str, llm: LlmProvider) -> QuizResponse:
    paragraphs = split_paragraphs(body)
    if not paragraphs:
        raise AppError(
            status_code=422,
            code="EMPTY_ARTICLE",
            message="기사 본문에서 문단을 찾지 못했다.",
        )

    key = _cache_key(title, body)
    hit = _cache.get(key)
    if hit and time.time() - hit[0] < _CACHE_TTL_SEC:
        return hit[1]

    result = _normalize(await llm.generate_quiz(title, paragraphs), paragraphs)
    if not result.quiz:
        # LLM 출력이 통째로 어긋난 경우 1회 재시도.
        result = _normalize(await llm.generate_quiz(title, paragraphs), paragraphs)
    if not result.quiz:
        raise AppError(
            status_code=502,
            code="LLM_INVALID_OUTPUT",
            message="퀴즈 생성에 실패했다. 유효한 문항이 하나도 없다.",
        )

    _cache[key] = (time.time(), result)
    return result
