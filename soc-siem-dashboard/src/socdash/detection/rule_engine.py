"""A small Sigma-inspired rule engine: YAML files carry metadata (id, title,
severity, MITRE mapping) and matcher parameters; the actual pattern-matching
logic lives here in Python, keyed by `logic.type`. Real Sigma backends work
the same way — the rule format is portable, the matching backend isn't.

Filters follow Sigma's field-modifier syntax: `field: value` is equality,
`field|startswith: value` (also endswith / contains / in / re) applies a
modifier.

Every alert carries `entities` (hosts / users / external IPs) taken from the
events that are its evidence — that is what correlation.py joins on.
"""

from __future__ import annotations

import uuid
from pathlib import Path

import pandas as pd
import yaml

from .. import mitre
from ..geo import COUNTRY_GEO, implied_speed_kmh
from . import entities as entity_util

RULES_DIR = Path(__file__).parent / "rules"


def load_rules(rules_dir: Path | None = None) -> list[dict]:
    rules_dir = rules_dir or RULES_DIR
    rules = []
    for path in sorted(rules_dir.glob("*.yml")):
        with open(path) as f:
            rules.append(yaml.safe_load(f))
    return rules


def _new_alert_id() -> str:
    return uuid.uuid4().hex[:12]


def _entity_label(key) -> str:
    key_tuple = key if isinstance(key, tuple) else (key,)
    return " → ".join(str(k) for k in key_tuple)


def _truncate(text: str, limit: int) -> str:
    return text if len(text) <= limit else text[: limit - 1] + "…"


def _alert(rule: dict, ts, entity: str, description: str, evidence: pd.DataFrame,
           severity: str | None = None, kinds: tuple[str, ...] = entity_util.KINDS) -> dict:
    technique = rule["mitre"]["technique"]
    info = mitre.describe(technique)
    return {
        "alert_id": _new_alert_id(),
        "ts": ts,
        "source": rule["id"],
        "title": rule["title"],
        "severity": severity or rule["severity"],
        "mitre_tactic": info["tactic"],
        "mitre_technique": technique,
        "mitre_technique_name": info["name"],
        "entity": entity,
        "entities": entity_util.from_events(evidence, kinds),
        "description": description,
        "event_ids": evidence["event_id"].tolist(),
        "score": None,
    }


def apply_filters(df: pd.DataFrame, filters: dict | None) -> pd.DataFrame:
    for key, value in (filters or {}).items():
        field, _, modifier = key.partition("|")
        col = df[field]
        text = col.astype(str)
        present = col.notna()
        if modifier == "":
            mask = col == value
        elif modifier == "startswith":
            mask = present & text.str.startswith(value)
        elif modifier == "endswith":
            mask = present & text.str.endswith(value)
        elif modifier == "contains":
            mask = present & text.str.contains(value, regex=False)
        elif modifier == "re":
            mask = present & text.str.contains(value, regex=True)
        elif modifier == "in":
            mask = col.isin(value)
        else:
            raise ValueError(f"Unknown filter modifier {modifier!r} in {key!r}")
        df = df[mask]
    return df


def _select(df: pd.DataFrame, logic: dict) -> pd.DataFrame:
    return apply_filters(df[df["event_type"] == logic["event_type"]], logic.get("filters"))


# Both windowed matchers below fire the moment their threshold is crossed,
# then treat the rest of that window as part of the same alert — the way a
# SIEM groups follow-up events into an open alert instead of paging again.
# That keeps the evidence complete (a fan-out's later targets belong to the
# alert, and correlation needs them), and after the window the rule re-arms,
# so a second burst from the same source days later raises a second alert.


