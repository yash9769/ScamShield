"""Threat intelligence: a reputation feed, an analyst watchlist, sightings,
retro-hunting, and DGA-style domain scoring.

**The feed** stands in for a commercial or community IP-reputation list. It
is built from the synthetic inventory's `known_malicious` flag, which was
set when the inventory was generated, before any attack ran. Scenarios draw
their attacker from that pool only some of the time (70%), so the feed
covers some attacks and misses others, much as a real list does. Feed
coverage of the attacks in the current dataset is measured, not assumed.

**The watchlist** holds indicators an analyst added, usually an incident's
IOCs. It is stored in the database (see storage.db) so it survives a
re-run of detection.

**Retro-hunting** (`sweep`) answers the first question after an IOC is
found: who else touched it, and when did that start? It searches every
event, not just the ones that raised alerts.

**Domain scoring** rates how machine-generated a domain looks (character
entropy, digits, length, and a cheap TLD). DGA malware cycles through such
names so a blocklist can't keep up. On this synthetic data the score
separates C2 domains from the 20 ordinary SaaS domains easily; real DNS
traffic has CDNs and tracking hosts that look random too.
"""

from __future__ import annotations

import hashlib
import math
from collections import Counter

import pandas as pd

from .detection.entities import is_internal
from .generator.entities import EXTERNAL_IPS

FEED_NAMES = ("community-blocklist", "honeypot-network", "abuse-reports")
SUSPICIOUS_TLDS = {"info", "top", "xyz", "biz", "click", "gq", "tk"}
INDICATOR_COLUMNS = ["type", "value", "source", "confidence", "note"]
SIGHTING_COLUMNS = ["ts", "type", "value", "host", "user", "direction", "event_type", "event_id"]


def _stable(value: str, n: int) -> int:
    return int(hashlib.sha1(value.encode()).hexdigest(), 16) % n


def feed() -> pd.DataFrame:
    """The reputation feed: one row per known-bad external address."""
    rows = []
    for ip in EXTERNAL_IPS:
        if not ip.known_malicious:
            continue
        rows.append({
            "type": "ip", "value": ip.ip,
            "source": FEED_NAMES[_stable(ip.ip, len(FEED_NAMES))],
            "confidence": 60 + _stable(ip.ip + "c", 40),
            "note": f"reported infrastructure, geolocated {ip.country}",
        })
    return pd.DataFrame(rows, columns=INDICATOR_COLUMNS)


def indicator_type(value: str) -> str:
    parts = value.split(".")
    if len(parts) == 4 and all(p.isdigit() for p in parts):
        return "ip"
    return "domain"


def sightings(events: pd.DataFrame, indicators: pd.DataFrame) -> pd.DataFrame:
    """Every event touching an indicator: an IP as source or destination, a
    domain as a DNS query."""
    if indicators.empty or events.empty:
        return pd.DataFrame(columns=SIGHTING_COLUMNS)
    ips = set(indicators.loc[indicators["type"] == "ip", "value"])
    domains = {d.lower() for d in indicators.loc[indicators["type"] == "domain", "value"]}
    frames = []
    for column, direction in (("src_ip", "inbound"), ("dst_ip", "outbound")):
        hit = events[events[column].isin(ips)]
        if not hit.empty:
            frames.append(hit.assign(type="ip", value=hit[column], direction=direction))
    if domains:
        hit = events[events["domain"].str.lower().isin(domains)]
        if not hit.empty:
            frames.append(hit.assign(type="domain", value=hit["domain"], direction="dns query"))
    if not frames:
        return pd.DataFrame(columns=SIGHTING_COLUMNS)
    return pd.concat(frames)[SIGHTING_COLUMNS].sort_values("ts").reset_index(drop=True)


