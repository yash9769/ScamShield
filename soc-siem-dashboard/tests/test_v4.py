"""The search language, incident attack graphs, threat intel and retro-hunts,
the watchlist, and alert suppression."""

from datetime import datetime, timedelta

import pandas as pd
import pytest

from socdash import evaluation, intel, pipeline, search
from socdash.detection import graph, rule_engine, suppression
from socdash.storage import db

T0 = datetime(2026, 1, 1, 10, 0, 0)


@pytest.fixture(scope="module")
def stored(tmp_path_factory):
    path = tmp_path_factory.mktemp("v4") / "soc.db"
    pipeline.run_pipeline(db_path=path, days=4, scenario_count=12, campaign_count=1, seed=42, end=datetime(2026, 9, 6))
    conn = db.connect(path)
    frames = db.read_events(conn), db.read_alerts(conn), db.read_incidents(conn)
    conn.close()
    return path, frames


def _events(rows):
    base = {c: None for c in db.EVENT_COLUMNS}
    df = pd.DataFrame([{**base, "event_id": f"e{i}", "ts": T0 + timedelta(minutes=i), **r} for i, r in enumerate(rows)])
    df["ts"] = pd.to_datetime(df["ts"])
    for col in ("port", "bytes_sent"):
        df[col] = pd.to_numeric(df[col])
    return df


SAMPLE = _events([
    {"event_type": "auth", "host": "WKS-0001", "user": "a.b", "outcome": "failure", "src_ip": "203.0.113.9"},
    {"event_type": "auth", "host": "WKS-0001", "user": "a.b", "outcome": "failure", "src_ip": "203.0.113.9"},
    {"event_type": "auth", "host": "DC-01", "user": "c.d", "outcome": "success", "src_ip": "10.10.10.5"},
    {"event_type": "network", "host": "WKS-0002", "direction": "outbound", "dst_ip": "198.51.100.7", "bytes_sent": 5_000_000, "port": 443},
    {"event_type": "network", "host": "WKS-0002", "direction": "outbound", "dst_ip": "10.10.10.9", "bytes_sent": 900, "port": 445},
    {"event_type": "dns", "host": "WKS-0003", "domain": "x7k2q9zr4mf.info", "scenario_tag": "dns_beaconing", "scenario_id": "s1"},
    {"event_type": "process", "host": "WKS-0003", "user": "e.f", "process_name": "powershell.exe",
     "command_line": "powershell.exe -nop -enc SQBFAFgA"},
])


# --- Search -------------------------------------------------------------------

def test_field_terms_wildcards_and_numbers():
    assert search.run(SAMPLE, "host=WKS-0001").matched == 2
    assert search.run(SAMPLE, "host=wks-000*").matched == 6
    assert search.run(SAMPLE, "bytes_sent>1000000").matched == 1
    assert search.run(SAMPLE, "event_type=network NOT dst_ip=10.10.*").matched == 1
    assert search.run(SAMPLE, "outcome=failure OR outcome=success").matched == 3
    assert search.run(SAMPLE, '"-enc"').matched == 1  # bare phrase, any text field


def test_stats_top_and_where_pipeline():
    result = search.run(SAMPLE, "* | stats count, dc(user) as users by event_type | where count >= 2 | sort -count")
    assert list(result.frame["event_type"]) == ["auth", "network"]
    assert list(result.frame["count"]) == [3, 2]
    assert result.chart == "bar"
    top = search.run(SAMPLE, "event_type=auth | top limit=1 host")
    assert top.frame.iloc[0]["host"] == "WKS-0001" and top.frame.iloc[0]["count"] == 2


def test_timechart_folds_series_past_the_palette_into_other():
    rows = [{"event_type": "dns", "host": f"H{i % 11}", "domain": "a.com"} for i in range(44)]
    result = search.run(_events(rows), "* | timechart span=1h count by host")
    assert result.chart == "timechart"
    series = [c for c in result.frame.columns if c != "time"]
    assert len(series) == search.MAX_SERIES + 1 and series[-1] == "OTHER"
    assert result.frame[series].to_numpy().sum() == 44  # nothing lost in the fold


def test_ground_truth_is_not_searchable():
    with pytest.raises(search.SearchError):
        search.run(SAMPLE, "scenario_tag=dns_beaconing")
    assert "scenario_id" not in search.run(SAMPLE, "*").frame.columns


@pytest.mark.parametrize("query", [
    "stats count",               # command with no search terms first
    "* | bogus",                 # unknown command
    "nofield=1",                 # unknown field
    "* | stats sum by host",     # aggregate without a field
    "* | where count",           # not a comparison
    'host="unclosed',            # quote
    "a OR",                      # dangling OR
    "* |",                       # empty command
])
def test_malformed_queries_raise_search_error(query):
    with pytest.raises(search.SearchError):
        search.run(SAMPLE, query)


def test_saved_searches_all_run(stored):
    _, (events, _, _) = stored
    for query in search.SAVED_SEARCHES.values():
        search.run(events, query)


# --- Attack graph ---------------------------------------------------------------

