"""Behavioral anomaly detection: bucket every host's activity into 1-hour
windows, build a small feature vector per (host, bucket), and score it with
an Isolation Forest.

This exists to catch what the Sigma-style rules in rule_engine.py cannot:
DNS beaconing has no single "bad" event — it's a *pattern* (many queries,
suspiciously regular timing) that only shows up once you aggregate. Rules
are for known signatures; this is for "this host doesn't behave like it
usually does."
"""

from __future__ import annotations

import uuid

import numpy as np
import pandas as pd
from sklearn.ensemble import IsolationForest

from .. import mitre

BUCKET = "1h"

FEATURE_COLS = [
    "event_count", "auth_failure_count", "distinct_dst_ips", "total_bytes_out",
    "distinct_ports_inbound", "dns_query_count", "distinct_domains", "dns_interval_std",
]

# Large sentinel for "not enough DNS queries this hour to judge regularity" —
# must look like LOW suspicion, and beaconing is flagged by LOW std, so the
# fill value has to be large, not zero (zero would read as maximally regular).
NO_SIGNAL_STD = 3600.0


def extract_features(df: pd.DataFrame, bucket: str = BUCKET) -> pd.DataFrame:
    """One row per (host, time bucket) covering the full span of df, zero
    (or no-signal) filled for buckets where a host had no matching events —
    quiet hours are the majority class Isolation Forest learns as normal."""
    work = df.copy()
    work["bucket"] = work["ts"].dt.floor(bucket)
    hosts = work["host"].dropna().unique()
    buckets = pd.date_range(work["bucket"].min(), work["bucket"].max(), freq=bucket)
    feat = pd.DataFrame(
        list(pd.MultiIndex.from_product([hosts, buckets])), columns=["host", "bucket"]
    )

    def _merge(series: pd.Series, name: str) -> None:
        nonlocal feat
        feat = feat.merge(series.rename(name).reset_index(), on=["host", "bucket"], how="left")

    _merge(work.groupby(["host", "bucket"]).size(), "event_count")

    auth = work[work["event_type"] == "auth"]
    _merge(auth[auth["outcome"] == "failure"].groupby(["host", "bucket"]).size(), "auth_failure_count")

    net_out = work[(work["event_type"] == "network") & (work["direction"] == "outbound")]
    _merge(net_out.groupby(["host", "bucket"])["dst_ip"].nunique(), "distinct_dst_ips")
    _merge(net_out.groupby(["host", "bucket"])["bytes_sent"].sum(), "total_bytes_out")

    net_in = work[(work["event_type"] == "network") & (work["direction"] == "inbound")]
    _merge(net_in.groupby(["host", "bucket"])["port"].nunique(), "distinct_ports_inbound")

    dns = work[work["event_type"] == "dns"]
    _merge(dns.groupby(["host", "bucket"]).size(), "dns_query_count")
    _merge(dns.groupby(["host", "bucket"])["domain"].nunique(), "distinct_domains")

    def _interval_std(group: pd.DataFrame) -> float:
        times = group.sort_values("ts")["ts"]
        if len(times) < 3:
            return np.nan
        return times.diff().dropna().dt.total_seconds().std()

    if not dns.empty:
        interval_std = dns.groupby(["host", "bucket"]).apply(_interval_std, include_groups=False)
        _merge(interval_std, "dns_interval_std")
    else:
        feat["dns_interval_std"] = np.nan

    for col in FEATURE_COLS:
        if col not in feat.columns:
            feat[col] = 0.0
    feat["dns_interval_std"] = feat["dns_interval_std"].fillna(NO_SIGNAL_STD)
    other_cols = [c for c in FEATURE_COLS if c != "dns_interval_std"]
    feat[other_cols] = feat[other_cols].fillna(0.0)
    return feat


def _matrix(feat: pd.DataFrame) -> np.ndarray:
    raw = feat[FEATURE_COLS].to_numpy(dtype=float)
    # log1p compresses the heavy-tailed count/byte columns so Isolation
    # Forest isn't effectively just thresholding on raw byte volume.
    return np.sign(raw) * np.log1p(np.abs(raw))


def fit_model(feat: pd.DataFrame, contamination: float = 0.03, random_state: int = 42) -> IsolationForest:
    """Fit on active host-hours only (see score_anomalies)."""
    active = feat[feat["event_count"] > 0]
    model = IsolationForest(contamination=contamination, random_state=random_state, n_estimators=200)
    return model.fit(_matrix(active))