def _match_threshold_then_success(df: pd.DataFrame, rule: dict) -> list[dict]:
    """Fires the moment N failures land within window_minutes of each other
    for the same group; if a success follows in the same window the
    severity is escalated (likely account compromise, not just noise)."""
    logic = rule["logic"]
    sub = _select(df, logic)
    if sub.empty:
        return []
    window = pd.Timedelta(minutes=logic["window_minutes"])
    min_failures = logic["min_failures"]
    alerts = []
    for key, g in sub.groupby(logic["group_by"]):
        g = g.sort_values("ts").reset_index(drop=True)
        failures = g[g["action"] == logic["failure_action"]].reset_index(drop=True)
        fail_times = failures["ts"]
        i = 0
        while i + min_failures - 1 < len(failures):
            if fail_times[i + min_failures - 1] - fail_times[i] > window:
                i += 1
                continue
            triggered_at = fail_times[i + min_failures - 1]
            window_end = triggered_at + window
            burst = failures[(fail_times >= fail_times[i]) & (fail_times <= window_end)]
            successes = g[
                (g["action"] == logic["success_action"]) & (g["ts"] >= triggered_at) & (g["ts"] <= window_end)
            ]
            compromised = not successes.empty
            description = f"{len(burst)} failed logins within {logic['window_minutes']} minutes"
            description += (
                ", followed by a successful login — the account may be compromised."
                if compromised
                else "; no successful login observed in the same window."
            )
            alerts.append(_alert(
                rule, triggered_at, _entity_label(key), description,
                pd.concat([burst, successes]), severity="critical" if compromised else None,
            ))
            i = int(fail_times.searchsorted(window_end, side="right"))
    return alerts


def _match_distinct_count(df: pd.DataFrame, rule: dict) -> list[dict]:
    """Sliding-window distinct-value count — e.g. how many different
    destination ports one source touched on one host within N minutes."""
    logic = rule["logic"]
    sub = _select(df, logic)
    if sub.empty:
        return []
    window = pd.Timedelta(minutes=logic["window_minutes"])
    distinct_field = logic["distinct_field"]
    min_distinct = logic["min_distinct"]
    alerts = []
    for key, g in sub.groupby(logic["group_by"]):
        g = g.sort_values("ts").reset_index(drop=True)
        times = g["ts"].tolist()
        values = g[distinct_field].tolist()
        start, end = 0, 0
        counts: dict = {}
        while end < len(times):
            counts[values[end]] = counts.get(values[end], 0) + 1
            while times[end] - times[start] > window:
                counts[values[start]] -= 1
                if counts[values[start]] == 0:
                    del counts[values[start]]
                start += 1
            if len(counts) < min_distinct:
                end += 1
                continue
            until = times[end] + window
            burst = g[(g["ts"] >= times[start]) & (g["ts"] <= until)]
            alerts.append(_alert(
                rule, times[end], _entity_label(key),
                f"{burst[distinct_field].nunique()} distinct {distinct_field} values in one burst "
                f"(fired on reaching {min_distinct} within {logic['window_minutes']} minutes).",
                burst,
            ))
            end = int(g["ts"].searchsorted(until, side="right"))
            start, counts = end, {}
    return alerts


def _match_impossible_travel(df: pd.DataFrame, rule: dict) -> list[dict]:
    logic = rule["logic"]
    sub = df[(df["event_type"] == "auth") & (df["action"] == logic["success_action"])]
    if sub.empty:
        return []
    max_speed = logic["max_speed_kmh"]
    alerts = []
    for user, g in sub.groupby("user"):
        g = g.sort_values("ts").reset_index(drop=True)
        for i in range(1, len(g)):
            prev, cur = g.iloc[i - 1], g.iloc[i]
            if prev["src_country"] == cur["src_country"]:
                continue
            if prev["src_country"] not in COUNTRY_GEO or cur["src_country"] not in COUNTRY_GEO:
                continue
            hours = (cur["ts"] - prev["ts"]).total_seconds() / 3600
            lat1, lon1 = COUNTRY_GEO[prev["src_country"]]
            lat2, lon2 = COUNTRY_GEO[cur["src_country"]]
            speed = implied_speed_kmh(lat1, lon1, lat2, lon2, hours)
            if speed <= max_speed:
                continue
            minutes = round((cur["ts"] - prev["ts"]).total_seconds() / 60)
            # The host a remote login lands on is incidental; the account and
            # the two source addresses are what this alert is about.
            alerts.append(_alert(
                rule, cur["ts"], str(user),
                f"Login from {prev['src_country']} then {cur['src_country']} "
                f"{minutes} min apart implies {int(speed):,} km/h travel.",
                g.iloc[[i - 1, i]], kinds=("users", "ips"),
            ))
    return alerts


