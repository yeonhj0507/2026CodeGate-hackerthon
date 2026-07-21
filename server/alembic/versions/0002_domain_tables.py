"""도메인 테이블 생성: temp_scraps, partner_articles (담당3)

담당2의 0001(users) 뒤에 이어 붙는다 — 하나의 마이그레이션 체인 공유.

Revision ID: 0002
Revises: 0001
"""

import pgvector.sqlalchemy
import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "0002"
down_revision = "0001"
branch_labels = None
depends_on = None

# JSONB 는 Postgres 전용이다. 담당2의 sqlite 스모크 경로(README)에서도 돌도록
# 방언에 따라 JSON 으로 낮춘다.
JSON_TYPE = postgresql.JSONB().with_variant(sa.JSON(), "sqlite")


def upgrade() -> None:
    bind = op.get_bind()
    is_postgres = bind.dialect.name == "postgresql"

    if is_postgres:
        op.execute("CREATE EXTENSION IF NOT EXISTS vector")

    op.create_table(
        "temp_scraps",
        sa.Column("id", sa.String(length=36), primary_key=True),
        sa.Column("user_id", sa.String(length=64), nullable=False),
        sa.Column("article_title", sa.String(length=512), nullable=False),
        sa.Column("article_body", sa.Text(), nullable=False),
        sa.Column("results", JSON_TYPE, nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_temp_scraps_user_id", "temp_scraps", ["user_id"])
    op.create_index("ix_temp_scraps_user_created", "temp_scraps", ["user_id", "created_at"])

    op.create_table(
        "partner_articles",
        sa.Column("id", sa.String(length=36), primary_key=True),
        sa.Column("title", sa.String(length=512), nullable=False),
        sa.Column("url", sa.String(length=1024), nullable=False),
        sa.Column("summary", sa.Text(), nullable=False),
        sa.Column("publisher", sa.String(length=128), nullable=False),
        sa.Column("category", sa.String(length=64), nullable=False),
        sa.Column("concept_tags", JSON_TYPE, nullable=False),
        sa.Column("published_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "embedding",
            pgvector.sqlalchemy.Vector(1536) if is_postgres else sa.Text(),
            nullable=True,
        ),
    )
    op.create_index("ix_partner_articles_category", "partner_articles", ["category"])


def downgrade() -> None:
    op.drop_table("partner_articles")
    op.drop_table("temp_scraps")
