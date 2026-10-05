import sqlite3
from datetime import datetime

import pandas as pd
import pytest

from socdash.storage import db


@pytest.fixture
def conn(tmp_path):
    connection = db.connect(tmp_path / "test.db")
    yield connection
    connection.close()


def _alert(alert_id, status="new", incident_id=None, **overrides):
    alert = {
        "alert_id": alert_id, "ts": datetime(2026, 1, 1, 10, 0, 0), "source": "test", "title": "t",
        "severity": "high", "mitre_tactic": None, "mitre_technique": None, "mitre_technique_name": None,
        "entity": "WKS-0001", "entities": {"hosts": ["WKS-0001"], "users": [], "ips": []},
        "description": "d", "event_ids": ["e1"], "score": None, "incident_id": incident_id, "status": status,
    }
    alert.update(overrides)
    return alert


def test_write_and_read_events_roundtrip(conn):
    df = pd.DataFrame([{
        "event_id": "e1", "ts": datetime(2026, 1, 1, 10, 0, 0), "event_type": "process",
        "user": "a.user", "host": "WKS-0001", "process_name": "powershell.exe",
        "command_line": "powershell.exe -NoProfile", "scenario_id": "sc-1",
    }])
    assert db.write_events(conn, df) == 1
    back = db.read_events(conn)
    assert back.iloc[0]["command_line"] == "powershell.exe -NoProfile"
    assert back.iloc[0]["scenario_id"] == "sc-1"


def test_write_events_replace_clears_previous_rows(conn):
    db.write_events(conn, pd.DataFrame([{"event_id": "e1", "ts": datetime(2026, 1, 1), "event_type": "auth"}]))
    db.write_events(conn, pd.DataFrame([{"event_id": "e2", "ts": datetime(2026, 1, 2), "event_type": "network"}]))
    back = db.read_events(conn)
    assert back["event_id"].tolist() == ["e2"]


def test_alerts_roundtrip_json_fields(conn):
    db.write_alerts(conn, [_alert("a1")])
    back = db.read_alerts(conn).iloc[0]
    assert back["status"] == "new"
    assert back["event_ids"] == ["e1"]
    assert back["entities"] == {"hosts": ["WKS-0001"], "users": [], "ips": []}


def test_read_alerts_filters_by_status(conn):
    db.write_alerts(conn, [_alert("a1"), _alert("a2", status="closed")])
    assert len(db.read_alerts(conn, status="new")) == 1
    assert len(db.read_alerts(conn)) == 2


def test_incident_status_cascades_to_member_alerts(conn):
    db.write_alerts(conn, [_alert("a1", incident_id="INC-1"), _alert("a2", incident_id="INC-1"), _alert("a3", incident_id="INC-2")])
    db.write_incidents(conn, [{
        "incident_id": inc, "first_seen": datetime(2026, 1, 1), "last_seen": datetime(2026, 1, 1, 1),
        "title": "t", "severity": "high", "score": 6.0, "alert_count": 1, "tactics": ["Execution"],
        "entities": {"hosts": ["WKS-0001"]}, "sources": ["test"],
    } for inc in ("INC-1", "INC-2")])
    db.update_incident_status(conn, "INC-1", "closed")
    statuses = db.read_alerts(conn).set_index("alert_id")["status"].to_dict()
    assert statuses == {"a1": "closed", "a2": "closed", "a3": "new"}
    incidents = db.read_incidents(conn).set_index("incident_id")
    assert incidents.loc["INC-1", "status"] == "closed"
    assert incidents.loc["INC-1", "tactics"] == ["Execution"]


def test_older_database_files_are_migrated(tmp_path):
    """A v1 database (no command lines, ground-truth ids, entities, or
    incidents) must open and upgrade in place instead of failing writes."""
    path = tmp_path / "v1.db"
    old = sqlite3.connect(path)
    old.execute("CREATE TABLE events (event_id TEXT PRIMARY KEY, ts TEXT NOT NULL, event_type TEXT NOT NULL, host TEXT)")
    old.execute("CREATE TABLE alerts (alert_id TEXT PRIMARY KEY, ts TEXT NOT NULL, source TEXT NOT NULL, title TEXT NOT NULL, "
                "severity TEXT NOT NULL, event_ids TEXT, status TEXT NOT NULL DEFAULT 'new')")
    old.execute("INSERT INTO alerts (alert_id, ts, source, title, severity, event_ids) VALUES ('old', '2026-01-01T00:00:00', 's', 't', 'low', '[]')")
    old.commit()
    old.close()

    conn = db.connect(path)
    event_columns = {r[1] for r in conn.execute("PRAGMA table_info(events)")}
    assert {"command_line", "scenario_id", "campaign_id"} <= event_columns
    assert {"entities", "incident_id"} <= {r[1] for r in conn.execute("PRAGMA table_info(alerts)")}
    assert db.read_alerts(conn).iloc[0]["entities"] == {}
    assert db.read_incidents(conn).empty
    conn.close()