def summarize(found: pd.DataFrame, indicators: pd.DataFrame, alerts: pd.DataFrame) -> pd.DataFrame:
    """Per indicator: how often it was seen, by how many hosts, and whether
    any alert covered one of those events. An indicator that is seen but
    never alerted on is a detection gap worth a look."""
    columns = ["type", "value", "source", "confidence", "events", "hosts", "first_seen", "last_seen", "alerted"]
    if found.empty:
        return pd.DataFrame(columns=columns)
    alerted_events = {e for ids in alerts["event_ids"] for e in ids} if not alerts.empty else set()
    stats = found.groupby(["type", "value"]).agg(
        events=("event_id", "size"),
        hosts=("host", "nunique"),
        first_seen=("ts", "min"),
        last_seen=("ts", "max"),
        alerted=("event_id", lambda ids: bool(set(ids) & alerted_events)),
    ).reset_index()
    meta = indicators.drop_duplicates(["type", "value"])[["type", "value", "source", "confidence"]]
    out = stats.merge(meta, on=["type", "value"], how="left")
    return out[columns].sort_values(["alerted", "events"], ascending=[True, False]).reset_index(drop=True)


def sweep(events: pd.DataFrame, values: list[str]) -> pd.DataFrame:
    """Retro-hunt: every host that touched any of `values`, with first and
    last contact and how. One row per (indicator, host)."""
    values = [v.strip() for v in values if v and v.strip()]
    if not values:
        return pd.DataFrame(columns=["value", "host", "first_contact", "last_contact", "events", "how", "users"])
    indicators = pd.DataFrame({"type": [indicator_type(v) for v in values], "value": values})
    found = sightings(events, indicators)
    if found.empty:
        return pd.DataFrame(columns=["value", "host", "first_contact", "last_contact", "events", "how", "users"])
    out = found.groupby(["value", "host"]).agg(
        first_contact=("ts", "min"),
        last_contact=("ts", "max"),
        events=("event_id", "size"),
        how=("direction", lambda s: ", ".join(sorted(set(s)))),
        users=("user", lambda s: ", ".join(sorted(set(s.dropna())))),
    ).reset_index()
    return out.sort_values("first_contact").reset_index(drop=True)


def feed_coverage(events: pd.DataFrame, indicators: pd.DataFrame) -> dict:
    """Of the external addresses that took part in injected attacks, how
    many did the feed already list? Uses ground truth, so it is evaluation,
    not detection."""
    if "scenario_id" not in events:
        return {"attack_ips": 0, "listed": 0}
    attack = events[events["scenario_id"].notna()]
    ips = {ip for col in ("src_ip", "dst_ip") for ip in attack[col].dropna() if not is_internal(ip)}
    listed = ips & set(indicators.loc[indicators["type"] == "ip", "value"])
    return {"attack_ips": len(ips), "listed": len(listed)}


def _entropy(text: str) -> float:
    if not text:
        return 0.0
    counts = Counter(text)
    return -sum(c / len(text) * math.log2(c / len(text)) for c in counts.values())


def domain_score(domain: str) -> float:
    """0..1, higher = more machine-generated. Scores the label left of the
    registrable suffix: entropy, digit share, length, plus a cheap TLD."""
    parts = domain.lower().strip(".").split(".")
    if len(parts) < 2:
        return 0.0
    label, tld = parts[-2], parts[-1]
    entropy = min(_entropy(label) / 3.8, 1.0)
    digits = sum(ch.isdigit() for ch in label) / len(label)
    length = min(max(len(label) - 6, 0) / 10, 1.0)
    score = 0.45 * entropy + 0.25 * min(digits * 3, 1.0) + 0.15 * length + 0.15 * (tld in SUSPICIOUS_TLDS)
    return round(score, 3)


def suspicious_domains(events: pd.DataFrame, limit: int = 15) -> pd.DataFrame:
    dns = events[(events["event_type"] == "dns") & events["domain"].notna()]
    if dns.empty:
        return pd.DataFrame(columns=["domain", "score", "queries", "hosts", "first_seen"])
    out = dns.groupby("domain").agg(queries=("event_id", "size"), hosts=("host", "nunique"),
                                    first_seen=("ts", "min")).reset_index()
    out["score"] = out["domain"].map(domain_score)
    return out[["domain", "score", "queries", "hosts", "first_seen"]].sort_values("score", ascending=False).head(limit).reset_index(drop=True)
