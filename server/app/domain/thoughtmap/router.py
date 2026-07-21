from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_db
from app.core.deps import CurrentUser, get_current_user
from app.domain.llm.base import get_llm_provider
from app.domain.schemas import ThoughtmapUpdateRequest, ThoughtmapUpdateResponse
from app.domain.thoughtmap import service

router = APIRouter(tags=["thoughtmap"])


@router.post("/thoughtmap/update", response_model=ThoughtmapUpdateResponse)
async def update_thoughtmap(
    payload: ThoughtmapUpdateRequest,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> ThoughtmapUpdateResponse:
    """현재 그래프 + 버퍼 스크랩 + 사용자 컨텍스트 → 갱신 그래프 + 추천 (명세 §4.4)."""
    return await service.update_thoughtmap(db, user.user_id, payload, get_llm_provider())
