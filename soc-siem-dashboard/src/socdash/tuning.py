"""Detection tuning against ground truth: what happens to recall and false
positives if a threshold moves.

Every detection threshold is a trade. Lower it and the rule catches quieter
attacks, but also fires on ordinary noise; raise it and the queue is
cleaner, but a careful attacker slips underneath. With synthetic ground
truth the trade can be measured instead of argued about:

* rule sweeps re-run one rule across a range of values for one parameter
  and score each run — attack instances caught (recall), and alerts that
  touched no attack activity at all (false positives);
* the anomaly alert budget ranks every scored host-hour and asks, for the
  top k: how many were attack hours (precision@k), and how many attack
  instances do those k hours cover (recall@k). Raising an alert is the
  expensive part of anomaly detection — an analyst has to look at it — so
  "how many a day can we afford" is the real tuning knob.
"""

from __future__ import annotations

import copy

import pandas as pd

from .detection import anomaly, rule_engine
from .evaluation import SCENARIO_TECHNIQUE, scenario_instances

# The parameters worth sweeping, with ranges wide enough to show both
# failure modes. `default` is read from the rule file, not repeated here.
SWEEPS: dict[str, dict] = {
    "brute_force": {"param": "min_failures", "values": [1, 2, 3, 4, 5, 6, 8, 10, 12, 15, 20],
                    "label": "failures before a success"},
    "port_scan": {"param": "min_distinct", "values": [2, 3, 4, 5, 6, 8, 10, 15, 20, 30, 40],
                  "label": "distinct ports in 5 min"},
    "lateral_movement": {"param": "min_distinct", "values": [1, 2, 3, 4, 5, 6, 7, 8, 10],
                         "label": "distinct hosts in 30 min"},
    "data_exfiltration": {"param": "bytes_sent_threshold",
                          "values": [int(v * 1_000_000) for v in (0.02, 0.05, 0.1, 0.2, 0.5, 1, 5, 20, 60, 150, 300, 600)],
                          "label": "bytes sent in 10 min"},
    "impossible_travel": {"param": "max_speed_kmh", "values": [100, 300, 500, 700, 900, 1200, 2000, 5000, 10000],
                          "label": "max plausible speed (km/h)"},
}

SWEEP_COLUMNS = ["value", "alerts", "true_positives", "false_positives", "instances", "detected", "recall", "is_default"]
BUDGET_COLUMNS = ["k", "score", "attack_hour", "true_positives", "precision", "instances_covered", "recall"]


def _rule(rules: list[dict], rule_id: str) -> dict:
    for rule in rules:
        if rule["id"] == rule_id:
            return rule
    raise KeyError(f"no rule with id {rule_id!r}")


def sweep_rule(
    events: pd.DataFrame,
    rule_id: str,
    param: str | None = None,
    values: list | None = None,
    rules: list[dict] | None = None,
) -> pd.DataFrame:
    """Re-run one rule at each value of `param`. Recall counts the attack
    instances of the rule's own technique that any alert touched; a false
    positive is an alert touching no injected activity at all."""
    rules = rules if rules is not None else rule_engine.load_rules()
    base = _rule(rules, rule_id)
    spec = SWEEPS.get(rule_id, {})
    param = param or spec["param"]
    values = list(values if values is not None else spec["values"])
    default = base["logic"][param]
    if default not in values:
        values = sorted([*values, default])

    tagged = events[events["scenario_id"].notna()]
    instance_of = dict(zip(tagged["event_id"], tagged["scenario_id"]))
    instances = scenario_instances(events)
    technique = base["mitre"]["technique"]
    targets = set(instances.loc[instances["scenario_tag"].map(SCENARIO_TECHNIQUE) == technique, "scenario_id"])

    rows = []
    for value in values:
        rule = copy.deepcopy(base)
        rule["logic"][param] = value
        alerts = rule_engine.run_rules(events, [rule])
        touched_per_alert = [{instance_of[e] for e in a["event_ids"] if e in instance_of} for a in alerts]
        true_positives = sum(1 for t in touched_per_alert if t)
        detected = set().union(*touched_per_alert) & targets if touched_per_alert else set()
        rows.append({
            "value": value,
            "alerts": len(alerts),
            "true_positives": true_positives,
            "false_positives": len(alerts) - true_positives,
            "instances": len(targets),
            "detected": len(detected),
            "recall": len(detected) / len(targets) if targets else float("nan"),
            "is_default": value == default,
        })
    return pd.DataFrame(rows, columns=SWEEP_COLUMNS)


def alert_budget(events: pd.DataFrame, contamination: float = 0.03, max_k: int = 100) -> pd.DataFrame:
    """Precision@k and instance recall@k over host-hours ranked by anomaly
    score. Recall is over every injected instance, including the ones no
    host-hour-level model could see (an impossible-travel login is two
    ordinary events) — so it plateaus well below 1, and that plateau is the
    point: past it, more budget buys only false positives."""
    scored = anomaly.score_anomalies(anomaly.extract_features(events), contamination=contamination)
    if scored.empty:
        return pd.DataFrame(columns=BUDGET_COLUMNS)
    tagged = events[events["scenario_id"].notna()]
    buckets = tagged["ts"].dt.floor(anomaly.BUCKET)
    instances_by_hour = tagged.groupby([tagged["host"], buckets])["scenario_id"].agg(set).to_dict()
    total = tagged["scenario_id"].nunique()

    ranked = scored.sort_values("anomaly_score", ascending=False).head(max_k).reset_index(drop=True)
    covered: set[str] = set()
    rows = []
    true_positives = 0
    for k, row in enumerate(ranked.itertuples(index=False), start=1):
        hour_instances = instances_by_hour.get((row.host, row.bucket), set())
        true_positives += bool(hour_instances)
        covered |= hour_instances
        rows.append({
            "k": k,
            "score": row.anomaly_score,
            "attack_hour": bool(hour_instances),
            "true_positives": true_positives,
            "precision": true_positives / k,
            "instances_covered": len(covered),
            "recall": len(covered) / total if total else float("nan"),
        })
    return pd.DataFrame(rows, columns=BUDGET_COLUMNS)
