from datetime import datetime, timedelta

from socdash.detection import correlation

T0 = datetime(2026, 1, 1, 10, 0, 0)


def _alert(alert_id, hours, hosts=(), users=(), ips=(), tactic=None, severity="high", source="rule_x", title=None):
    return {
        "alert_id": alert_id, "ts": T0 + timedelta(hours=hours), "source": source,
        "title": title or f"alert {alert_id}", "severity": severity, "mitre_tactic": tactic,
        "entities": {"hosts": list(hosts), "users": list(users), "ips": list(ips)},
    }


def _groups(alerts):
    by_incident = {}
    for a in alerts:
        by_incident.setdefault(a["incident_id"], set()).add(a["alert_id"])
    return sorted(by_incident.values(), key=min)


def test_transitive_chain_becomes_one_incident():
    """a and c share nothing, but a~b (host) and b~c (user) — one intrusion."""
    alerts = [
        _alert("a", 0, hosts=["WKS-1"]),
        _alert("b", 1, hosts=["WKS-1"], users=["u1"]),
        _alert("c", 2, users=["u1"], ips=["9.9.9.9"]),
    ]
    incidents = correlation.correlate(alerts)
    assert len(incidents) == 1
    assert _groups(alerts) == [{"a", "b", "c"}]


def test_shared_entity_outside_the_window_is_a_separate_incident():
    alerts = [_alert("a", 0, hosts=["WKS-1"]), _alert("b", 10, hosts=["WKS-1"])]
    assert len(correlation.correlate(alerts, link_window_hours=3)) == 2


def test_window_is_configurable():
    alerts = [_alert("a", 0, hosts=["WKS-1"]), _alert("b", 10, hosts=["WKS-1"])]
    assert len(correlation.correlate(alerts, link_window_hours=12)) == 1


def test_no_shared_entity_means_no_link():
    alerts = [_alert("a", 0, hosts=["WKS-1"]), _alert("b", 0.5, hosts=["WKS-2"])]
    assert len(correlation.correlate(alerts)) == 2


def test_every_alert_gets_an_incident_id():
    alerts = [_alert("a", 0, hosts=["WKS-1"]), _alert("b", 5, hosts=["WKS-9"])]
    incidents = correlation.correlate(alerts)
    assert {a["incident_id"] for a in alerts} == {i["incident_id"] for i in incidents}


def test_three_tactics_escalate_to_critical_and_order_by_matrix():
    alerts = [
        _alert("exfil", 2, hosts=["DB-01"], tactic="Exfiltration", severity="medium"),
        _alert("scan", 0, hosts=["DB-01"], tactic="Reconnaissance", severity="medium"),
        _alert("move", 1, hosts=["DB-01"], tactic="Lateral Movement", severity="medium"),
    ]
    incident = correlation.correlate(alerts)[0]
    assert incident["severity"] == "critical"
    assert incident["tactics"] == ["Reconnaissance", "Lateral Movement", "Exfiltration"]
    assert incident["title"].startswith("Reconnaissance → Lateral Movement → Exfiltration")


def test_title_leads_with_the_most_severe_alert():
    alerts = [
        _alert("noise", 0, hosts=["WKS-1"], severity="medium", title="Anomalous host behavior"),
        _alert("brute", 0.2, hosts=["WKS-1"], severity="critical", title="Repeated login failures"),
    ]
    incident = correlation.correlate(alerts)[0]
    assert incident["title"].startswith("Repeated login failures (+1 related)")


def test_score_rewards_breadth():
    narrow = correlation.correlate([_alert("a", 0, hosts=["H"], tactic="Execution"),
                                    _alert("b", 0.5, hosts=["H"], tactic="Execution")])[0]
    broad = correlation.correlate([_alert("a", 0, hosts=["H"], tactic="Execution"),
                                   _alert("b", 0.5, hosts=["H"], tactic="Exfiltration")])[0]
    assert broad["score"] > narrow["score"]


def test_kill_chain_stages_cover_the_matrix():
    stages = correlation.kill_chain_stages(["Execution", "Exfiltration"])
    assert len(stages) == 14
    assert [t for t, touched in stages if touched] == ["Execution", "Exfiltration"]
