"""Entity risk scoring, in the spirit of risk-based alerting: rather than
treating every alert as its own page, attribute each alert's weight to the
entities it involves and let it decay over time. An entity collecting risk
from several detectors in a short span is worth a human's attention even if
no single alert was alarming on its own.
"""

from __future__ import annotations

import pandas as pd

from .correlation import SEVERITY_WEIGHT
from .entities import KINDS

RISK_COLUMNS = ["kind", "entity", "risk", "alerts", "detectors", "last_seen"]


def entity_risk(alerts: pd.DataFrame, now: pd.Timestamp | None = None, half_life_hours: float = 24.0) -> pd.DataFrame:
    """One row per (kind, entity): time-decayed risk, raw alert count,
    distinct detectors, last alert time. `now` defaults to the latest alert,
    so a historical dataset is scored as of its own end, not wall-clock time."""
    rows = []
    for _, alert in alerts.iterrows():
        weight = SEVERITY_WEIGHT.get(alert["severity"], 1)
        entities = alert.get("entities") or {}
        for kind in KINDS:
            for value in entities.get(kind, []):
                rows.append({"kind": kind[:-1], "entity": value, "ts": alert["ts"],
                             "weight": weight, "source": alert["source"]})
    if not rows:
        return pd.DataFrame(columns=RISK_COLUMNS)
    df = pd.DataFrame(rows)
    now = now if now is not None else df["ts"].max()
    age_hours = ((now - df["ts"]).dt.total_seconds() / 3600).clip(lower=0)
    df["risk"] = df["weight"] * 0.5 ** (age_hours / half_life_hours)
    out = df.groupby(["kind", "entity"]).agg(
        risk=("risk", "sum"), alerts=("weight", "size"),
        detectors=("source", "nunique"), last_seen=("ts", "max"),
    ).reset_index()
    out["risk"] = out["risk"].round(1)
    return out.sort_values("risk", ascending=False)[RISK_COLUMNS].reset_index(drop=True)