def test_campaign_graph_has_directed_attack_path(stored):
    _, (events, alerts, incidents) = stored
    campaign = incidents.iloc[0]
    members = alerts[alerts["incident_id"] == campaign["incident_id"]]
    nodes, edges = graph.build(members, events)
    by_technique = {}
    for edge in edges:
        by_technique.setdefault(edge.technique, []).append(edge)
    # Exfiltration flows out of a host to an external address; C2 from a host to a domain.
    assert all(e.source.startswith("host:") and e.target.startswith("ip:") for e in by_technique["T1041"])
    assert any(e.target.startswith("domain:") for e in edges)
    # Lateral movement is host -> host, with the account in the label rather than a separate edge.
    lateral = by_technique["T1021"]
    assert all(e.source.startswith("host:") and e.target.startswith("host:") for e in lateral)
    assert all(any(" as " in a for a in e.actions) for e in lateral)
    assert not any(e.technique == "unattributed" and any(o.technique != "unattributed" and (o.source, o.target) == (e.source, e.target) for o in edges) for e in edges)

    laid = graph.layout(nodes)
    lanes = laid.assign(lane=laid["kind"].map(graph.LANES))
    assert ((lanes["y"] - lanes["lane"]).abs() < 0.5).all()  # offsets never cross into another lane
    assert not laid.duplicated(["x", "y"]).any()             # no two nodes on one spot


# --- Threat intel ------------------------------------------------------------

def test_sightings_sweep_and_feed_coverage(stored):
    _, (events, alerts, _) = stored
    feed = intel.feed()
    assert (feed["type"] == "ip").all() and feed["value"].is_unique
    found = intel.sightings(events, feed)
    assert set(found["value"]) <= set(feed["value"])
    coverage = intel.feed_coverage(events, feed)
    assert 0 < coverage["listed"] <= coverage["attack_ips"]

    target = found["value"].iloc[0]
    swept = intel.sweep(events, [target])
    touching = events[(events["src_ip"] == target) | (events["dst_ip"] == target)]
    assert set(swept["host"]) == set(touching["host"].dropna())
    assert swept["events"].sum() == len(touching)


def test_dga_domains_outscore_ordinary_ones():
    assert intel.domain_score("x7k2q9zr4mf3.info") > 0.7
    assert intel.domain_score("google.com") < 0.4
    assert intel.domain_score("localhost") == 0.0


def test_watchlist_roundtrip(tmp_path):
    conn = db.connect(tmp_path / "w.db")
    assert db.add_watchlist(conn, [{"value": "203.0.113.9", "type": "ip", "incident_id": "INC-1"},
                                   {"value": "evil.example.info", "type": "domain"}]) == 2
    assert db.add_watchlist(conn, [{"value": "203.0.113.9", "type": "ip", "note": "again"}]) == 0
    watch = db.read_watchlist(conn).set_index("value")
    assert watch.loc["203.0.113.9", "note"] == "again" and watch.loc["203.0.113.9", "incident_id"] == "INC-1"
    db.remove_watchlist(conn, ["evil.example.info"])
    assert list(db.read_watchlist(conn)["value"]) == ["203.0.113.9"]
    conn.close()


# --- Suppression -------------------------------------------------------------

def test_suppression_matching_and_expiry():
    alert = {"source": "port_scan", "entity": "203.0.113.9 → WEB-01"}
    assert suppression.matches(alert, {"source": "port_scan", "entity": "203.0.113.9*"})
    assert suppression.matches(alert, {"source": "*", "entity": "*web-01"})
    assert not suppression.matches(alert, {"source": "brute_force", "entity": "*"})
    now = datetime(2026, 1, 10)
    assert suppression.is_active({"expires_at": None}, now)
    assert suppression.is_active({"expires_at": "2026-01-11T00:00:00"}, now)
    assert not suppression.is_active({"expires_at": "2026-01-09T00:00:00"}, now)
    kept, dropped = suppression.apply(
        [alert, {"source": "brute_force", "entity": "x"}],
        [{"suppression_id": "SUP-1", "source": "port_scan", "entity": "*"},
         {"suppression_id": "SUP-2", "source": "*", "entity": "*", "expires_at": "2020-01-01T00:00:00"}],
        now,
    )
    assert [a["source"] for a in kept] == ["brute_force"]
    assert dropped[0]["status"] == "suppressed" and dropped[0]["suppressed_by"] == "SUP-1"


def test_suppressed_alerts_stay_out_of_incidents_and_evaluation(stored, tmp_path):
    path, (events, alerts, _) = stored
    copy = tmp_path / "sup.db"
    copy.write_bytes(path.read_bytes())
    target = alerts[alerts["source"] == "port_scan"].iloc[0]
    conn = db.connect(copy)
    db.add_suppression(conn, {"source": "port_scan", "entity": target["entity"], "reason": "approved scanner"})
    conn.close()

    summary = pipeline.detect_and_store(copy)
    conn = db.connect(copy)
    after = db.read_alerts(conn)
    conn.close()
    suppressed = after[after["status"] == "suppressed"]
    assert summary["suppressed"] == len(suppressed) >= 1
    assert suppressed["incident_id"].isna().all()
    assert set(suppressed["suppressed_by"]) == {db.read_suppressions(db.connect(copy)).iloc[0]["suppression_id"]}

    graded = evaluation.evaluate(events, after, rule_engine.load_rules())
    assert not set(graded["matches"]["alert_id"]) & set(suppressed["alert_id"])
