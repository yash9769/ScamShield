"""The attack graph of one incident: who did what to whom, in what order.

Nodes are the incident's entities: external addresses, domains, hosts and
accounts. Edges come from the evidence events of its rule alerts, not from
the alerts' entity lists, because an entity list is an unordered set and an
edge needs a direction:

* an inbound connection or a logon:  source (external IP, or the host behind
  an internal IP) -> host, labelled with the account used;
* a successful logon from outside, or a process: account -> host;
* an outbound transfer:              host -> external IP;
* a DNS lookup:                      host -> domain.

An anomaly alert's evidence is everything its host did in an hour, mostly
ordinary traffic, so it contributes only DNS lookups of rare domains (the
same rule ioc.py uses). That is how a C2 domain caught only by anomaly
detection still appears on the graph.

`layout` places nodes in swimlanes by kind (external, hosts, accounts) and
left to right in the order they first appear, so the graph reads as a
sequence of steps. Order rather than clock time: a lateral fan-out to six
servers in fifteen minutes would otherwise pile into one corner after a
two-hour gap.
"""

from __future__ import annotations

from dataclasses import dataclass, field

import pandas as pd

from .. import mitre
from .entities import _IP_TO_HOST, is_internal
from .ioc import rare_domains

LANES = {"ip": 2.0, "domain": 2.0, "host": 1.0, "user": 0.0}
LANE_LABELS = {2.0: "External", 1.0: "Hosts", 0.0: "Accounts"}
ANOMALY_SOURCE = "anomaly_isolation_forest"


@dataclass
class Edge:
    source: str
    target: str
    technique: str
    tactic: str
    first: pd.Timestamp
    last: pd.Timestamp
    count: int = 0
    actions: set[str] = field(default_factory=set)


def _node(kind: str, value: str) -> str:
    return f"{kind}:{value}"


def _endpoint(ip) -> str | None:
    if not isinstance(ip, str) or not ip:
        return None
    if is_internal(ip):
        return _node("host", _IP_TO_HOST[ip]) if ip in _IP_TO_HOST else None
    return _node("ip", ip)


def _event_edges(event) -> list[tuple[str, str, str]]:
    """(source node, target node, action) pairs one event implies."""
    host = _node("host", event["host"]) if isinstance(event.get("host"), str) else None
    user = _node("user", event["user"]) if isinstance(event.get("user"), str) else None
    kind = event["event_type"]
    out = []
    if kind == "auth" and host:
        source = _endpoint(event.get("src_ip"))
        failed = event.get("outcome") == "failure"
        as_user = f" as {event['user']}" if user else ""
        if source and source != host:
            out.append((source, host, ("failed logon" if failed else "logon") + as_user))
        # Host-to-host logons carry the account in the edge's label; a
        # separate account edge per hop would repeat it once per target.
        if user and not failed and not (source or "").startswith("host:"):
            out.append((user, host, "logged on"))
    elif kind == "network" and host:
        if event.get("direction") == "inbound":
            source = _endpoint(event.get("src_ip"))
            if source and source != host:
                out.append((source, host, f"inbound :{int(event['port'])}" if pd.notna(event.get("port")) else "inbound"))
        else:
            target = _endpoint(event.get("dst_ip"))
            if target and target != host:
                out.append((host, target, "outbound transfer"))
    elif kind == "dns" and host and isinstance(event.get("domain"), str):
        out.append((host, _node("domain", event["domain"]), "DNS lookup"))
    elif kind == "process" and host and user:
        out.append((user, host, f"ran {event.get('process_name') or 'a process'}"))
    return out


def build(members: pd.DataFrame, events: pd.DataFrame) -> tuple[pd.DataFrame, list[Edge]]:
    """Nodes (id, kind, label, first_seen, alerts) and edges for one incident."""
    by_id = events.set_index("event_id", drop=False)
    edges: dict[tuple[str, str, str], Edge] = {}
    alert_count: dict[str, int] = {}
    rare = rare_domains(events)

    for _, alert in members.iterrows():
        for kind, values in (alert["entities"] or {}).items():
            for value in values:
                node = _node({"hosts": "host", "users": "user", "ips": "ip"}[kind], value)
                alert_count[node] = alert_count.get(node, 0) + 1
        technique = alert["mitre_technique"] if isinstance(alert["mitre_technique"], str) else "unattributed"
        tactic = mitre.describe(technique)["tactic"] if technique != "unattributed" else "Unattributed"
        evidence = by_id.loc[by_id.index.intersection(alert["event_ids"])]
        if alert["source"] == ANOMALY_SOURCE:
            evidence = evidence[(evidence["event_type"] == "dns") & evidence["domain"].isin(rare)]
        for _, event in evidence.iterrows():
            for source, target, action in _event_edges(event):
                key = (source, target, technique)
                edge = edges.get(key)
                if edge is None:
                    edge = edges[key] = Edge(source, target, technique, tactic, event["ts"], event["ts"])
                edge.count += 1
                edge.first = min(edge.first, event["ts"])
                edge.last = max(edge.last, event["ts"])
                edge.actions.add(action)

    # An unattributed edge (from an anomaly alert with no technique) that
    # duplicates an attributed one adds nothing but a second line: fold it in.
    for key in [k for k in edges if k[2] == "unattributed"]:
        twin = next((e for k, e in edges.items() if k[:2] == key[:2] and k[2] != "unattributed"), None)
        if twin is not None:
            extra = edges.pop(key)
            twin.count += extra.count
            twin.first, twin.last = min(twin.first, extra.first), max(twin.last, extra.last)
            twin.actions |= extra.actions

    first_seen: dict[str, pd.Timestamp] = {}
    for edge in edges.values():
        for node in (edge.source, edge.target):
            first_seen[node] = min(first_seen.get(node, edge.first), edge.first)
    # Entities only anomaly alerts mention still belong on the graph, placed
    # at that alert's time.
    for _, alert in members.iterrows():
        for node in alert_count:
            if node not in first_seen and node.split(":", 1)[1] in sum((alert["entities"] or {}).values(), []):
                first_seen[node] = alert["ts"]

    rows = [{"id": node, "kind": node.split(":", 1)[0], "label": node.split(":", 1)[1],
             "first_seen": ts, "alerts": alert_count.get(node, 0)} for node, ts in first_seen.items()]
    nodes = pd.DataFrame(rows, columns=["id", "kind", "label", "first_seen", "alerts"])
    return nodes.sort_values("first_seen").reset_index(drop=True), sorted(edges.values(), key=lambda e: e.first)


def layout(nodes: pd.DataFrame, row_step: float = 0.24) -> pd.DataFrame:
    """x = order of first appearance (nodes first seen at the same moment
    share a column), y = lane plus a small offset when a lane already has a
    node in that column."""
    if nodes.empty:
        return nodes.assign(x=pd.Series(dtype=float), y=pd.Series(dtype=float))
    out = nodes.copy()
    out["x"] = out["first_seen"].rank(method="dense").astype(float) - 1
    out["y"] = out["kind"].map(LANES)
    for (lane, x), group in out.groupby([out["kind"].map(LANES), "x"]):
        for slot, idx in enumerate(group.sort_values("label").index):
            # Alternate above and below the lane line: 0, +1, -1, +2, -2 ...
            offset = (slot + 1) // 2 * (1 if slot % 2 else -1)
            out.at[idx, "y"] = lane + offset * row_step
    return out
