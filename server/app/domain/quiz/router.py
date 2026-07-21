import json
import logging
from collections.abc import AsyncIterator

from fastapi import APIRouter, Depends
from fastapi.responses import StreamingResponse

from app.core.deps import CurrentUser, get_current_user
from app.core.errors import AppError
from app.domain.llm.base import get_llm_provider
from app.domain.quiz import service
from app.domain.schemas import QuizRequest, QuizResponse

logger = logging.getLogger(__name__)

router = APIRouter(tags=["quiz"])


@router.post("/quiz", response_model=QuizResponse)
async def create_quiz(
    payload: QuizRequest,
    _user: CurrentUser = Depends(get_current_user),
) -> QuizResponse:
    """기사 제목·원문 → 재질문 트리를 포함한 퀴즈 전체 정보 (명세 §4.2).

    전체가 완성돼야 응답이 나간다. `/quiz/stream` 의 폴백으로 남겨 둔다 —
    구버전 익스텐션과 스트리밍 실패 경로가 이걸 쓴다.
    """
    return await service.generate_quiz(
        payload.articleTitle, payload.articleBody, get_llm_provider()
    )


@router.post("/quiz/stream")
async def create_quiz_stream(
    payload: QuizRequest,
    _user: CurrentUser = Depends(get_current_user),
) -> StreamingResponse:
    """같은 퀴즈를 **완성되는 대로** NDJSON 으로 흘려보낸다.

    한 줄에 JSON 하나:
        {"item": {...}}                            문항 1건
        {"done": true, "total": 4}                 정상 종료
        {"error": {"code": ..., "message": ...}}   중도 실패

    LLM 호출 횟수는 `/quiz` 와 같은 1회다(명세 §3.2). 바뀌는 건 도착 시점뿐이라
    "세션 중 추가 서버 호출 없음" 원칙은 그대로 지켜진다.
    """
    llm = get_llm_provider()

    async def lines() -> AsyncIterator[str]:
        total = 0
        try:
            async for item in service.stream_quiz(
                payload.articleTitle, payload.articleBody, llm
            ):
                total += 1
                yield json.dumps({"item": item.model_dump()}, ensure_ascii=False) + "\n"
        except AppError as exc:
            # 첫 바이트가 나간 뒤엔 상태코드를 못 바꾼다. 본문 줄로 알리고
            # 익스텐션이 /quiz 로 폴백하게 한다.
            yield json.dumps(
                {"error": {"code": exc.code, "message": exc.message}}, ensure_ascii=False
            ) + "\n"
            return
        except Exception:  # noqa: BLE001 - 스트림 중간 실패도 줄로 알린다
            logger.exception("quiz stream failed")
            yield json.dumps(
                {"error": {"code": "INTERNAL", "message": "퀴즈 생성 중 오류가 발생했다."}},
                ensure_ascii=False,
            ) + "\n"
            return

        yield json.dumps({"done": True, "total": total}, ensure_ascii=False) + "\n"

    return StreamingResponse(
        lines(),
        media_type="application/x-ndjson",
        # 프록시가 버퍼링하면 점진 전달이 통째로 무의미해진다.
        headers={"Cache-Control": "no-store", "X-Accel-Buffering": "no"},
    )
