"""Alembic 마이그레이션 환경 (async)."""
import asyncio
from logging.config import fileConfig

from alembic import context
from sqlalchemy.ext.asyncio import create_async_engine

from app.core.config import settings
from app.core.db import Base, async_engine_options

# --- 모델 import: Base.metadata 에 테이블이 등록되도록 반드시 import ---
from app.auth import models as _auth_models  # noqa: F401,E402
from app.domain import models as _domain_models  # noqa: F401,E402

config = context.config
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata


def run_migrations_offline() -> None:
    context.configure(
        url=settings.database_url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        compare_type=True,
    )
    with context.begin_transaction():
        context.run_migrations()


def _do_run_migrations(connection) -> None:
    context.configure(connection=connection, target_metadata=target_metadata, compare_type=True)
    with context.begin_transaction():
        context.run_migrations()


async def run_migrations_online() -> None:
    # db.py 와 동일한 규칙으로 SSL·풀러 옵션을 적용한다 → Supabase 로 마이그레이션할 때
    # URL 에 ?ssl=require 를 덧붙이지 않아도 된다(호스트로 자동 판단).
    engine_kwargs, connect_args = async_engine_options(settings.database_url)
    connectable = create_async_engine(settings.database_url, connect_args=connect_args, **engine_kwargs)
    async with connectable.connect() as connection:
        await connection.run_sync(_do_run_migrations)
    await connectable.dispose()


if context.is_offline_mode():
    run_migrations_offline()
else:
    asyncio.run(run_migrations_online())
