"""SQLite store: `events` (the raw normalized log stream), `alerts` (what
detection/ produces from it), and `incidents` (alerts the correlation engine
grouped into one attack story) — the same index / notable-events / cases
split a real SIEM makes.

Each table's columns are declared once below; CREATE TABLE and the migration
of older database files are both derived from those declarations.
"""

from __future__ import annotations

import json
import sqlite3
import uuid
from datetime import datetime
from pathlib import Path

import pandas as pd

EVENT_SCHEMA: dict[str, str] = {
    "event_id": "TEXT PRIMARY KEY",
    "ts": "TEXT NOT NULL",
    "event_type": "TEXT NOT NULL",
    "user": "TEXT",
    "host": "TEXT",
    "src_ip": "TEXT",
    "src_country": "TEXT",
    "dst_ip": "TEXT",
    "direction": "TEXT",
    "action": "TEXT",
    "outcome": "TEXT",
    "port": "INTEGER",
    "protocol": "TEXT",
    "bytes_sent": "INTEGER",
    "bytes_received": "INTEGER",
    "process_name": "TEXT",
    "command_line": "TEXT",
    "domain": "TEXT",
    # Ground truth, written only by the synthetic generator. Detection never
    # reads these; evaluation.py scores detections against them.
    "scenario_tag": "TEXT",
    "scenario_id": "TEXT",
    "campaign_id": "TEXT",
}

ALERT_SCHEMA: dict[str, str] = {
    "alert_id": "TEXT PRIMARY KEY",
    "ts": "TEXT NOT NULL",
    "source": "TEXT NOT NULL",
    "title": "TEXT NOT NULL",
    "severity": "TEXT NOT NULL",
    "mitre_tactic": "TEXT",
    "mitre_technique": "TEXT",
    "mitre_technique_name": "TEXT",
    "entity": "TEXT",
    "entities": "TEXT",
    "description": "TEXT",
    "event_ids": "TEXT",
    "score": "REAL",
    "incident_id": "TEXT",
    "status": "TEXT NOT NULL DEFAULT 'new'",
    "suppressed_by": "TEXT",  # v4: id of the suppression that matched, if any
}

INCIDENT_SCHEMA: dict[str, str] = {
    "incident_id": "TEXT PRIMARY KEY",
    "first_seen": "TEXT NOT NULL",
    "last_seen": "TEXT NOT NULL",
    "title": "TEXT NOT NULL",
    "severity": "TEXT NOT NULL",
    "score": "REAL",
    "alert_count": "INTEGER",
    "tactics": "TEXT",
    "entities": "TEXT",
    "sources": "TEXT",
    "status": "TEXT NOT NULL DEFAULT 'new'",
    # Case work (v3): free-text analyst notes and the keys of completed
    # response steps (JSON list). Re-running detection rebuilds incidents
    # from scratch, so — like status — these reset with it.
    "notes": "TEXT",
    "actions_done": "TEXT",
}

# Analyst-curated indicators (v4). Not rebuilt by detection: a re-run keeps them.
WATCHLIST_SCHEMA: dict[str, str] = {
    "value": "TEXT PRIMARY KEY",
    "type": "TEXT NOT NULL",
    "note": "TEXT",
    "incident_id": "TEXT",
    "added_at": "TEXT NOT NULL",
}

SUPPRESSION_SCHEMA: dict[str, str] = {
    "suppression_id": "TEXT PRIMARY KEY",
    "source": "TEXT NOT NULL",     # detector id, or * for any
    "entity": "TEXT NOT NULL",     # fnmatch pattern over the alert's entity
    "reason": "TEXT NOT NULL",
    "created_at": "TEXT NOT NULL",
    "expires_at": "TEXT",          # NULL = until removed
    "created_from": "TEXT",        # alert id it was written from, if any
}

TABLES = {"events": EVENT_SCHEMA, "alerts": ALERT_SCHEMA, "incidents": INCIDENT_SCHEMA,
          "watchlist": WATCHLIST_SCHEMA, "suppressions": SUPPRESSION_SCHEMA}

INDEXES = [
    "CREATE INDEX IF NOT EXISTS idx_events_ts ON events(ts)",
    "CREATE INDEX IF NOT EXISTS idx_events_type ON events(event_type)",
    "CREATE INDEX IF NOT EXISTS idx_events_host ON events(host)",
    "CREATE INDEX IF NOT EXISTS idx_events_user ON events(user)",
    "CREATE INDEX IF NOT EXISTS idx_alerts_ts ON alerts(ts)",
    "CREATE INDEX IF NOT EXISTS idx_alerts_status ON alerts(status)",
    "CREATE INDEX IF NOT EXISTS idx_alerts_incident ON alerts(incident_id)",
]

