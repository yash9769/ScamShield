"""
backend/app/services/audit.py
Lightweight SQLite audit logger for admin analytics.

Each analysis / scan writes one row. Admin endpoints read it back via the
dashboard API. Writes are best-effort and never raise, so a storage problem
cannot take down the analysis pipeline.

PRIVACY: raw user content (messages, emails, OTPs, phone numbers, reset
links) is NEVER stored. The audit row keeps only a short SHA-256 fingerprint
of the scanned target plus its length and outcome. This means the admin
dashboard can reason about volume/risk without retaining sensitive content.
"""

from __future__ import annotations

import sqlite3
import threading
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional

from app.core.config import get_settings
from app.core.logging import get_logger

logger = get_logger(__name__)

_lock = threading.Lock()


def _db_path() -> Path:
    return Path(get_settings().AUDIT_DB_PATH)


def _init_db(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(str(path)) as conn:
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS audit_logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT NOT NULL,
                event_type TEXT NOT NULL,
                target TEXT NOT NULL,
                target_fingerprint TEXT NOT NULL DEFAULT '',
                target_length INTEGER NOT NULL DEFAULT 0,
                risk_score INTEGER NOT NULL DEFAULT 0,
                risk_level TEXT NOT NULL DEFAULT ''
            )
            """
        )
        _migrate(conn)


def _migrate(conn: sqlite3.Connection) -> None:
    """Add fingerprint/length columns to pre-existing audit DBs."""
    cols = {row[1] for row in conn.execute("PRAGMA table_info(audit_logs)")}
    if "target_fingerprint" not in cols:
        conn.execute("ALTER TABLE audit_logs ADD COLUMN target_fingerprint TEXT NOT NULL DEFAULT ''")
    if "target_length" not in cols:
        conn.execute("ALTER TABLE audit_logs ADD COLUMN target_length INTEGER NOT NULL DEFAULT 0")
    conn.commit()


def log_audit_event(
    event_type: str,
    target: str,
    risk_score: int,
    risk_level: str,
    target_fingerprint: Optional[str] = None,
    target_length: Optional[int] = None,
) -> None:
    """Record an analysis event. Never raises.

    ``target`` may hold a *safe, non-sensitive* label (e.g. a sanitised APK
    filename). Any user content must be passed via ``target_fingerprint``
    (a SHA-256 prefix) instead — raw messages/emails are never persisted.
    """
    try:
        path = _db_path()
        _init_db(path)
        # Only keep non-sensitive labels; anything else is stripped.
        safe_target = str(target)[:150] if target else ""
        fp = (target_fingerprint or "")[:32]
        length = int(target_length or 0)
        with _lock, sqlite3.connect(str(path)) as conn:
            conn.execute(
                "INSERT INTO audit_logs (timestamp, event_type, target, target_fingerprint, "
                "target_length, risk_score, risk_level) VALUES (?, ?, ?, ?, ?, ?, ?)",
                (
                    datetime.now(timezone.utc).isoformat(),
                    event_type,
                    safe_target,
                    fp,
                    length,
                    int(risk_score),
                    str(risk_level),
                ),
            )
    except Exception as exc:  # pragma: no cover - storage must never break analysis
        logger.warning("Failed to write audit event", extra={"error": str(exc)})


def fetch_audit_logs(limit: int = 50) -> List[Dict[str, Any]]:
    """Return the most recent audit rows, newest first."""
    try:
        path = _db_path()
        _init_db(path)
        bounded = max(1, min(int(limit), 100))
        with sqlite3.connect(str(path)) as conn:
            conn.row_factory = sqlite3.Row
            rows = conn.execute(
                "SELECT timestamp, event_type, target, target_fingerprint, "
                "target_length, risk_score, risk_level"
                " FROM audit_logs ORDER BY id DESC LIMIT ?",
                (bounded,),
            ).fetchall()
        return [dict(r) for r in rows]
    except Exception as exc:
        logger.warning("Failed to read audit logs", extra={"error": str(exc)})
        return []


def audit_stats() -> Dict[str, Any]:
    """Aggregate audit counters for the dashboard."""
    try:
        path = _db_path()
        _init_db(path)
        with sqlite3.connect(str(path)) as conn:
            count = conn.execute("SELECT count(*) FROM audit_logs").fetchone()[0]
        return {"total_audit_events": count}
    except Exception:
        return {"total_audit_events": 0}
