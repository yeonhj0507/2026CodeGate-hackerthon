"""도메인 테이블 초기 생성: temp_scraps, partner_articles

담당2의 users 테이블은 별도 리비전으로 이 체인 뒤에 붙는다.

Revision ID: 0001
Revises:
"""

import pgvector.sqlalchemy
import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "0001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("CREATE EXTENSION IF NOT EXISTS vector")

    op.create_table(
        "temp_scraps",
        sa.Column("id", sa.String(length=36), primary_key=True),
        sa.Column("user_id", sa.String(length=64), nullable=False),
        sa.Column("article_title", sa.String(length=512), nullable=False),
        sa.Column("article_body", sa.Text(), nullable=False),
        sa.Column("results", postgresql.JSONB(), nullable=False),
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
        sa.Column("concept_tags", postgresql.JSONB(), nullable=False),
        sa.Column("published_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("embedding", pgvector.sqlalchemy.Vector(1536), nullable=True),
    )
    op.create_index("ix_partner_articles_category", "partner_articles", ["category"])


def downgrade() -> None:
    op.drop_table("partner_articles")
    op.drop_table("temp_scraps")