def _match_volume_spike(df: pd.DataFrame, rule: dict) -> list[dict]:
    """Outbound bytes per host over a sliding window. Fires at the event that
    pushes the window over the threshold — the moment a streaming pipeline
    would know — then stays quiet for suppress_minutes, so one sustained
    transfer is one alert rather than one per window. Evidence is the
    destinations that carried the bulk of the volume, not every connection
    the host made in that time."""
    logic = rule["logic"]
    sub = df[(df["event_type"] == "network") & (df["direction"] == "outbound")]
    sub = sub[~sub["dst_ip"].astype(str).str.startswith(logic.get("internal_prefix", "10.10."))]
    if sub.empty:
        return []
    window = pd.Timedelta(minutes=logic["window_minutes"])
    suppress = pd.Timedelta(minutes=logic.get("suppress_minutes", logic["window_minutes"]))
    threshold = logic["bytes_sent_threshold"]
    alerts = []
    for host, g in sub.groupby("host"):
        g = g.sort_values("ts").reset_index(drop=True)
        times = g["ts"].tolist()
        sizes = g["bytes_sent"].fillna(0).tolist()
        start, total, quiet_until = 0, 0, None
        for end in range(len(g)):
            total += sizes[end]
            while times[end] - times[start] > window:
                total -= sizes[start]
                start += 1
            if total < threshold or (quiet_until is not None and times[end] <= quiet_until):
                continue
            quiet_until = times[end] + suppress
            trigger = g.iloc[start:end + 1]
            by_dest = trigger.groupby("dst_ip")["bytes_sent"].sum()
            major = by_dest[by_dest >= 0.2 * by_dest.sum()]
            if major.empty:  # volume spread thinly across many destinations
                major = by_dest.nlargest(1)
            evidence = g[
                (g["ts"] >= times[start]) & (g["ts"] <= quiet_until) & g["dst_ip"].isin(major.index)
            ]
            mb = evidence["bytes_sent"].sum() / 1_000_000
            alerts.append(_alert(
                rule, times[end], str(host),
                f"{host} sent {mb:,.1f} MB outbound to {', '.join(major.index)} "
                f"({len(evidence)} transfers); crossed {threshold / 1_000_000:.0f} MB "
                f"within {logic['window_minutes']} minutes.",
                evidence,
            ))
    return alerts


def _match_pattern(df: pd.DataFrame, rule: dict) -> list[dict]:
    """Regex match on one field (Sigma's `field|re`). Matches for the same
    group are sessionized — a burst of suspicious commands on one host is
    one alert, not one per command."""
    logic = rule["logic"]
    sub = _select(df, logic)
    field = logic["field"]
    if sub.empty or field not in sub:
        return []
    text = sub[field].fillna("").astype(str)
    mask = pd.Series(False, index=sub.index)
    for pattern in logic["patterns"]:
        mask |= text.str.contains(pattern, regex=True)
    hits = sub[mask]
    if hits.empty:
        return []
    gap = pd.Timedelta(minutes=logic["window_minutes"])
    alerts = []
    for key, g in hits.groupby(logic["group_by"]):
        g = g.sort_values("ts")
        burst_ids = (g["ts"].diff() > gap).cumsum()
        for _, burst in g.groupby(burst_ids):
            example = _truncate(str(burst[field].iloc[0]), 110)
            alerts.append(_alert(
                rule, burst["ts"].iloc[0], _entity_label(key),
                f"{len(burst)} matching {field} value(s), e.g. {example}",
                burst,
            ))
    return alerts


MATCHERS = {
    "threshold_then_success": _match_threshold_then_success,
    "distinct_count": _match_distinct_count,
    "impossible_travel": _match_impossible_travel,
    "volume_spike": _match_volume_spike,
    "pattern_match": _match_pattern,
}


def run_rules(df: pd.DataFrame, rules: list[dict] | None = None) -> list[dict]:
    rules = rules if rules is not None else load_rules()
    alerts: list[dict] = []
    for rule in rules:
        alerts.extend(MATCHERS[rule["logic"]["type"]](df, rule))
    return alerts