EVENT_COLUMNS = list(EVENT_SCHEMA)
ALERT_COLUMNS = list(ALERT_SCHEMA)
INCIDENT_COLUMNS = list(INCIDENT_SCHEMA)
STATUS_OPTIONS = ["new", "investigating", "closed", "false_positive"]


def _create_table_sql(table: str, schema: dict[str, str]) -> str:
    columns = ", ".join(f"{name} {decl}" for name, decl in schema.items())
    return f"CREATE TABLE IF NOT EXISTS {table} ({columns})"


def _migrate(conn: sqlite3.Connection, table: str, schema: dict[str, str]) -> None:
    """Adds columns an older database file is missing. Every column added
    after v1 is nullable, which is what makes ALTER TABLE ADD COLUMN legal."""
    existing = {row[1] for row in conn.execute(f"PRAGMA table_info({table})")}
    for name, decl in schema.items():
        if name not in existing:
            conn.execute(f"ALTER TABLE {table} ADD COLUMN {name} {decl}")


def connect(db_path: str | Path) -> sqlite3.Connection:
    Path(db_path).parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    for table, schema in TABLES.items():
        conn.execute(_create_table_sql(table, schema))
        _migrate(conn, table, schema)
    for statement in INDEXES:
        conn.execute(statement)
    conn.commit()
    return conn


def _ts_text(ts) -> str:
    return ts.strftime("%Y-%m-%dT%H:%M:%S") if hasattr(ts, "strftime") else str(ts)


def _loads(value, empty):
    if value is None or value == "" or (isinstance(value, float) and pd.isna(value)):
        return empty
    return json.loads(value)


def _insert(conn: sqlite3.Connection, table: str, columns: list[str], rows: list[tuple]) -> None:
    placeholders = ",".join("?" for _ in columns)
    conn.executemany(f"INSERT OR REPLACE INTO {table} ({','.join(columns)}) VALUES ({placeholders})", rows)


def write_events(conn: sqlite3.Connection, df: pd.DataFrame, replace: bool = True) -> int:
    if replace:
        conn.execute("DELETE FROM events")
    if df.empty:
        conn.commit()
        return 0
    out = df.copy()
    out["ts"] = pd.to_datetime(out["ts"]).dt.strftime("%Y-%m-%dT%H:%M:%S")
    for col in EVENT_COLUMNS:
        if col not in out.columns:
            out[col] = None
    out = out[EVENT_COLUMNS]
    out.to_sql("events", conn, if_exists="append", index=False)
    conn.commit()
    return len(out)


def write_alerts(conn: sqlite3.Connection, alerts: list[dict], replace: bool = True) -> int:
    if replace:
        conn.execute("DELETE FROM alerts")
    rows = []
    for alert in alerts:
        row = dict(alert)
        row["ts"] = _ts_text(row["ts"])
        row["event_ids"] = json.dumps(list(row.get("event_ids") or []))
        row["entities"] = json.dumps(row.get("entities") or {})
        row["status"] = row.get("status") or "new"
        rows.append(tuple(row.get(col) for col in ALERT_COLUMNS))
    if rows:
        _insert(conn, "alerts", ALERT_COLUMNS, rows)
    conn.commit()
    return len(rows)


def write_incidents(conn: sqlite3.Connection, incidents: list[dict], replace: bool = True) -> int:
    if replace:
        conn.execute("DELETE FROM incidents")
    rows = []
    for incident in incidents:
        row = dict(incident)
        row["first_seen"] = _ts_text(row["first_seen"])
        row["last_seen"] = _ts_text(row["last_seen"])
        for field in ("tactics", "sources"):
            row[field] = json.dumps(list(row.get(field) or []))
        row["entities"] = json.dumps(row.get("entities") or {})
        row["status"] = row.get("status") or "new"
        row["notes"] = row.get("notes") or ""
        row["actions_done"] = json.dumps(sorted(row.get("actions_done") or []))
        rows.append(tuple(row.get(col) for col in INCIDENT_COLUMNS))
    if rows:
        _insert(conn, "incidents", INCIDENT_COLUMNS, rows)
    conn.commit()
    return len(rows)


def read_events(conn: sqlite3.Connection, event_type: str | None = None) -> pd.DataFrame:
    query = "SELECT * FROM events"
    params: tuple = ()
    if event_type:
        query += " WHERE event_type = ?"
        params = (event_type,)
    df = pd.read_sql_query(query, conn, params=params)
    if not df.empty:
        df["ts"] = pd.to_datetime(df["ts"])
    return df


def read_alerts(conn: sqlite3.Connection, status: str | None = None) -> pd.DataFrame:
    query = "SELECT * FROM alerts"
    params: tuple = ()
    if status:
        query += " WHERE status = ?"
        params = (status,)
    query += " ORDER BY ts DESC"
    df = pd.read_sql_query(query, conn, params=params)
    if not df.empty:
        df["ts"] = pd.to_datetime(df["ts"])
        df["event_ids"] = df["event_ids"].apply(lambda v: _loads(v, []))
        df["entities"] = df["entities"].apply(lambda v: _loads(v, {}))
    return df


