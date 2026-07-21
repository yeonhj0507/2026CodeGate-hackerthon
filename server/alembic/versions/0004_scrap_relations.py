"""temp_scraps: relations 추가

퀴즈 트리가 이미 품고 있던 선행 관계를 정답·오답과 무관하게 실어 나른다.
이전에는 사용자가 틀려서 재질문으로 내려갔을 때만(parentConcept) 엣지가 생겨,
다 맞히면 개념이 전부 고립됐다.

Revision ID: 0004
Revises: 0003
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import JSONB

revision = "0004"
down_revision = "0003"
branch_labels = None
depends_on = None

_JSON = JSONB().with_variant(sa.JSON(), "sqlite")


def upgrade() -> None:
    # 기존 버퍼 행에는 관계가 없다. 빈 배열로 채운 뒤 기본값을 떼어
    # 이후 삽입은 애플리케이션이 값을 넣도록 한다.
    op.add_column(
        "temp_scraps",
        sa.Column("relations", _JSON, nullable=False, server_default="[]"),
    )
    op.alter_column("temp_scraps", "relations", server_default=None)


def downgrade() -> None:
    op.drop_column("temp_scraps", "relations")
