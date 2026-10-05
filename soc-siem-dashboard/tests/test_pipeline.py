"""End-to-end: generate -> detect -> correlate -> evaluate, on a temp DB.

Rule-based recall is asserted at 100% because it is deterministic by
construction: every injected rule-covered scenario is generated to cross its
rule's threshold (e.g. a brute force is always >= 8 failures inside the
rule's 10-minute window). Anomaly-detection recall is probabilistic, so it is
only required to be non-trivial.
"""

from datetime import datetime

import pandas as pd
import pytest

from socdash import evaluation, pipeline
from socdash.detection import rule_engine
from socdash.detection.risk import entity_risk
from socdash.storage import db


@pytest.fixture(scope="module", params=[42, 7])
def run(request, tmp_path_factory):
    path = tmp_path_factory.mktemp(f"pipeline{request.param}") / "soc.db"
    summary = pipeline.run_pipeline(db_path=path, days=5, scenario_count=14, campaign_count=1,
                                    seed=request.param, end=datetime(2026, 9, 6))
    conn = db.connect(path)
    events, alerts, incidents = db.read_events(conn), db.read_alerts(conn), db.read_incidents(conn)
    conn.close()
    return summary, events, alerts, incidents, evaluation.evaluate(events, alerts, rule_engine.load_rules())


def test_counts_are_consistent(run):
    summary, events, alerts, incidents, _ = run
    assert summary["events"] == len(events)
    assert summary["total_alerts"] == len(alerts) == summary["rule_alerts"] + summary["anomaly_alerts"]
    assert summary["incidents"] == len(incidents)
    assert alerts["incident_id"].notna().all()
    assert set(alerts["incident_id"]) == set(incidents["incident_id"])


def test_rule_covered_techniques_are_always_caught(run):
    techniques = run[4]["techniques"].set_index("scenario_tag")
    rule_covered = [t for t in techniques.index if t != "dns_beaconing"]
    assert (techniques.loc[rule_covered, "recall"] == 1.0).all()


def test_rules_raise_no_false_positives(run):
    precision = run[4]["precision"].set_index("source")
    rules = precision.drop(index=evaluation.ANOMALY_SOURCE, errors="ignore")
    assert (rules["false_positives"] == 0).all()


def test_anomaly_detection_earns_its_place(run):
    """It's the only thing that can catch beaconing, and must mostly be right."""
    ev = run[4]
    beacon = ev["techniques"].set_index("scenario_tag").loc["dns_beaconing"]
    assert beacon["recall"] >= 0.5
    assert ev["precision"].set_index("source").loc[evaluation.ANOMALY_SOURCE, "precision"] >= 0.6


def test_time_to_detect_is_never_negative(run):
    assert (run[4]["outcomes"]["ttd_minutes"].dropna() >= 0).all()


def test_the_campaign_is_reconstructed_as_one_incident(run):
    campaigns = run[4]["campaigns"]
    assert len(campaigns) == 1
    assert campaigns["stages_detected"].iloc[0] == 6
    assert bool(campaigns["reconstructed"].iloc[0])
    top = run[3].iloc[0]
    assert len(top["tactics"]) >= 5 and top["severity"] == "critical", "the campaign is the top-scoring incident"


def test_entity_risk_decays_with_age():
    alerts = pd.DataFrame([
        {"ts": pd.Timestamp("2026-01-01"), "severity": "high", "source": "r",
         "entities": {"hosts": ["OLD"], "users": [], "ips": []}},
        {"ts": pd.Timestamp("2026-01-03"), "severity": "high", "source": "r",
         "entities": {"hosts": ["NEW"], "users": ["u"], "ips": []}},
    ])
    risk = entity_risk(alerts).set_index("entity")
    assert risk.loc["NEW", "risk"] == 6.0
    assert risk.loc["OLD", "risk"] == pytest.approx(6 * 0.25, abs=0.05), "two half-lives old"
    assert risk.loc["u", "kind"] == "user"
