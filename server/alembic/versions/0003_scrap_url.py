"""temp_scraps: article_body 제거, article_url 추가

명세 개정(§3.4, §4.3): 스크랩은 기사 원문을 재전송하지 않는다. `/quiz` 에서 이미
보냈으므로 URL·제목만 버퍼링하고, 서버에 원문이 영속되는 지점을 없앤다.

Revision ID: 0003
Revises: 0002
"""

import sqlalchemy as sa
from alembic import op

revision = "0003"
down_revision = "0002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # 기존 버퍼 행에는 URL이 없다. server_default 로 채운 뒤 기본값을 떼어
    # 이후 삽입은 애플리케이션이 반드시 값을 넣도록 강제한다.
    op.add_column(
        "temp_scraps",
        sa.Column("article_url", sa.String(length=1024), nullable=False, server_default=""),
    )
    op.alter_column("temp_scraps", "article_url", server_default=None)
    op.drop_column("temp_scraps", "article_body")


def downgrade() -> None:
    op.add_column(
        "temp_scraps",
        sa.Column("article_body", sa.Text(), nullable=False, server_default=""),
    )
    op.alter_column("temp_scraps", "article_body", server_default=None)
    op.drop_column("temp_scraps", "article_url")
