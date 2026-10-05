from datetime import datetime, timedelta

import pandas as pd

from socdash.detection import anomaly

_BLANK = {
    "user": None, "src_ip": None, "src_country": None, "dst_ip": None, "direction": None,
    "action": None, "outcome": None, "port": None, "protocol": None, "bytes_sent": None,
    "bytes_received": None, "process_name": None, "domain": None,
}


def _event(event_id: str, ts: datetime, host: str, event_type: str, **overrides) -> dict:
    row = dict(_BLANK, event_id=event_id, ts=ts, host=host, event_type=event_type)
    row.update(overrides)
    return row


def _df(rows: list[dict]) -> pd.DataFrame:
    df = pd.DataFrame(rows)
    df["ts"] = pd.to_datetime(df["ts"])
    return df


def test_extract_features_shape_and_columns():
    base = datetime(2026, 1, 1, 0, 0, 0)
    rows = [
        _event(f"e{i}", base + timedelta(minutes=i), "WKS-0001", "network",
               direction="outbound", dst_ip="8.8.8.8", bytes_sent=1000)
        for i in range(3)
    ]
    feat = anomaly.extract_features(_df(rows))
    assert set(anomaly.FEATURE_COLS).issubset(feat.columns)
    assert {"host", "bucket"}.issubset(feat.columns)


def test_score_anomalies_flags_injected_outlier():
    base = datetime(2026, 1, 1, 0, 0, 0)
    rows = []
    for h in range(20):
        for i in range(2):
            rows.append(_event(f"bg-{h}-{i}", base + timedelta(hours=h, minutes=i), f"WKS-{h:04d}", "network",
                                direction="outbound", dst_ip="8.8.8.8", bytes_sent=1000))
    for i in range(5):
        rows.append(_event(f"out-{i}", base + timedelta(hours=2, minutes=i), "WKS-OUTLIER", "network",
                            direction="outbound", dst_ip="8.8.8.8", bytes_sent=80_000_000))

    feat = anomaly.extract_features(_df(rows))
    scored = anomaly.score_anomalies(feat, contamination=0.05)
    outlier_rows = scored[scored["host"] == "WKS-OUTLIER"]
    assert not outlier_rows.empty
    assert outlier_rows["is_anomaly"].any()


def test_score_anomalies_excludes_idle_buckets_from_output():
    base = datetime(2026, 1, 1, 0, 0, 0)
    # Two events, ten hours apart, on the same host: extract_features spans
    # the full range in 1h buckets, so the hours between them are idle.
    rows = [
        _event("e1", base, "WKS-0001", "network", direction="outbound", dst_ip="8.8.8.8", bytes_sent=1000),
        _event("e2", base + timedelta(hours=10), "WKS-0001", "network", direction="outbound", dst_ip="8.8.8.8", bytes_sent=1000),
    ]
    feat = anomaly.extract_features(_df(rows))
    assert (feat["event_count"] == 0).any()
    scored = anomaly.score_anomalies(feat)
    assert (scored["event_count"] == 0).sum() == 0


def test_generate_anomaly_alerts_explains_beaconing():
    base = datetime(2026, 1, 1, 0, 0, 0)
    rows = []
    for h in range(10):
        for i in range(2):
            rows.append(_event(f"bg-{h}-{i}", base + timedelta(hours=h, minutes=i * 10), f"WKS-{h:04d}", "dns",
                                domain="example.com"))
    for i in range(30):
        rows.append(_event(f"beacon-{i}", base + timedelta(hours=2, seconds=i * 60), "WKS-BEACON", "dns",
                            domain="xqplofk3n.net"))

    events = _df(rows)
    feat = anomaly.extract_features(events)
    scored = anomaly.score_anomalies(feat, contamination=0.1)
    alerts = anomaly.generate_anomaly_alerts(scored, events, top_n=5)
    assert alerts
    top = alerts[0]
    assert top["entity"] == "WKS-BEACON"
    assert "beaconing" in top["description"].lower() or "c2" in top["description"].lower()
    assert top["mitre_technique"] == "T1071"
