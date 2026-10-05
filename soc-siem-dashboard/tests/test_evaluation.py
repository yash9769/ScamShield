from datetime import datetime, timedelta

import pandas as pd

from socdash import evaluation

T0 = datetime(2026, 1, 1, 10, 0, 0)


def _event(event_id, minutes, tag=None, scenario=None, campaign=None):
    return {"event_id": event_id, "ts": T0 + timedelta(minutes=minutes), "event_type": "auth",
            "scenario_tag": tag, "scenario_id": scenario, "campaign_id": campaign}


def _alert(alert_id, minutes, event_ids, source="brute_force", incident="INC-1"):
    return {"alert_id": alert_id, "ts": T0 + timedelta(minutes=minutes), "source": source,
            "event_ids": event_ids, "incident_id": incident, "mitre_technique": None}


def _frames(events, alerts):
    ev = pd.DataFrame(events)
    ev["ts"] = pd.to_datetime(ev["ts"])
    al = pd.DataFrame(alerts)
    al["ts"] = pd.to_datetime(al["ts"])
    return ev, al


def test_coverage_precision_and_time_to_detect():
    events, alerts = _frames(
        [
            _event("b1", 0, "brute_force", "sc-bf"), _event("b2", 1, "brute_force", "sc-bf"),
            _event("d1", 5, "dns_beaconing", "sc-dns"),
            _event("x1", 30, "port_scan", "sc-missed"),
            _event("n1", 50),  # background
        ],
        [
            _alert("r1", 2, ["b1", "b2"]),                                          # rule TP, 2 min after the first event
            _alert("a1", 0, ["d1", "n1"], source=evaluation.ANOMALY_SOURCE),        # anomaly TP for the 10:00 hour
            _alert("fp", 50, ["n1"]),                                               # rule FP
        ],
    )
    out = evaluation.evaluate(events, alerts, rules=[])
    outcomes = out["outcomes"].set_index("scenario_id")
    assert outcomes.loc["sc-bf", "outcome"] == "rules only"
    assert outcomes.loc["sc-dns", "outcome"] == "anomaly only"
    assert outcomes.loc["sc-missed", "outcome"] == "missed"
    assert outcomes.loc["sc-bf", "ttd_minutes"] == 2
    # Anomaly alerts are scored when their hour closes: 10:00 bucket -> 11:00, first event 10:05.
    assert outcomes.loc["sc-dns", "ttd_minutes"] == 55
    assert outcomes.loc["sc-dns", "first_detector"] == "anomaly"

    precision = out["precision"].set_index("source")
    assert precision.loc["brute_force", "true_positives"] == 1
    assert precision.loc["brute_force", "false_positives"] == 1
    assert precision.loc[evaluation.ANOMALY_SOURCE, "precision"] == 1.0

    techniques = out["techniques"].set_index("scenario_tag")
    assert techniques.loc["port_scan", "recall"] == 0.0
    assert techniques.loc["brute_force", "recall"] == 1.0


def test_campaign_reconstruction_and_incident_purity():
    events, alerts = _frames(
        [
            _event("s1", 0, "port_scan", "st-1", "cmp-A"),
            _event("s2", 10, "brute_force", "st-2", "cmp-A"),
            _event("s3", 20, "lateral_movement", "st-3", "cmp-B"),
            _event("s4", 30, "lateral_movement", "st-4", "cmp-B"),
            _event("o1", 40, "port_scan", "sc-other"),
        ],
        [
            _alert("a1", 1, ["s1"], incident="INC-A"), _alert("a2", 11, ["s2"], incident="INC-A"),
            _alert("b1", 21, ["s3"], incident="INC-B1"), _alert("b2", 31, ["s4"], incident="INC-B2"),
            _alert("m1", 41, ["o1", "s1"], incident="INC-A"),  # merges an unrelated attack into INC-A
            _alert("fp", 45, [], incident="INC-FP"),
        ],
    )
    out = evaluation.evaluate(events, alerts, rules=[])
    campaigns = out["campaigns"].set_index("campaign_id")
    assert bool(campaigns.loc["cmp-A", "reconstructed"]) is True
    assert bool(campaigns.loc["cmp-B", "reconstructed"]) is False
    assert campaigns.loc["cmp-B", "incidents"] == 2

    purity = out["purity"].set_index("incident_id")["verdict"]
    assert purity["INC-A"] == "merged attacks"
    assert purity["INC-B1"] == "one attack"
    assert purity["INC-FP"] == "false positives only"


def test_attack_coverage_marks_gaps():
    events, alerts = _frames([_event("b1", 0, "brute_force", "sc-bf")], [_alert("r1", 1, ["b1"])])
    rules = [{"id": "brute_force", "mitre": {"technique": "T1110"}}]
    coverage = evaluation.evaluate(events, alerts, rules)["coverage"].set_index("technique")
    assert "brute_force" in coverage.loc["T1110", "detectors"]
    assert coverage.loc["T1110", "injected"] == 1 and coverage.loc["T1110", "caught"] == 1
    assert coverage.loc["T1568", "detectors"] == [], "Dynamic Resolution has no detector — a visible gap"


def test_no_ground_truth_is_handled():
    events, alerts = _frames([_event("n1", 0)], [_alert("fp", 1, ["n1"])])
    out = evaluation.evaluate(events, alerts, rules=[])
    assert out["outcomes"].empty
    assert out["precision"].set_index("source").loc["brute_force", "precision"] == 0.0
