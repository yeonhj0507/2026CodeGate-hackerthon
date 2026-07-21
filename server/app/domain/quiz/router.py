from fastapi import APIRouter, Depends

from app.core.deps import CurrentUser, get_current_user
from app.domain.llm.base import get_llm_provider
from app.domain.quiz import service
from app.domain.schemas import QuizRequest, QuizResponse

router = APIRouter(tags=["quiz"])


@router.post("/quiz", response_model=QuizResponse)
async def create_quiz(
    payload: QuizRequest,
    _user: CurrentUser = Depends(get_current_user),
) -> QuizResponse:
    """기사 제목·원문 → 재질문 트리를 포함한 퀴즈 전체 정보 (명세 §4.2)."""
    return await service.generate_quiz(
        payload.articleTitle, payload.articleBody, get_llm_provider()
    )
