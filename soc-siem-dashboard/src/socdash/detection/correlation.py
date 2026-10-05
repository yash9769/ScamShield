"""Alert correlation: group alerts into incidents.

Two alerts belong to the same incident when they share an entity (host,
user, or external IP) and fired within `link_window_hours` of each other.
Grouping is transitive (union-find), so a chain like

    scan(IP A → gateway) → brute force(IP A, user U) → PowerShell(U on WKS-12)
    → lateral movement(WKS-12 → DB-01) → exfiltration(DB-01 → IP A)

becomes one incident even though its first and last alerts share nothing
directly — which is the whole point: an analyst should see one intrusion,
not five unrelated pages.
"""

from __future__ import annotations

import uuid
from collections import Counter, defaultdict

import pandas as pd

from .. import mitre
from . import entities as entity_util

SEVERITY_ORDER = ["low", "medium", "high", "critical"]
SEVERITY_WEIGHT = {"low": 1, "medium": 3, "high": 6, "critical": 10}


class _UnionFind:
    def __init__(self, n: int) -> None:
        self.parent = list(range(n))

    def find(self, i: int) -> int:
        while self.parent[i] != i:
            self.parent[i] = self.parent[self.parent[i]]
            i = self.parent[i]
        return i

    def union(self, a: int, b: int) -> None:
        ra, rb = self.find(a), self.find(b)
        if ra != rb:
            self.parent[rb] = ra


def _primary_entity(alerts: list[dict]) -> str | None:
    """The entity most of the incident's alerts mention — hosts first, since
    that's what an analyst pivots to — used to make titles distinguishable."""
    for kind in entity_util.KINDS:
        counts = Counter(v for a in alerts for v in (a.get("entities") or {}).get(kind, []))
        if counts:
            return counts.most_common(1)[0][0]
    return None


def _title(alerts: list[dict], tactics: list[str]) -> str:
    if len(tactics) >= 4:
        return f"Multi-stage attack across {len(tactics)} ATT&CK tactics"
    if len(tactics) >= 2:
        return " → ".join(tactics)
    lead = max(alerts, key=lambda a: SEVERITY_ORDER.index(a["severity"]))
    return lead["title"] if len(alerts) == 1 else f"{lead['title']} (+{len(alerts) - 1} related)"


def _summarize(alerts: list[dict]) -> dict:
    alerts = sorted(alerts, key=lambda a: pd.Timestamp(a["ts"]))
    # Matrix order, not alert-time order: anomaly alerts are stamped at the
    # start of their hour, so time order can put a stage before the one that
    # caused it. The dashboard timeline shows the real sequence.
    tactics = sorted({a["mitre_tactic"] for a in alerts if a.get("mitre_tactic")}, key=mitre.tactic_rank)

    severity = max((a["severity"] for a in alerts), key=SEVERITY_ORDER.index)
    # Three or more distinct tactics is an attack progressing, not noise —
    # escalate regardless of how severe each individual alert looked.
    if len(tactics) >= 3:
        severity = "critical"
    breadth = 1 + 0.5 * max(0, len(tactics) - 1)
    score = round(sum(SEVERITY_WEIGHT.get(a["severity"], 1) for a in alerts) * breadth, 1)

    title = _title(alerts, tactics)
    primary = _primary_entity(alerts)
    if primary:
        title += f" · {primary}"

    merged = {kind: sorted({v for a in alerts for v in (a.get("entities") or {}).get(kind, [])})
              for kind in entity_util.KINDS}
    return {
        "incident_id": f"INC-{uuid.uuid4().hex[:6].upper()}",
        "first_seen": pd.Timestamp(alerts[0]["ts"]),
        "last_seen": pd.Timestamp(alerts[-1]["ts"]),
        "title": title,
        "severity": severity,
        "score": score,
        "alert_count": len(alerts),
        "tactics": tactics,
        "entities": merged,
        "sources": sorted({a["source"] for a in alerts}),
        "status": "new",
    }


def correlate(alerts: list[dict], link_window_hours: float = 3.0) -> list[dict]:
    """Sets `incident_id` on every alert dict (in place) and returns one
    summary per incident, highest score first."""
    if not alerts:
        return []
    window = pd.Timedelta(hours=link_window_hours)
    times = [pd.Timestamp(a["ts"]) for a in alerts]
    uf = _UnionFind(len(alerts))

    by_entity: dict[tuple[str, str], list[int]] = defaultdict(list)
    for i, alert in enumerate(alerts):
        for key in entity_util.keys(alert.get("entities")):
            by_entity[key].append(i)
    for members in by_entity.values():
        members.sort(key=lambda i: times[i])
        # Linking time-adjacent pairs is enough: if a~b and b~c are each
        # within the window, union-find already joins a, b and c.
        for prev, cur in zip(members, members[1:]):
            if times[cur] - times[prev] <= window:
                uf.union(prev, cur)

    groups: dict[int, list[int]] = defaultdict(list)
    for i in range(len(alerts)):
        groups[uf.find(i)].append(i)

    incidents = []
    for members in groups.values():
        incident = _summarize([alerts[i] for i in members])
        for i in members:
            alerts[i]["incident_id"] = incident["incident_id"]
        incidents.append(incident)
    incidents.sort(key=lambda inc: inc["score"], reverse=True)
    return incidents


def kill_chain_stages(tactics: list[str]) -> list[tuple[str, bool]]:
    """Every ATT&CK tactic in matrix order, flagged by whether this incident
    touched it — the data behind the kill-chain strip in the dashboard."""
    seen = set(tactics)
    return [(tactic, tactic in seen) for tactic in mitre.TACTIC_ORDER]
