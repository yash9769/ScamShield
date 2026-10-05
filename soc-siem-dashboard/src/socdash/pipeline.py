"""Orchestration layer: generate -> store, and (separately) detect -> correlate
-> store.

Split into two stages, the way a real SIEM separates ingestion from
detection re-runs — the dashboard uses this to let you re-run detection
(e.g. after changing the anomaly contamination slider) without
regenerating the underlying event stream.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from pathlib import Path

from .detection import anomaly, correlation, rule_engine, suppression
from .generator import generate_dataset
from .storage import db

DEFAULT_DB_PATH = Path(__file__).resolve().parents[2] / "data" / "soc.db"


def generate_and_store(
    db_path: Path | str = DEFAULT_DB_PATH,
    days: int = 5,
    base_per_hour: int = 30,
    scenario_count: int = 14,
    campaign_count: int = 1,
    seed: int = 42,
    end: datetime | None = None,
) -> dict:
    end = end or datetime.now(timezone.utc).replace(tzinfo=None, minute=0, second=0, microsecond=0)
    start = end - timedelta(days=days)
    events = generate_dataset(
        start, end, base_per_hour=base_per_hour, scenario_count=scenario_count,
        campaign_count=campaign_count, seed=seed,
    )
    conn = db.connect(db_path)
    try:
        n_events = db.write_events(conn, events)
    finally:
        conn.close()
    return {"events": n_events, "start": start, "end": end}


def detect_and_store(
    db_path: Path | str = DEFAULT_DB_PATH,
    anomaly_contamination: float = 0.03,
    link_window_hours: float = 3.0,
) -> dict:
    conn = db.connect(db_path)
    try:
        events = db.read_events(conn)
        if events.empty:
            return {"rule_alerts": 0, "anomaly_alerts": 0, "total_alerts": 0, "suppressed": 0, "incidents": 0}

        rule_alerts = rule_engine.run_rules(events)
        feat = anomaly.extract_features(events)
        scored = anomaly.score_anomalies(feat, contamination=anomaly_contamination)
        anomaly_alerts = anomaly.generate_anomaly_alerts(scored, events)

        rules = db.read_suppressions(conn).to_dict("records")
        alerts, suppressed = suppression.apply(rule_alerts + anomaly_alerts, rules)
        incidents = correlation.correlate(alerts, link_window_hours=link_window_hours)
        n_alerts = db.write_alerts(conn, alerts + suppressed)
        n_incidents = db.write_incidents(conn, incidents)
    finally:
        conn.close()

    return {
        "rule_alerts": len(rule_alerts),
        "anomaly_alerts": len(anomaly_alerts),
        "total_alerts": n_alerts,
        "suppressed": len(suppressed),
        "incidents": n_incidents,
    }


def run_pipeline(
    db_path: Path | str = DEFAULT_DB_PATH,
    days: int = 5,
    base_per_hour: int = 30,
    scenario_count: int = 14,
    campaign_count: int = 1,
    seed: int = 42,
    anomaly_contamination: float = 0.03,
    end: datetime | None = None,
) -> dict:
    gen_result = generate_and_store(db_path, days, base_per_hour, scenario_count, campaign_count, seed, end)
    detect_result = detect_and_store(db_path, anomaly_contamination)
    return {**gen_result, **detect_result}
