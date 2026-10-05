"""Scores the detection stack against the synthetic generator's ground truth.

NSL-KDD validation scores one model against one label per record. This
scores the whole stack the way a detection-engineering team would:

* coverage — of the attack instances injected, how many did anything catch,
  and with what (rules, anomaly detection, both);
* precision — of the alerts each detector raised, how many touched any
  injected attack activity at all;
* time-to-detect — from an instance's first event to its first alert;
* correlation quality — whether a multi-stage campaign's detected stages
  ended up in one incident, and whether incidents mix unrelated attacks.

Stated up front: an anomaly alert links every event its host produced that
hour, so it is credited with any attack instance active on that host in
that hour even if the score was driven by something else. Anomaly recall is
therefore an upper bound.
"""

from __future__ import annotations

from collections import defaultdict

import numpy as np
import pandas as pd

from . import mitre
from .detection.anomaly import EXPLAINED_TECHNIQUES

ANOMALY_SOURCE = "anomaly_isolation_forest"
# Anomaly scoring is an hourly batch: an hour can only be scored once it has
# closed, so that's the earliest moment an anomaly alert could have existed.
ANOMALY_LATENCY = pd.Timedelta(hours=1)

SCENARIO_TECHNIQUE = {
    "port_scan": "T1595",
    "impossible_travel": "T1078",
    "suspicious_process": "T1059.001",
    "brute_force": "T1110",
    "lateral_movement": "T1021",
    "dns_beaconing": "T1071",
    "data_exfiltration": "T1041",
}

OUTCOMES = ["rules only", "anomaly only", "both", "missed"]

_INSTANCE_COLUMNS = ["scenario_id", "scenario_tag", "campaign_id", "first_ts", "last_ts", "n_events"]


def scenario_instances(events: pd.DataFrame) -> pd.DataFrame:
    """One row per injected attack instance (a standalone scenario or one
    stage of a campaign)."""
    if "scenario_id" not in events:
        return pd.DataFrame(columns=_INSTANCE_COLUMNS)
    tagged = events[events["scenario_id"].notna()]
    if tagged.empty:
        return pd.DataFrame(columns=_INSTANCE_COLUMNS)
    return tagged.groupby("scenario_id").agg(
        scenario_tag=("scenario_tag", "first"),
        campaign_id=("campaign_id", "first"),
        first_ts=("ts", "min"),
        last_ts=("ts", "max"),
        n_events=("event_id", "size"),
    ).reset_index()


def alert_matches(events: pd.DataFrame, alerts: pd.DataFrame) -> pd.DataFrame:
    """One row per (alert, attack instance it touched). An alert touching no
    instance appears once with scenario_id = None: a false positive."""
    tagged = events[events["scenario_id"].notna()] if "scenario_id" in events else events.iloc[0:0]
    instance_of = dict(zip(tagged["event_id"], tagged["scenario_id"]))
    rows = []
    for _, alert in alerts.iterrows():
        is_anomaly = alert["source"] == ANOMALY_SOURCE
        base = {
            "alert_id": alert["alert_id"],
            "source": alert["source"],
            "detector": "anomaly" if is_anomaly else "rule",
            "detected_at": pd.Timestamp(alert["ts"]) + (ANOMALY_LATENCY if is_anomaly else pd.Timedelta(0)),
            "incident_id": alert.get("incident_id"),
        }
        touched = {instance_of[e] for e in alert["event_ids"] if e in instance_of}
        for scenario_id in sorted(touched) or [None]:
            rows.append({**base, "scenario_id": scenario_id})
    return pd.DataFrame(rows, columns=["alert_id", "source", "detector", "detected_at", "incident_id", "scenario_id"])


def instance_outcomes(instances: pd.DataFrame, matches: pd.DataFrame) -> pd.DataFrame:
    """Per instance: which detector families caught it and how fast."""
    out = instances.copy()
    if out.empty:
        extra = ["technique", "by_rule", "by_anomaly", "detected", "outcome", "first_detected", "first_detector", "ttd_minutes"]
        return out.reindex(columns=[*out.columns, *extra])
    hit = matches.dropna(subset=["scenario_id"])
    rule_hits = set(hit.loc[hit["detector"] == "rule", "scenario_id"])
    anomaly_hits = set(hit.loc[hit["detector"] == "anomaly", "scenario_id"])
    earliest = hit.sort_values("detected_at").drop_duplicates("scenario_id").set_index("scenario_id")
    first_detected = earliest["detected_at"]

    out["technique"] = out["scenario_tag"].map(SCENARIO_TECHNIQUE)
    out["by_rule"] = out["scenario_id"].isin(rule_hits)
    out["by_anomaly"] = out["scenario_id"].isin(anomaly_hits)
    out["detected"] = out["by_rule"] | out["by_anomaly"]
    out["outcome"] = np.select(
        [out["by_rule"] & out["by_anomaly"], out["by_rule"], out["by_anomaly"]],
        ["both", "rules only", "anomaly only"],
        default="missed",
    )
    out["first_detected"] = out["scenario_id"].map(first_detected)
    out["first_detector"] = out["scenario_id"].map(earliest["detector"])
    out["ttd_minutes"] = (out["first_detected"] - out["first_ts"]).dt.total_seconds() / 60
    return out


