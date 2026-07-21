from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_db
from app.core.deps import CurrentUser, get_current_user
from app.domain.schemas import ScrapRequest, ScrapResponse
from app.domain.scrap import service

router = APIRouter(tags=["scrap"])


@router.post("/scrap", response_model=ScrapResponse, status_code=status.HTTP_201_CREATED)
async def create_scrap(
    payload: ScrapRequest,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> ScrapResponse:
    """세션 진단 결과를 계정 단위로 일시 버퍼링한다 (명세 §4.3)."""
    return await service.buffer_scrap(db, user.user_id, payload)