def score_with(model: IsolationForest, feat: pd.DataFrame) -> pd.DataFrame:
    """Score host-hours with an already-fitted model — how a streaming
    deployment works: train on history, score each hour as it closes."""
    feat = feat[feat["event_count"] > 0].reset_index(drop=True)
    if feat.empty:
        return feat.assign(anomaly_score=pd.Series(dtype=float), is_anomaly=pd.Series(dtype=bool))
    X = _matrix(feat)
    out = feat.copy()
    out["anomaly_score"] = -model.decision_function(X)
    out["is_anomaly"] = model.predict(X) == -1
    return out


def score_anomalies(feat: pd.DataFrame, contamination: float = 0.03, random_state: int = 42) -> pd.DataFrame:
    """Scores every (host, bucket) row with event_count > 0 — a silent hour
    tells us nothing about *how* a host behaves, and including thousands of
    identical all-zero rows would just spend the contamination budget on
    "active vs idle" instead of on comparing active hours to each other.
    Returns only the scored (non-idle) rows, with anomaly_score (higher =
    more anomalous) and is_anomaly columns added."""
    if feat[feat["event_count"] > 0].empty:
        return score_with(None, feat)
    return score_with(fit_model(feat, contamination, random_state), feat)


# Every technique _explain() below can attribute an anomaly to — used by the
# ATT&CK coverage view. Keep in sync with the branches of _explain().
EXPLAINED_TECHNIQUES = ("T1071", "T1041", "T1110", "T1595")


def _explain(row: pd.Series) -> tuple[str, str | None, str | None, str | None]:
    """Heuristic "why did this fire" on top of the opaque IsolationForest
    score — turns a bare anomaly score into something an analyst (or a
    reviewer of this project) can act on without reading model internals."""
    if row["dns_query_count"] >= 15 and row["dns_interval_std"] < 15:
        info = mitre.describe("T1071")
        desc = (
            f"{int(row['dns_query_count'])} DNS queries in one hour at a near-constant "
            f"interval (std {row['dns_interval_std']:.1f}s) — looks like scripted C2 "
            f"beaconing, not human browsing."
        )
        return desc, info["tactic"], "T1071", info["name"]
    if row["total_bytes_out"] > 5_000_000:
        info = mitre.describe("T1041")
        desc = f"{row['total_bytes_out'] / 1_000_000:.1f} MB sent outbound in one hour, well above this host's norm."
        return desc, info["tactic"], "T1041", info["name"]
    if row["auth_failure_count"] >= 3:
        info = mitre.describe("T1110")
        desc = f"{int(row['auth_failure_count'])} authentication failures in one hour on this host."
        return desc, info["tactic"], "T1110", info["name"]
    if row["distinct_ports_inbound"] >= 5:
        info = mitre.describe("T1595")
        desc = f"{int(row['distinct_ports_inbound'])} distinct inbound ports touched in one hour."
        return desc, info["tactic"], "T1595", info["name"]
    return (
        "This host's activity profile this hour deviates from its established baseline "
        "across several behavioral features, without matching a single known pattern.",
        None, None, None,
    )


def generate_anomaly_alerts(
    scored: pd.DataFrame,
    events: pd.DataFrame,
    top_n: int = 20,
    bucket: str = BUCKET,
    high_cut: float | None = None,
) -> list[dict]:
    """`high_cut` is the score above which an alert is high rather than
    medium; by default the 97th percentile of `scored`. A streaming caller
    scoring one hour at a time passes the cut from its training data."""
    if scored.empty:
        return []
    work = events.copy()
    work["bucket"] = work["ts"].dt.floor(bucket)
    anomalies = scored[scored["is_anomaly"]].sort_values("anomaly_score", ascending=False).head(top_n)
    if anomalies.empty:
        return []
    if high_cut is None:
        high_cut = scored["anomaly_score"].quantile(0.97)
    alerts = []
    for _, row in anomalies.iterrows():
        description, tactic, technique, technique_name = _explain(row)
        related = work[(work["host"] == row["host"]) & (work["bucket"] == row["bucket"])]
        alerts.append({
            "alert_id": uuid.uuid4().hex[:12],
            "ts": row["bucket"],
            "source": "anomaly_isolation_forest",
            "title": "Anomalous host behavior (Isolation Forest)",
            "severity": "high" if row["anomaly_score"] >= high_cut else "medium",
            "mitre_tactic": tactic,
            "mitre_technique": technique,
            "mitre_technique_name": technique_name,
            "entity": row["host"],
            # Host only: the linked events are everything this host did in
            # the hour, so their users/IPs are mostly ordinary background
            # traffic and would make correlation join unrelated alerts.
            "entities": {"hosts": [str(row["host"])], "users": [], "ips": []},
            "description": description,
            "event_ids": related["event_id"].tolist()[:50],
            "score": float(row["anomaly_score"]),
        })
    return alerts
