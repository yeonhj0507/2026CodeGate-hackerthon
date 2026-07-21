"""임시 스크랩 버퍼링 (명세 §4.3).

영구 저장이 아니다. 로컬앱의 `/thoughtmap/update` 요청 때 소비·삭제된다.
"""

from datetime import datetime, timedelta, timezone

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.domain.models import TempScrap
from app.domain.schemas import ScrapRequest, ScrapResponse


async def buffer_scrap(db: AsyncSession, user_id: str, payload: ScrapRequest) -> ScrapResponse:
    row = TempScrap(
        user_id=user_id,
        article_url=payload.articleUrl,
        article_title=payload.articleTitle,
        results=[r.model_dump() for r in payload.results],
    )
    db.add(row)
    await _prune(db, user_id)
    await db.commit()
    return ScrapResponse(buffered=len(payload.results))


async def _prune(db: AsyncSession, user_id: str) -> None:
    """버퍼 무한 누적 방지 (명세 §9). 로컬 동기화가 오래 없는 계정을 위한 안전장치."""
    settings = get_settings()

    cutoff = datetime.now(timezone.utc) - timedelta(days=settings.scrap_buffer_ttl_days)
    await db.execute(
        delete(TempScrap).where(TempScrap.user_id == user_id, TempScrap.created_at < cutoff)
    )

    # 상한 초과 시 오래된 것부터 버린다.
    stale = (
        await db.execute(
            select(TempScrap.id)
            .where(TempScrap.user_id == user_id)
            .order_by(TempScrap.created_at.desc())
            .offset(settings.scrap_buffer_max_rows)
        )
    ).scalars().all()
    if stale:
        await db.execute(delete(TempScrap).where(TempScrap.id.in_(stale)))
