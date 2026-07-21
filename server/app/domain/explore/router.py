from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_db
from app.core.deps import CurrentUser, get_current_user
from app.domain.explore import service
from app.domain.llm.base import get_llm_provider
from app.domain.schemas import ExploreRequest, ExploreResponse

router = APIRouter(tags=["explore"])


@router.post("/explore", response_model=ExploreResponse)
async def explore(
    payload: ExploreRequest,
    _user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> ExploreResponse:
    """고른 키워드 2~3개 → 묶음 설명 + 관련 기사 2건 (탐색 탭)."""
    return await service.explore(db, payload, get_llm_provider())