def technique_summary(outcomes: pd.DataFrame) -> pd.DataFrame:
    if outcomes.empty:
        return pd.DataFrame(columns=["scenario_tag", "technique", "instances", *OUTCOMES, "detected", "recall", "median_ttd_minutes"])
    counts = pd.crosstab(outcomes["scenario_tag"], outcomes["outcome"]).reindex(columns=OUTCOMES, fill_value=0)
    summary = counts.reset_index()
    summary["technique"] = summary["scenario_tag"].map(SCENARIO_TECHNIQUE)
    summary["instances"] = summary[OUTCOMES].sum(axis=1)
    summary["detected"] = summary["instances"] - summary["missed"]
    summary["recall"] = summary["detected"] / summary["instances"]
    ttd = outcomes.groupby("scenario_tag")["ttd_minutes"].median()
    summary["median_ttd_minutes"] = summary["scenario_tag"].map(ttd)
    columns = ["scenario_tag", "technique", "instances", *OUTCOMES, "detected", "recall", "median_ttd_minutes"]
    return summary[columns].sort_values("recall").reset_index(drop=True)


def detector_precision(matches: pd.DataFrame) -> pd.DataFrame:
    """Per detector: alerts raised and how many touched any attack activity."""
    if matches.empty:
        return pd.DataFrame(columns=["source", "alerts", "true_positives", "false_positives", "precision"])
    per_alert = (
        matches.assign(hit=matches["scenario_id"].notna())
        .groupby(["source", "alert_id"])["hit"].any()
        .reset_index()
    )
    summary = per_alert.groupby("source").agg(alerts=("hit", "size"), true_positives=("hit", "sum")).reset_index()
    summary["false_positives"] = summary["alerts"] - summary["true_positives"]
    summary["precision"] = summary["true_positives"] / summary["alerts"]
    return summary.sort_values("precision").reset_index(drop=True)


def campaign_reconstruction(instances: pd.DataFrame, matches: pd.DataFrame) -> pd.DataFrame:
    """Per campaign: stages injected vs detected, and how many incidents the
    detected stages were split across — 1 means correlation told the whole
    story as a single incident."""
    columns = ["campaign_id", "stages", "stages_detected", "incidents", "reconstructed"]
    campaigns = instances[instances["campaign_id"].notna()]
    if campaigns.empty:
        return pd.DataFrame(columns=columns)
    hit = matches.dropna(subset=["scenario_id"]).merge(campaigns[["scenario_id", "campaign_id"]], on="scenario_id")
    rows = []
    for campaign_id, stages in campaigns.groupby("campaign_id"):
        caught = hit[hit["campaign_id"] == campaign_id]
        n_incidents = caught["incident_id"].dropna().nunique()
        rows.append({
            "campaign_id": campaign_id,
            "stages": len(stages),
            "stages_detected": caught["scenario_id"].nunique(),
            "incidents": n_incidents,
            "reconstructed": n_incidents == 1,
        })
    return pd.DataFrame(rows, columns=columns)


def incident_purity(instances: pd.DataFrame, matches: pd.DataFrame) -> pd.DataFrame:
    """Per incident: how many distinct attacks (a campaign counts as one) its
    alerts touched. Exactly one is the goal; more means correlation merged
    unrelated activity, zero means the incident is false positives only."""
    columns = ["incident_id", "alerts", "attacks", "verdict"]
    if matches.empty or matches["incident_id"].isna().all():
        return pd.DataFrame(columns=columns)
    attack_of = dict(zip(instances["scenario_id"], instances["campaign_id"].fillna(instances["scenario_id"])))
    per = (
        matches.assign(attack=matches["scenario_id"].map(attack_of))
        .groupby("incident_id")
        .agg(alerts=("alert_id", "nunique"), attacks=("attack", "nunique"))
        .reset_index()
    )
    per["verdict"] = np.select(
        [per["attacks"] == 0, per["attacks"] == 1], ["false positives only", "one attack"], default="merged attacks",
    )
    return per[columns]


def attack_coverage(rules: list[dict], alerts: pd.DataFrame, outcomes: pd.DataFrame) -> pd.DataFrame:
    """One row per technique in the local ATT&CK catalog: which detectors can
    produce it, alerts it received, and how many injected instances were
    caught — the data behind the coverage grid."""
    detectors: dict[str, list[str]] = defaultdict(list)
    for rule in rules:
        detectors[rule["mitre"]["technique"]].append(rule["id"])
    for technique in EXPLAINED_TECHNIQUES:
        detectors[technique].append("anomaly")
    alert_counts = alerts["mitre_technique"].value_counts() if not alerts.empty else pd.Series(dtype=int)
    injected = outcomes.groupby("technique")["detected"].agg(["size", "sum"]) if not outcomes.empty else None
    rows = []
    for technique, info in mitre.TECHNIQUES.items():
        has_injected = injected is not None and technique in injected.index
        rows.append({
            "technique": technique,
            "name": info["name"],
            "tactic": info["tactic"],
            "detectors": sorted(detectors.get(technique, [])),
            "alerts": int(alert_counts.get(technique, 0)),
            "injected": int(injected.loc[technique, "size"]) if has_injected else 0,
            "caught": int(injected.loc[technique, "sum"]) if has_injected else 0,
        })
    out = pd.DataFrame(rows)
    out["tactic_rank"] = out["tactic"].map(mitre.tactic_rank)
    return out.sort_values(["tactic_rank", "technique"]).drop(columns="tactic_rank").reset_index(drop=True)


def evaluate(events: pd.DataFrame, alerts: pd.DataFrame, rules: list[dict]) -> dict[str, pd.DataFrame]:
    # A suppressed alert never reached an analyst: it is not a detection.
    if "status" in alerts.columns:
        alerts = alerts[alerts["status"] != "suppressed"]
    instances = scenario_instances(events)
    matches = alert_matches(events, alerts)
    outcomes = instance_outcomes(instances, matches)
    return {
        "instances": instances,
        "matches": matches,
        "outcomes": outcomes,
        "techniques": technique_summary(outcomes),
        "precision": detector_precision(matches),
        "campaigns": campaign_reconstruction(instances, matches),
        "purity": incident_purity(instances, matches),
        "coverage": attack_coverage(rules, alerts, outcomes),
    }
