from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_db
from app.core.deps import CurrentUser, get_current_user
from app.domain.llm.base import get_llm_provider
from app.domain.schemas import (
    ScrapAckRequest,
    ScrapAckResponse,
    ThoughtmapUpdateRequest,
    ThoughtmapUpdateResponse,
)
from app.domain.thoughtmap import service

router = APIRouter(tags=["thoughtmap"])


@router.post("/thoughtmap/update", response_model=ThoughtmapUpdateResponse)
async def update_thoughtmap(
    payload: ThoughtmapUpdateRequest,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> ThoughtmapUpdateResponse:
    """현재 그래프 + 버퍼 스크랩 + 사용자 컨텍스트 → 갱신 그래프 + 추천 (명세 §4.4).

    반영된 스크랩은 **여기서 지우지 않는다.** 응답의 `consumedScrapIds` 를 받은
    클라이언트가 로컬 반영을 마친 뒤 `/thoughtmap/ack` 로 알려줘야 지워진다.
    """
    return await service.update_thoughtmap(db, user.user_id, payload, get_llm_provider())


@router.post("/thoughtmap/ack", response_model=ScrapAckResponse)
async def ack_scraps(
    payload: ScrapAckRequest,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> ScrapAckResponse:
    """로컬 반영을 마친 스크랩을 버퍼에서 지운다.

    이 호출이 실패해도 사용자는 잃는 게 없다 — 다음 동기화가 같은 스크랩을 다시
    반영하고(병합은 두 번 먹어도 결과가 같다) 그때 다시 지울 기회가 온다.
    """
    deleted = await service.ack_scraps(db, user.user_id, payload.scrapIds)
    return ScrapAckResponse(deleted=deleted)
