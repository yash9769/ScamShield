"""
backend/migrations/env.py
Alembic environment — runs migrations against the same DATABASE_URL the app
uses. The async drivers used at runtime (asyncpg / aiosqlite) are swapped for
their synchronous equivalents so migrations work under plain ``alembic``.

Usage (from backend/):

    alembic upgrade head
    alembic revision --autogenerate -m "describe change"
"""

from __future__ import annotations

from logging.config import fileConfig

from alembic import context
from sqlalchemy import engine_from_config, pool

from app.core.config import get_settings
from app.models.base import Base

# Import every model so autogenerate sees the full metadata.
import app.models.schema  # noqa: F401

config = context.config

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata


def _sync_url() -> str:
    """Return a synchronous database URL mirroring settings.DATABASE_URL.

    Alembic cannot drive an async engine, so the async driver scheme is
    translated to its sync equivalent:
      postgresql+asyncpg -> postgresql+psycopg2
      sqlite+aiosqlite   -> sqlite+pysqlite
    """
    database_url = get_settings().DATABASE_URL
    if database_url.startswith("postgresql+asyncpg"):
        return database_url.replace("postgresql+asyncpg", "postgresql+psycopg2", 1)
    if database_url.startswith("sqlite+aiosqlite"):
        return database_url.replace("sqlite+aiosqlite", "sqlite+pysqlite", 1)
    return database_url


def run_migrations_offline() -> None:
    """Run migrations in 'offline' mode (emit SQL to a script, no DB)."""
    context.configure(
        url=_sync_url(),
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        compare_type=True,
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    """Run migrations in 'online' mode against a live database."""
    if get_settings().DATABASE_URL.startswith("postgresql"):
        # psycopg2 is required for sync Postgres migrations. Instruct clearly
        # rather than failing with an opaque import error.
        try:
            import psycopg2  # noqa: F401
        except ImportError as exc:  # pragma: no cover - env-specific
            raise RuntimeError(
                "Alembic migrations against PostgreSQL require the 'psycopg2' "
                "driver. Install it with: pip install psycopg2-binary"
            ) from exc

    cfg = config.get_section(config.config_ini_section, {})
    cfg["sqlalchemy.url"] = _sync_url()
    connectable = engine_from_config(
        cfg,
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )

    with connectable.connect() as connection:
        context.configure(
            connection=connection,
            target_metadata=target_metadata,
            compare_type=True,
        )
        with context.begin_transaction():
            context.run_migrations()

    connectable.dispose()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
