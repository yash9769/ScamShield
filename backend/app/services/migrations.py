"""
backend/app/services/migrations.py
Programmatic Alembic runner used at application startup in production.

Replaces the old ``create_all()`` + ad-hoc ``ALTER TABLE`` bootstrap. Every
schema change now ships as a real migration under backend/migrations/ and is
applied automatically (and idempotently) on boot via ``alembic upgrade head``.

Legacy databases created with ``create_all()`` have no ``alembic_version``
table. If the target DB already contains tables (schema adopted from the
previous bootstrap), we ``stamp head`` instead of re-running the DDL so we do
not crash on ``CREATE TABLE ... already exists``.
"""

from __future__ import annotations

import logging
from pathlib import Path

from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, inspect

from app.core.config import get_settings

logger = logging.getLogger(__name__)

_BACKEND_DIR = Path(__file__).resolve().parent.parent.parent  # backend/


def _sync_url() -> str:
    """Sync (non-async) form of settings.DATABASE_URL for Alembic."""
    database_url = get_settings().DATABASE_URL
    if database_url.startswith("postgresql+asyncpg"):
        return database_url.replace("postgresql+asyncpg", "postgresql+psycopg2", 1)
    if database_url.startswith("sqlite+aiosqlite"):
        return database_url.replace("sqlite+aiosqlite", "sqlite+pysqlite", 1)
    return database_url


def _alembic_config() -> Config:
    cfg = Config(str(_BACKEND_DIR / "alembic.ini"))
    cfg.set_main_option("script_location", str(_BACKEND_DIR / "migrations"))
    cfg.set_main_option("prepend_sys_path", str(_BACKEND_DIR))
    cfg.attributes["sqlalchemy.url"] = _sync_url()
    return cfg


def _legacy_schema_without_version(engine) -> bool:
    """True when the DB has application tables but no alembic_version table."""
    inspector = inspect(engine)
    tables = set(inspector.get_table_names())
    return "alembic_version" not in tables and bool(tables)


def run_migrations() -> None:
    """Apply pending migrations. Called once at startup."""
    settings = get_settings()
    try:
        engine = create_engine(_sync_url(), future=True)
    except Exception as exc:  # pragma: no cover - environment-specific
        logger.warning("Migrations skipped: could not connect to the database: %s", exc)
        return

    try:
        with engine.connect():
            if _legacy_schema_without_version(engine):
                command.stamp(_alembic_config(), "head")
                logger.info(
                    "Detected a pre-migration schema; stamped Alembic head "
                    "(existing tables adopted as-is, no DDL was re-run)"
                )
            else:
                command.upgrade(_alembic_config(), "head")
                logger.info("Database schema is up to date (alembic upgrade head)")
    except Exception as exc:  # pragma: no cover - fail loudly, config error
        logger.error("Database migration failed: %s", exc)
        raise
    finally:
        engine.dispose()
