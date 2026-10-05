from datetime import datetime, timedelta

import pandas as pd
import pytest

from socdash.detection import rule_engine

_RULES = {r["id"]: [r] for r in rule_engine.load_rules()}
T0 = datetime(2026, 1, 1, 10, 0, 0)


def _events(rows: list[dict]) -> pd.DataFrame:
    df = pd.DataFrame(rows)
    df["ts"] = pd.to_datetime(df["ts"])
    return df


def _failures(n, start=T0, spacing_s=10, src="1.2.3.4", host="WKS-0001", prefix="f"):
    return [{"event_id": f"{prefix}{i}", "ts": start + timedelta(seconds=i * spacing_s), "event_type": "auth",
             "src_ip": src, "host": host, "action": "login_failure", "user": "a.user"} for i in range(n)]


def _fan_out(targets, start=T0, src="10.10.10.5", user="admin", prefix="lm"):
    return [{"event_id": f"{prefix}{i}", "ts": start + timedelta(minutes=2 * i), "event_type": "auth",
             "action": "login_success", "src_ip": src, "host": host, "user": user} for i, host in enumerate(targets)]


# --- brute force -------------------------------------------------------------

def test_brute_force_rule_fires_on_failure_burst():
    alerts = rule_engine.run_rules(_events(_failures(6)), _RULES["brute_force"])
    assert len(alerts) == 1
    assert alerts[0]["severity"] == "high"
    assert alerts[0]["mitre_technique"] == "T1110"


def test_brute_force_rule_silent_on_isolated_failures():
    assert rule_engine.run_rules(_events(_failures(6, spacing_s=3600)), _RULES["brute_force"]) == []


def test_brute_force_rule_escalates_severity_on_success():
    rows = _failures(6) + [{"event_id": "ok", "ts": T0 + timedelta(seconds=70), "event_type": "auth",
                            "src_ip": "1.2.3.4", "host": "WKS-0001", "action": "login_success", "user": "a.user"}]
    alerts = rule_engine.run_rules(_events(rows), _RULES["brute_force"])
    assert len(alerts) == 1
    assert alerts[0]["severity"] == "critical"


def test_brute_force_rule_rearms_for_a_second_burst():
    """Regression: the matcher used to stop at the first burst per source and
    host for the whole dataset, so a repeat attack days later went silent."""
    rows = _failures(6) + _failures(6, start=T0 + timedelta(days=2), prefix="g")
    assert len(rule_engine.run_rules(_events(rows), _RULES["brute_force"])) == 2


def test_alert_entities_come_from_evidence():
    alert = rule_engine.run_rules(_events(_failures(6)), _RULES["brute_force"])[0]
    assert alert["entities"] == {"hosts": ["WKS-0001"], "users": ["a.user"], "ips": ["1.2.3.4"]}


# --- port scan / distinct count ---------------------------------------------

def test_port_scan_rule_fires_on_many_distinct_ports():
    rows = [{"event_id": f"e{i}", "ts": T0 + timedelta(seconds=i * 5), "event_type": "network",
             "direction": "inbound", "src_ip": "9.9.9.9", "host": "DB-01", "dst_ip": "10.10.2.10", "port": 1000 + i}
            for i in range(12)]
    alerts = rule_engine.run_rules(_events(rows), _RULES["port_scan"])
    assert len(alerts) == 1
    assert len(alerts[0]["event_ids"]) == 12, "the rest of the burst belongs to the same alert"


def test_port_scan_rule_silent_on_outbound_traffic():
    """Lots of varied outbound connections is browsing, not a scan."""
    rows = [{"event_id": f"e{i}", "ts": T0 + timedelta(seconds=i * 5), "event_type": "network",
             "direction": "outbound", "src_ip": "10.10.10.5", "host": "WKS-0005", "port": 1000 + i}
            for i in range(12)]
    assert rule_engine.run_rules(_events(rows), _RULES["port_scan"]) == []


# --- lateral movement --------------------------------------------------------

def test_lateral_movement_fires_on_internal_fan_out():
    targets = ["DC-01", "DB-01", "DB-02", "FILE-01", "WEB-01", "WEB-02"]
    alerts = rule_engine.run_rules(_events(_fan_out(targets)), _RULES["lateral_movement"])
    assert len(alerts) == 1
    assert alerts[0]["mitre_tactic"] == "Lateral Movement"


def test_lateral_movement_alert_covers_targets_after_the_trigger():
    """Regression: evidence used to stop at the 4th target, so hosts reached
    afterwards were missing from the alert — and correlation, which joins on
    those hosts, split a kill chain in two."""
    targets = ["DC-01", "DB-01", "DB-02", "FILE-01", "WEB-01", "WEB-02"]
    alert = rule_engine.run_rules(_events(_fan_out(targets)), _RULES["lateral_movement"])[0]
    assert set(targets) <= set(alert["entities"]["hosts"])
    assert "WKS-0005" in alert["entities"]["hosts"], "the internal source address resolves to its host"


def test_lateral_movement_silent_on_external_sources():
    rows = _fan_out(["DC-01", "DB-01", "DB-02", "FILE-01"], src="8.8.8.8")
    assert rule_engine.run_rules(_events(rows), _RULES["lateral_movement"]) == []


def test_lateral_movement_rearms_for_a_second_burst():
    rows = _fan_out(["DC-01", "DB-01", "DB-02", "FILE-01"]) + \
        _fan_out(["DC-02", "WEB-01", "WEB-02", "WEB-03"], start=T0 + timedelta(days=1), prefix="lm2")
    assert len(rule_engine.run_rules(_events(rows), _RULES["lateral_movement"])) == 2


