"""도메인 테이블. 담당2의 `User` 와 같은 Base/Alembic 체인을 공유한다.

서버는 학습 데이터를 영구 보관하지 않는다(명세 §4.5). `TempScrap` 은 로컬
동기화 시점까지의 **경유 버퍼**이고, `PartnerArticle` 은 사용자 데이터가 아니라
신문사 제휴(광고) 기반 추천 소스 데이터셋이다.
"""

from datetime import datetime, timezone

import sqlalchemy as sa
from pgvector.sqlalchemy import Vector
from sqlalchemy import DateTime, Index, String, Text
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base
from app.core.ids import new_id

EMBEDDING_DIM = 1536

# JSONB 는 Postgres 전용이다. 담당2의 sqlite 스모크 경로(README)에서도 뜨도록 낮춘다.
JSON_TYPE = JSONB().with_variant(sa.JSON(), "sqlite")


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class TempScrap(Base):
    """익스텐션이 보낸 세션 진단 결과 (명세 §4.3). 로컬 동기화 시 소비·삭제된다."""

    __tablename__ = "temp_scraps"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(String(64), index=True)
    # 원문은 받지도 저장하지도 않는다(명세 §4.3). 출처 식별자는 URL.
    article_url: Mapped[str] = mapped_column(String(1024))
    article_title: Mapped[str] = mapped_column(String(512))
    # [{conceptTag, parentConcept, level, correct}] — 담당1 §3.6 계약 그대로.
    results: Mapped[list] = mapped_column(JSON_TYPE, default=list)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utcnow)

    __table_args__ = (Index("ix_temp_scraps_user_created", "user_id", "created_at"),)


class PartnerArticle(Base):
    """신문사 제휴 기사 데이터셋 — "읽을 만한 기사" 추천 소스(명세 §4.4)."""

    __tablename__ = "partner_articles"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    title: Mapped[str] = mapped_column(String(512))
    url: Mapped[str] = mapped_column(String(1024))
    summary: Mapped[str] = mapped_column(Text, default="")
    publisher: Mapped[str] = mapped_column(String(128), default="")
    category: Mapped[str] = mapped_column(String(64), default="", index=True)
    # ["개념어", ...] — 추천 개념과 매칭하는 1차 키.
    concept_tags: Mapped[list] = mapped_column(JSON_TYPE, default=list)
    published_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    # 스트레치: pgvector 유사도 랭킹. 임베딩 미생성 시 NULL 이며 태그 매칭으로만 랭킹한다.
    embedding: Mapped[list | None] = mapped_column(Vector(EMBEDDING_DIM), nullable=True)