def read_incidents(conn: sqlite3.Connection) -> pd.DataFrame:
    df = pd.read_sql_query("SELECT * FROM incidents ORDER BY score DESC", conn)
    if not df.empty:
        df["first_seen"] = pd.to_datetime(df["first_seen"])
        df["last_seen"] = pd.to_datetime(df["last_seen"])
        df["tactics"] = df["tactics"].apply(lambda v: _loads(v, []))
        df["sources"] = df["sources"].apply(lambda v: _loads(v, []))
        df["entities"] = df["entities"].apply(lambda v: _loads(v, {}))
        df["notes"] = df["notes"].fillna("")
        df["actions_done"] = df["actions_done"].apply(lambda v: _loads(v, []))
    return df


def update_alert_status(conn: sqlite3.Connection, alert_id: str, status: str) -> None:
    conn.execute("UPDATE alerts SET status = ? WHERE alert_id = ?", (status, alert_id))
    conn.commit()


def update_incident_status(conn: sqlite3.Connection, incident_id: str, status: str) -> None:
    """Triage happens at the incident level; its member alerts follow, the
    way closing a case in a SOAR closes the notables attached to it."""
    conn.execute("UPDATE incidents SET status = ? WHERE incident_id = ?", (status, incident_id))
    conn.execute("UPDATE alerts SET status = ? WHERE incident_id = ?", (status, incident_id))
    conn.commit()


def update_incident_notes(conn: sqlite3.Connection, incident_id: str, notes: str) -> None:
    conn.execute("UPDATE incidents SET notes = ? WHERE incident_id = ?", (notes, incident_id))
    conn.commit()


def update_incident_actions(conn: sqlite3.Connection, incident_id: str, done: list[str] | set[str]) -> None:
    conn.execute("UPDATE incidents SET actions_done = ? WHERE incident_id = ?",
                 (json.dumps(sorted(done)), incident_id))
    conn.commit()


def add_watchlist(conn: sqlite3.Connection, entries: list[dict]) -> int:
    """Upsert indicators ({value, type, note?, incident_id?}); returns how
    many were new."""
    existing = {r[0] for r in conn.execute("SELECT value FROM watchlist")}
    now = datetime.now().strftime("%Y-%m-%dT%H:%M:%S")
    rows = [(e["value"], e["type"], e.get("note"), e.get("incident_id"), now) for e in entries if e.get("value")]
    conn.executemany(
        "INSERT INTO watchlist (value, type, note, incident_id, added_at) VALUES (?, ?, ?, ?, ?) "
        "ON CONFLICT(value) DO UPDATE SET note = COALESCE(excluded.note, note), "
        "incident_id = COALESCE(excluded.incident_id, incident_id)",
        rows,
    )
    conn.commit()
    return len({r[0] for r in rows} - existing)


def remove_watchlist(conn: sqlite3.Connection, values: list[str]) -> None:
    conn.executemany("DELETE FROM watchlist WHERE value = ?", [(v,) for v in values])
    conn.commit()


def read_watchlist(conn: sqlite3.Connection) -> pd.DataFrame:
    df = pd.read_sql_query("SELECT * FROM watchlist ORDER BY added_at DESC", conn)
    if not df.empty:
        df["added_at"] = pd.to_datetime(df["added_at"])
    return df


def add_suppression(conn: sqlite3.Connection, rule: dict) -> str:
    suppression_id = rule.get("suppression_id") or f"SUP-{uuid.uuid4().hex[:6].upper()}"
    expires = rule.get("expires_at")
    conn.execute(
        "INSERT INTO suppressions (suppression_id, source, entity, reason, created_at, expires_at, created_from) "
        "VALUES (?, ?, ?, ?, ?, ?, ?)",
        (suppression_id, rule["source"], rule["entity"], rule["reason"],
         datetime.now().strftime("%Y-%m-%dT%H:%M:%S"), _ts_text(expires) if expires else None, rule.get("created_from")),
    )
    conn.commit()
    return suppression_id


def remove_suppression(conn: sqlite3.Connection, suppression_id: str) -> None:
    conn.execute("DELETE FROM suppressions WHERE suppression_id = ?", (suppression_id,))
    conn.commit()


def read_suppressions(conn: sqlite3.Connection) -> pd.DataFrame:
    df = pd.read_sql_query("SELECT * FROM suppressions ORDER BY created_at DESC", conn)
    if not df.empty:
        df["created_at"] = pd.to_datetime(df["created_at"])
        df["expires_at"] = pd.to_datetime(df["expires_at"])
    return df


def event_count(conn: sqlite3.Connection) -> int:
    return conn.execute("SELECT COUNT(*) FROM events").fetchone()[0]