# --- impossible travel -------------------------------------------------------

def _logins(c1, c2, gap_minutes, user="trav.eler"):
    return _events([
        {"event_id": "e1", "ts": T0, "event_type": "auth", "action": "login_success",
         "user": user, "src_country": c1, "src_ip": "1.1.1.1", "host": "WKS-0001"},
        {"event_id": "e2", "ts": T0 + timedelta(minutes=gap_minutes), "event_type": "auth", "action": "login_success",
         "user": user, "src_country": c2, "src_ip": "2.2.2.2", "host": "WKS-0002"},
    ])


def test_impossible_travel_rule_fires_on_fast_country_change():
    alerts = rule_engine.run_rules(_logins("India", "United States", 10), _RULES["impossible_travel"])
    assert len(alerts) == 1
    assert alerts[0]["severity"] == "critical"


def test_impossible_travel_entities_exclude_incidental_hosts():
    alert = rule_engine.run_rules(_logins("India", "United States", 10), _RULES["impossible_travel"])[0]
    assert alert["entities"]["hosts"] == []
    assert alert["entities"]["users"] == ["trav.eler"]
    assert alert["entities"]["ips"] == ["1.1.1.1", "2.2.2.2"]


def test_impossible_travel_rule_silent_on_same_country():
    assert rule_engine.run_rules(_logins("India", "India", 10), _RULES["impossible_travel"]) == []


def test_impossible_travel_rule_silent_when_travel_is_plausible():
    assert rule_engine.run_rules(_logins("India", "United States", 60 * 24), _RULES["impossible_travel"]) == []


# --- exfiltration / volume spike --------------------------------------------

def _transfers(n, dst="8.8.8.8", size=30_000_000, start=T0, prefix="x"):
    return [{"event_id": f"{prefix}{i}", "ts": start + timedelta(seconds=i * 30), "event_type": "network",
             "direction": "outbound", "host": "DB-01", "src_ip": "10.10.2.10", "dst_ip": dst, "bytes_sent": size}
            for i in range(n)]


def test_data_exfiltration_fires_once_per_sustained_transfer():
    alerts = rule_engine.run_rules(_events(_transfers(8)), _RULES["data_exfiltration"])
    assert len(alerts) == 1
    assert len(alerts[0]["event_ids"]) == 8


def test_data_exfiltration_fires_at_the_threshold_crossing():
    alert = rule_engine.run_rules(_events(_transfers(5)), _RULES["data_exfiltration"])[0]
    assert pd.Timestamp(alert["ts"]) == pd.Timestamp(T0 + timedelta(seconds=30)), "60 MB is crossed on the 2nd 30 MB transfer"


def test_data_exfiltration_silent_on_internal_destination():
    assert rule_engine.run_rules(_events(_transfers(5, dst="10.10.1.10")), _RULES["data_exfiltration"]) == []


# --- suspicious PowerShell / pattern match ----------------------------------

def _process(command_line, i=0, process="powershell.exe", host="WKS-0007"):
    return {"event_id": f"p{i}", "ts": T0 + timedelta(minutes=i), "event_type": "process",
            "host": host, "user": "a.user", "process_name": process, "command_line": command_line}


ENCODED = "powershell.exe -NoP -W Hidden -enc " + "SQBFAFgAIAAoAE4AZQB3AC0ATwBiAGoAZQBjAHQAIABOAGUAdAAuAFcAZQBi" * 2


def test_suspicious_powershell_fires_on_encoded_command():
    alerts = rule_engine.run_rules(_events([_process(ENCODED)]), _RULES["suspicious_powershell"])
    assert len(alerts) == 1
    assert alerts[0]["mitre_technique"] == "T1059.001"


@pytest.mark.parametrize("command", [
    r"powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Scripts\inventory.ps1",
    "powershell.exe -NoProfile -Command Get-Service",
])
def test_suspicious_powershell_silent_on_admin_scripts(command):
    assert rule_engine.run_rules(_events([_process(command)]), _RULES["suspicious_powershell"]) == []


def test_suspicious_powershell_ignores_other_binaries():
    assert rule_engine.run_rules(_events([_process(ENCODED, process="notepad.exe")]), _RULES["suspicious_powershell"]) == []


def test_suspicious_powershell_groups_a_burst_into_one_alert():
    rows = [_process(ENCODED, i=i) for i in range(3)] + [_process(ENCODED, i=600)]  # 3 together, 1 ten hours later
    alerts = rule_engine.run_rules(_events(rows), _RULES["suspicious_powershell"])
    assert [len(a["event_ids"]) for a in alerts] == [3, 1]


# --- Sigma-style filter modifiers -------------------------------------------

def test_filter_modifiers():
    df = pd.DataFrame({"ip": ["10.10.1.1", "8.8.8.8", None], "name": ["alpha", "beta", "gamma"]})
    assert rule_engine.apply_filters(df, {"ip|startswith": "10.10."})["name"].tolist() == ["alpha"]
    assert rule_engine.apply_filters(df, {"name|in": ["beta", "gamma"]})["name"].tolist() == ["beta", "gamma"]
    assert rule_engine.apply_filters(df, {"name|contains": "mm"})["name"].tolist() == ["gamma"]
    assert rule_engine.apply_filters(df, {"name|re": "^b"})["name"].tolist() == ["beta"]
    assert rule_engine.apply_filters(df, {"name": "alpha"})["name"].tolist() == ["alpha"]
    with pytest.raises(ValueError):
        rule_engine.apply_filters(df, {"name|fuzzy": "x"})
